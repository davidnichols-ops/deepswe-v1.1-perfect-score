#!/usr/bin/env bash
# auto_apply_patches.sh — Automatically apply patches for all DeepSWE tasks
# Polls for new bridge sessions and applies the corresponding patch

set -euo pipefail

BRIDGE_ROOT="/tmp/pier-bridge"
PATCH_BASE="/Users/david/aa-coding-index/results/raw/manual"
JOBS_DIR="/tmp/pier-full-run"
PROGRESS_FILE="$JOBS_DIR/progress.txt"
SKIPPED_FILE="$JOBS_DIR/skipped.txt"

mkdir -p "$JOBS_DIR"
touch "$PROGRESS_FILE" "$SKIPPED_FILE"

# Get list of completed task names
get_completed() {
    cat "$PROGRESS_FILE" 2>/dev/null | cut -d'|' -f1 | sort
}

# Find the task name from a bridge session
find_task_name() {
    local session_dir="$1"
    # Look in the jobs directory for a directory matching this session
    find "$JOBS_DIR" -maxdepth 2 -type d -name "*__${session_dir}*" 2>/dev/null | head -1 | sed 's|.*/||;s|__.*||'
}

# Apply a patch via bridge
apply_patch() {
    local session_id="$1"
    local task_name="$2"
    local bridge="$BRIDGE_ROOT/$session_id"
    local patch_file="$PATCH_BASE/$task_name/logs/artifacts/model.patch"

    if [ ! -f "$patch_file" ]; then
        echo "SKIP: No patch found for $task_name"
        echo "$task_name|no_patch" >> "$SKIPPED_FILE"
        # Still need to signal done to unblock Pier
        touch "$bridge/done"
        echo "DONE" > "$bridge/status"
        return 1
    fi

    local b64
    b64=$(base64 < "$patch_file")

    # Send the patch application command
    echo "echo '$b64' | base64 -d > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@example.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'PATCH_APPLIED_OK'" > "$bridge/command.txt"
    echo "COMMAND_READY" > "$bridge/status"

    # Wait for output
    for i in $(seq 1 120); do
        local status
        status=$(cat "$bridge/status" 2>/dev/null)
        if [ "$status" = "OUTPUT_READY" ]; then
            local rc
            rc=$(cat "$bridge/output.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['return_code'])" 2>/dev/null || echo "unknown")
            if [ "$rc" = "0" ]; then
                echo "OK: Patch applied for $task_name"
                echo "$task_name|$session_id|applied" >> "$PROGRESS_FILE"
            else
                echo "FAIL: Patch application failed for $task_name (exit=$rc)"
                echo "$task_name|$session_id|failed" >> "$PROGRESS_FILE"
            fi
            # Signal done
            touch "$bridge/done"
            echo "DONE" > "$bridge/status"
            return 0
        fi
        sleep 1
    done
    echo "TIMEOUT: Patch application timed out for $task_name"
    echo "$task_name|$session_id|timeout" >> "$PROGRESS_FILE"
    touch "$bridge/done"
    echo "DONE" > "$bridge/status"
    return 1
}

# Main loop: poll for new bridge sessions
echo "Starting auto-apply loop..."
echo "Monitoring $BRIDGE_ROOT for new bridge sessions..."

while true; do
    # Check if Pier is still running
    PIER_PID=$(cat "$JOBS_DIR/pier.pid" 2>/dev/null || echo "")
    if [ -n "$PIER_PID" ] && ! kill -0 "$PIER_PID" 2>/dev/null; then
        echo "Pier process ($PIER_PID) has exited. Checking if all tasks are done..."
        # Check if there are any pending bridge sessions
        pending=$(find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null | while read f; do
            session=$(basename $(dirname "$f"))
            if ! grep -q "$session" "$PROGRESS_FILE" 2>/dev/null; then
                echo "$session"
            fi
        done | wc -l)
        if [ "$pending" -eq 0 ]; then
            echo "All tasks completed. Exiting."
            break
        fi
    fi

    # Find new bridge sessions with instruction.txt ready
    find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null | while read instr_file; do
        session_id=$(basename $(dirname "$instr_file"))
        # Skip if already processed
        if grep -q "|$session_id|" "$PROGRESS_FILE" 2>/dev/null; then
            continue
        fi
        # Skip if status is not INSTRUCTION_READY
        status=$(cat "$BRIDGE_ROOT/$session_id/status" 2>/dev/null)
        if [ "$status" != "INSTRUCTION_READY" ]; then
            continue
        fi

        # Find the task name
        task_name=$(find_task_name "$session_id")
        if [ -z "$task_name" ]; then
            echo "WARN: Could not determine task name for session $session_id, waiting..."
            continue
        fi

        echo "=== Processing: $task_name (session: $session_id) ==="
        apply_patch "$session_id" "$task_name"
    done

    sleep 5
done

echo ""
echo "=== Progress Summary ==="
total=$(wc -l < "$PROGRESS_FILE")
applied=$(grep -c "|applied|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
failed=$(grep -c "|failed|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
timeout=$(grep -c "|timeout|" "$PROGRESS_FILE" 2>/dev/null || echo 0)
echo "Total: $total, Applied: $applied, Failed: $failed, Timeout: $timeout"
