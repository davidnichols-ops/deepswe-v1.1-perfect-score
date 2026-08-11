#!/usr/bin/env bash
# DeepSWE v1.1 — Re-verification Script
#
# Re-runs the verifier for one or all tasks and checks the result matches
# the published reward.json. Requires Docker and the task definitions
# in benchmarks/deep-swe/tasks/.
#
# Usage:
#   ./verify.sh <task-id>          # verify a single task
#   ./verify.sh --all              # verify all 113 tasks
#   ./verify.sh --random N         # verify N random tasks
#   ./verify.sh --check            # only verify checksums, don't run Docker
#
# Prerequisites:
#   - Docker installed and running
#   - This repo cloned with benchmarks/ and orchestrator/ intact
#   - Network access to public.ecr.aws (for pulling Docker images)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BENCH_DIR="$REPO_ROOT/benchmarks/deep-swe/tasks"
ORCH_DIR="$REPO_ROOT/orchestrator"
RESULTS_DIR="$REPO_ROOT/results/raw/manual"
TMP_DIR="/tmp/deepswe-verify"

# Colors
red() { printf '\033[0;31m%s\033[0m\n' "$1"; }
green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }

# Verify a single task
verify_task() {
    local task="$1"
    local task_dir="$BENCH_DIR/$task"

    if [ ! -d "$task_dir" ]; then
        red "ERROR: Task '$task' not found in $BENCH_DIR"
        return 1
    fi

    if [ ! -f "$ORCH_DIR/${task}_model.patch" ]; then
        red "ERROR: No model.patch for '$task' in $ORCH_DIR"
        return 1
    fi

    # Get the Docker image from task.toml
    local img
    img=$(grep 'docker_image' "$task_dir/task.toml" | head -1 | sed 's/.*= "//;s/".*//')
    if [ -z "$img" ]; then
        red "ERROR: No docker_image found in $task_dir/task.toml"
        return 1
    fi

    local vname="deepswe-verify-$task"
    local work_dir="$TMP_DIR/$task"

    echo "── Verifying: $task ──"
    echo "   Image: $img"

    # Clean up any previous run
    rm -rf "$work_dir"
    mkdir -p "$work_dir/artifacts"
    cp "$ORCH_DIR/${task}_model.patch" "$work_dir/artifacts/model.patch"

    # Pull the base image
    echo "   Pulling base image..."
    if ! docker pull "$img" >/dev/null 2>&1; then
        yellow "   WARN: Pull failed (may already be cached)"
    fi

    # Build the verifier image
    echo "   Building verifier..."
    if ! docker build -t "$vname" "$task_dir/tests/" >/dev/null 2>&1; then
        red "   FAIL: Verifier build failed"
        return 1
    fi

    # Run the verifier
    echo "   Running tests..."
    local exit_code=0
    docker run --rm -v "$work_dir:/logs" "$vname" /tests/test.sh >/dev/null 2>&1 || exit_code=$?

    # Check the result
    local new_reward="$work_dir/verifier/reward.json"
    local published_reward="$RESULTS_DIR/$task/logs/verifier/reward.json"

    if [ ! -f "$new_reward" ]; then
        red "   FAIL: No reward.json produced (verifier crashed, exit=$exit_code)"
        return 1
    fi

    # Compare rewards
    local new_r published_r
    new_r=$(python3 -c "import json; print(json.load(open('$new_reward'))['reward'])")
    published_r=$(python3 -c "import json; print(json.load(open('$published_reward'))['reward'])")

    if [ "$new_r" != "$published_r" ]; then
        red "   MISMATCH: published reward=$published_r, re-verified reward=$new_r"
        return 1
    fi

    # Compare test counts
    local new_f2p new_p2p pub_f2p pub_p2p
    new_f2p=$(python3 -c "import json; d=json.load(open('$new_reward')); print(f\"{d['f2p_passed']}/{d['f2p_total']}\")")
    new_p2p=$(python3 -c "import json; d=json.load(open('$new_reward')); print(f\"{d['p2p_passed']}/{d['p2p_total']}\")")
    pub_f2p=$(python3 -c "import json; d=json.load(open('$published_reward')); print(f\"{d['f2p_passed']}/{d['f2p_total']}\")")
    pub_p2p=$(python3 -c "import json; d=json.load(open('$published_reward')); print(f\"{d['p2p_passed']}/{d['p2p_total']}\")")

    if [ "$new_f2p" != "$pub_f2p" ] || [ "$new_p2p" != "$pub_p2p" ]; then
        yellow "   WARN: Reward matches ($new_r) but test counts differ"
        echo "   F2P: published=$pub_f2p, re-verified=$new_f2p"
        echo "   P2P: published=$pub_p2p, re-verified=$new_p2p"
    else
        green "   PASS: reward=$new_r, F2P=$new_f2p, P2P=$new_p2p"
    fi

    # Clean up Docker
    docker rmi "$vname" >/dev/null 2>&1 || true
    rm -rf "$work_dir"

    return 0
}

# Verify checksums only
verify_checksums() {
    echo "── Verifying checksums ──"
    local checksums_file="$SCRIPT_DIR/checksums.sha256"
    if [ ! -f "$checksums_file" ]; then
        red "ERROR: $checksums_file not found"
        return 1
    fi
    cd "$REPO_ROOT"
    if shasum -a 256 -c --quiet "$checksums_file" 2>/dev/null; then
        green "   All $(grep -c '  ' "$checksums_file") checksums verified"
        return 0
    else
        red "   CHECKSUM MISMATCH detected"
        shasum -a 256 -c "$checksums_file" 2>&1 | grep -v "OK$" || true
        return 1
    fi
}

# Main
case "${1:-}" in
    --check)
        verify_checksums
        ;;
    --all)
        mkdir -p "$TMP_DIR"
        pass=0
        fail=0
        tasks=$(ls "$RESULTS_DIR")
        total=$(echo "$tasks" | wc -l)
        for task in $tasks; do
            if verify_task "$task"; then
                pass=$((pass + 1))
            else
                fail=$((fail + 1))
            fi
            echo "   Progress: $((pass + fail))/$total"
        done
        echo ""
        echo "═══ Results: $pass passed, $fail failed out of $total ═══"
        [ "$fail" -eq 0 ] && green "ALL VERIFIED" || red "SOME FAILED"
        ;;
    --random)
        N="${2:-5}"
        mkdir -p "$TMP_DIR"
        tasks=$(ls "$RESULTS_DIR" | shuf -n "$N")
        pass=0
        fail=0
        for task in $tasks; do
            if verify_task "$task"; then
                pass=$((pass + 1))
            else
                fail=$((fail + 1))
            fi
        done
        echo ""
        echo "═══ Results: $pass passed, $fail failed out of $N random ═══"
        [ "$fail" -eq 0 ] && green "ALL VERIFIED" || red "SOME FAILED"
        ;;
    "")
        echo "Usage: $0 <task-id> | --all | --random N | --check"
        exit 1
        ;;
    *)
        mkdir -p "$TMP_DIR"
        verify_task "$1"
        ;;
esac
