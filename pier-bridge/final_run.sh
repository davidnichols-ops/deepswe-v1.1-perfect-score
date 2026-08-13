#!/usr/bin/env bash
# final_run.sh — Definitive Pier bridge runner for all 113 DeepSWE tasks
# Handles: patch application (chunked for large patches), Docker cleanup, monitoring
#
# Usage: bash final_run.sh

set -uo pipefail

REPO_ROOT="/Users/david/aa-coding-index"
BRIDGE_ROOT="/tmp/pier-bridge"
JOBS_DIR="/tmp/pier-full-run-final"
PATCH_BASE="$REPO_ROOT/results/raw/manual"
TASKS_FILE="/tmp/published_tasks.txt"
PROGRESS_FILE="$JOBS_DIR/progress.txt"
FAIL_LOG="$JOBS_DIR/failures.txt"

mkdir -p "$JOBS_DIR" "$BRIDGE_ROOT"
rm -rf "$BRIDGE_ROOT"/*
touch "$PROGRESS_FILE" "$FAIL_LOG"

# ─── Helpers ───

find_task_name() {
    local truncated="$1"
    while IFS= read -r task; do
        if [[ "$task" == "$truncated"* ]]; then
            echo "$task"
            return 0
        fi
    done < "$TASKS_FILE"
    return 1
}

send_and_wait() {
    local bridge="$1"
    local cmd="$2"
    echo "$cmd" > "$bridge/command.txt"
    echo "COMMAND_READY" > "$bridge/status"
    for i in $(seq 1 180); do
        local status
        status=$(cat "$bridge/status" 2>/dev/null)
        if [ "$status" = "OUTPUT_READY" ]; then
            cat "$bridge/output.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f'exit={d[\"return_code\"]}')
print(d['stdout'][:2000])
if d.get('stderr'):
    print('--- stderr ---')
    print(d['stderr'][:1000])
" 2>/dev/null
            return 0
        fi
        sleep 1
    done
    echo "TIMEOUT"
    return 1
}

apply_patch() {
    local session_id="$1"
    local task_name="$2"
    local bridge="$BRIDGE_ROOT/$session_id"
    local patch_file="$PATCH_BASE/$task_name/logs/artifacts/model.patch"

    if [ ! -f "$patch_file" ]; then
        echo "  SKIP: No patch for $task_name"
        echo "$task_name|no_patch" >> "$PROGRESS_FILE"
        touch "$bridge/done"
        echo "DONE" > "$bridge/status"
        return 1
    fi

    local b64_size
    b64_size=$(base64 < "$patch_file" | wc -c)
    echo "  Patch: ${b64_size} b64 bytes"

    if [ "$b64_size" -lt 100000 ]; then
        # Small patch: inline
        local b64
        b64=$(base64 < "$patch_file")
        local cmd="echo '$b64' | base64 -d > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@e.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'OK'"
        local result
        result=$(send_and_wait "$bridge" "$cmd")
        echo "$result" | head -2
    else
        # Large patch: chunked write
        echo "  Large patch — chunking..."
        local b64_full
        b64_full=$(base64 < "$patch_file")
        local total_len=${#b64_full}
        local offset=1
        local chunk_num=1
        while [ $offset -le $total_len ]; do
            local end=$((offset + 49999))
            if [ $end -gt $total_len ]; then
                end=$total_len
            fi
            local chunk="${b64_full:offset-1:end-offset+1}"
            if [ $chunk_num -eq 1 ]; then
                cmd="echo -n '$chunk' > /tmp/model.patch.b64 && echo 'C1_OK'"
            else
                cmd="echo -n '$chunk' >> /tmp/model.patch.b64 && echo 'C${chunk_num}_OK'"
            fi
            result=$(send_and_wait "$bridge" "$cmd")
            if ! echo "$result" | grep -q "C${chunk_num}_OK"; then
                echo "  FAIL: chunk $chunk_num"
                echo "$task_name|chunk_fail" >> "$PROGRESS_FILE"
                touch "$bridge/done"
                echo "DONE" > "$bridge/status"
                return 1
            fi
            offset=$((end + 1))
            chunk_num=$((chunk_num + 1))
        done
        cmd="base64 -d /tmp/model.patch.b64 > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@e.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'OK'"
        result=$(send_and_wait "$bridge" "$cmd")
        echo "$result" | head -2
    fi

    local rc
    rc=$(cat "$bridge/output.json" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['return_code'])" 2>/dev/null || echo "?")
    if [ "$rc" = "0" ]; then
        echo "  ✓ $task_name"
        echo "$task_name|applied" >> "$PROGRESS_FILE"
    else
        echo "  ✗ $task_name (exit=$rc)"
        echo "$task_name|failed" >> "$PROGRESS_FILE"
        echo "$task_name" >> "$FAIL_LOG"
    fi
    touch "$bridge/done"
    echo "DONE" > "$bridge/status"
}

cleanup_docker() {
    docker container prune --force 2>/dev/null || true
    docker builder prune --all --force 2>/dev/null || true
    # Remove non-active images
    local active
    active=$(docker ps --format "{{.Image}}" 2>/dev/null | head -1)
    docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "^${active}$" | while read img; do
        docker rmi "$img" 2>/dev/null || true
    done
}

# ─── Start Pier ───
echo "=== Starting Pier for all 113 tasks ==="
cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT/pier-bridge" \
pier run \
  -p benchmarks/deep-swe/tasks \
  --agent-import-path "devin_bridge_agent:DevinBridgeAgent" \
  --model "devin-bridge" \
  --jobs-dir "$JOBS_DIR" \
  --agent-timeout-multiplier 0.5 \
  --verifier-timeout-multiplier 0.5 \
  --n-concurrent 1 \
  --n-attempts 1 \
  -y \
  --debug > "$JOBS_DIR/pier.log" 2>&1 &

PIER_PID=$!
echo $PIER_PID > "$JOBS_DIR/pier.pid"
echo "Pier PID: $PIER_PID"

# ─── Main loop ───
echo "Starting bridge handler loop..."
processed_sessions=""

while true; do
    # Check Pier
    if ! kill -0 "$PIER_PID" 2>/dev/null; then
        # Check for pending sessions
        pending=0
        for f in $(find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null); do
            session=$(basename $(dirname "$f"))
            if echo "$processed_sessions" | grep -qv "$session"; then
                pending=$((pending + 1))
            fi
        done
        if [ "$pending" -eq 0 ]; then
            echo ""
            echo "=== Pier finished. All tasks done. ==="
            break
        fi
        echo "Pier stopped but $pending sessions pending. Waiting..."
        sleep 10
        continue
    fi

    # Disk check — clean up if low
    free_gb=$(df -h / | awk 'NR==2{print $4}' | sed 's/Gi//' | sed 's/Mi/\/1000/' | bc 2>/dev/null || echo 99)
    if [ "$(echo "$free_gb < 8" | bc 2>/dev/null)" = "1" ]; then
        echo "[cleanup] Disk low (${free_gb}GB) — cleaning Docker..."
        cleanup_docker
        echo "[cleanup] After: $(df -h / | awk 'NR==2{print $4}')"
    fi

    # Process new bridge sessions
    for instr_file in $(find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null); do
        session_id=$(basename $(dirname "$instr_file"))
        # Skip if processed
        if echo "$processed_sessions" | grep -q "$session_id"; then
            continue
        fi
        # Skip if not ready
        status=$(cat "$BRIDGE_ROOT/$session_id/status" 2>/dev/null)
        if [ "$status" != "INSTRUCTION_READY" ]; then
            continue
        fi

        # Find task name
        truncated_name=$(find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -type d -name "*__*" 2>/dev/null | while read dir; do
            if [ ! -f "$dir/agent/trajectory.json" ]; then
                basename "$dir" | sed 's|__.*||'
                break
            fi
        done | head -1)

        if [ -z "$truncated_name" ]; then
            continue
        fi

        task_name=$(find_task_name "$truncated_name")
        if [ -z "$task_name" ]; then
            echo "WARN: Cannot match '$truncated_name'"
            continue
        fi

        echo ""
        echo "=== $(date +%H:%M:%S) Processing: $task_name ==="
        apply_patch "$session_id" "$task_name"
        processed_sessions="$processed_sessions $session_id"

        # Clean up Docker after each task
        cleanup_docker
    done

    sleep 3
done

# ─── Final report ───
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  FINAL RESULTS"
echo "════════════════════════════════════════════════════════════════"
total=$(wc -l < "$PROGRESS_FILE")
applied=$(grep -c "|applied|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
failed=$(grep -c "|failed|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
no_patch=$(grep -c "|no_patch|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
echo "  Total tasks: $total"
echo "  Applied: $applied"
echo "  Failed: $failed"
echo "  No patch: $no_patch"
echo ""
echo "=== Verifier Results ==="
find "$JOBS_DIR" -name "reward.json" 2>/dev/null | while read f; do
    python3 -c "import json; d=json.load(open('$f')); print(d['reward'])" 2>/dev/null
done | sort | uniq -c
echo ""
echo "=== Failed tasks ==="
cat "$FAIL_LOG" 2>/dev/null || echo "None"
echo ""
echo "════════════════════════════════════════════════════════════════"
