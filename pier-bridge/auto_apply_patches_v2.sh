#!/usr/bin/env bash
# auto_apply_patches_v2.sh — Automatically apply patches for all DeepSWE tasks
# Uses the Pier log to identify task names

set -euo pipefail

BRIDGE_ROOT="/tmp/pier-bridge"
PATCH_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/results/raw/manual"
JOBS_DIR="/tmp/pier-full-run"
PROGRESS_FILE="$JOBS_DIR/progress.txt"

mkdir -p "$JOBS_DIR"
touch "$PROGRESS_FILE"

# Find the task name for a bridge session by checking the most recent
# directory in the jobs folder that doesn't have a trajectory yet
find_task_name() {
    local session_id="$1"
    # Look for task directories (at depth 2, inside date directory) without trajectory.json
    find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -type d -name "*__*" 2>/dev/null | while read dir; do
        if [ ! -f "$dir/agent/trajectory.json" ]; then
            basename "$dir" | sed 's|__.*||'
            return
        fi
    done | head -1
}

# Apply a patch via bridge
apply_patch() {
    local session_id="$1"
    local task_name="$2"
    local bridge="$BRIDGE_ROOT/$session_id"
    local patch_file="$PATCH_BASE/$task_name/logs/artifacts/model.patch"

    if [ ! -f "$patch_file" ]; then
        echo "SKIP: No patch found for $task_name"
        echo "$task_name|$session_id|no_patch" >> "$PROGRESS_FILE"
        touch "$bridge/done"
        echo "DONE" > "$bridge/status"
        return 1
    fi

    local b64
    b64=$(base64 < "$patch_file")

    echo "echo '$b64' | base64 -d > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@example.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'PATCH_APPLIED_OK'" > "$bridge/command.txt"
    echo "COMMAND_READY" > "$bridge/status"

    for i in $(seq 1 120); do
        local status
        status=$(cat "$bridge/status" 2>/dev/null)
        if [ "$status" = "OUTPUT_READY" ]; then
            local rc
            rc=$(cat "$bridge/output.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['return_code'])" 2>/dev/null || echo "unknown")
            if [ "$rc" = "0" ]; then
                echo "OK: $task_name"
                echo "$task_name|$session_id|applied" >> "$PROGRESS_FILE"
            else
                echo "FAIL: $task_name (exit=$rc)"
                echo "$task_name|$session_id|failed" >> "$PROGRESS_FILE"
            fi
            touch "$bridge/done"
            echo "DONE" > "$bridge/status"
            return 0
        fi
        sleep 1
    done
    echo "TIMEOUT: $task_name"
    echo "$task_name|$session_id|timeout" >> "$PROGRESS_FILE"
    touch "$bridge/done"
    echo "DONE" > "$bridge/status"
    return 1
}

# Main loop
echo "Starting auto-apply loop v2..."
processed_sessions=""

while true; do
    # Check if Pier is still running
    PIER_PID=$(cat "$JOBS_DIR/pier.pid" 2>/dev/null || echo "")
    if [ -n "$PIER_PID" ] && ! kill -0 "$PIER_PID" 2>/dev/null; then
        # Check for pending sessions
        pending=0
        for f in $(find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null); do
            session=$(basename $(dirname "$f"))
            if echo "$processed_sessions" | grep -qv "$session"; then
                pending=$((pending + 1))
            fi
        done
        if [ "$pending" -eq 0 ]; then
            echo "All tasks completed. Exiting."
            break
        fi
    fi

    # Find new bridge sessions
    for instr_file in $(find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null); do
        session_id=$(basename $(dirname "$instr_file"))
        # Skip if already processed
        if echo "$processed_sessions" | grep -q "$session_id"; then
            continue
        fi
        # Skip if not ready
        status=$(cat "$BRIDGE_ROOT/$session_id/status" 2>/dev/null)
        if [ "$status" != "INSTRUCTION_READY" ]; then
            continue
        fi

        # Find task name
        task_name=$(find_task_name "$session_id")
        if [ -z "$task_name" ]; then
            continue
        fi

        echo "=== Processing: $task_name (session: $session_id) ==="
        apply_patch "$session_id" "$task_name"
        processed_sessions="$processed_sessions $session_id"
    done

    sleep 3
done

echo ""
echo "=== Progress Summary ==="
total=$(wc -l < "$PROGRESS_FILE")
applied=$(grep -c "|applied|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
failed=$(grep -c "|failed|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
echo "Total: $total, Applied: $applied, Failed: $failed"
