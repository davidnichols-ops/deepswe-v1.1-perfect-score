#!/usr/bin/env bash
# auto_apply_patches_v6.sh — Apply patches using chunked file writes for large patches
# Handles patches that exceed the command-line argument length limit

set -euo pipefail

BRIDGE_ROOT="/tmp/pier-bridge"
PATCH_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/results/raw/manual"
JOBS_DIR="/tmp/pier-full-run-3"
PROGRESS_FILE="$JOBS_DIR/progress.txt"
TASKS_FILE="/tmp/published_tasks.txt"

mkdir -p "$JOBS_DIR"
touch "$PROGRESS_FILE"

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
            cat "$bridge/output.json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'exit={d[\"return_code\"]}'); print(d['stdout'][:2000]); print('--- stderr ---'); print(d['stderr'][:1000])" 2>/dev/null
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
        echo "SKIP: No patch found for $task_name"
        echo "$task_name|$session_id|no_patch" >> "$PROGRESS_FILE"
        touch "$bridge/done"
        echo "DONE" > "$bridge/status"
        return 1
    fi

    local patch_size
    patch_size=$(wc -c < "$patch_file")
    local b64_size
    b64_size=$(base64 < "$patch_file" | wc -c)

    echo "  Patch size: ${patch_size} bytes (${b64_size} b64)"

    # If base64 is under 100KB, use the inline method
    if [ "$b64_size" -lt 100000 ]; then
        local b64
        b64=$(base64 < "$patch_file")
        local cmd="echo '$b64' | base64 -d > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@example.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'PATCH_APPLIED_OK'"
        local result
        result=$(send_and_wait "$bridge" "$cmd")
        echo "$result" | head -3
    else
        # Large patch: chunk it into multiple writes
        echo "  Large patch — using chunked write..."
        local n_chunks
        n_chunks=$(( (b64_size + 49999) / 50000 ))

        # First command: create the file with first chunk
        local b64_full
        b64_full=$(base64 < "$patch_file")
        local chunk
        chunk=$(echo "$b64_full" | cut -c1-50000)
        local cmd="echo -n '$chunk' > /tmp/model.patch.b64 && echo 'CHUNK_1_OK'"
        local result
        result=$(send_and_wait "$bridge" "$cmd")
        if ! echo "$result" | grep -q "CHUNK_1_OK"; then
            echo "FAIL: chunk 1 write failed"
            echo "$task_name|$session_id|chunk_fail" >> "$PROGRESS_FILE"
            touch "$bridge/done"
            echo "DONE" > "$bridge/status"
            return 1
        fi

        # Subsequent chunks: append
        for i in $(seq 2 $n_chunks); do
            local start=$(( (i - 1) * 50000 + 1 ))
            local end=$(( i * 50000 ))
            chunk=$(echo "$b64_full" | cut -c${start}-${end})
            if [ -z "$chunk" ]; then
                break
            fi
            cmd="echo -n '$chunk' >> /tmp/model.patch.b64 && echo 'CHUNK_${i}_OK'"
            result=$(send_and_wait "$bridge" "$cmd")
            if ! echo "$result" | grep -q "CHUNK_${i}_OK"; then
                echo "FAIL: chunk $i write failed"
                echo "$task_name|$session_id|chunk_fail" >> "$PROGRESS_FILE"
                touch "$bridge/done"
                echo "DONE" > "$bridge/status"
                return 1
            fi
        done

        # Decode and apply
        cmd="base64 -d /tmp/model.patch.b64 > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@example.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'PATCH_APPLIED_OK'"
        result=$(send_and_wait "$bridge" "$cmd")
        echo "$result" | head -3
    fi

    # Check result
    local rc
    rc=$(cat "$bridge/output.json" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['return_code'])" 2>/dev/null || echo "unknown")
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
}

# Main loop
echo "Starting auto-apply loop v6 (chunked patch support)..."
processed_sessions=""

while true; do
    PIER_PID=$(cat "$JOBS_DIR/pier.pid" 2>/dev/null || echo "")
    if [ -n "$PIER_PID" ] && ! kill -0 "$PIER_PID" 2>/dev/null; then
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
        echo "Pier stopped but $pending sessions pending..."
    fi

    for instr_file in $(find "$BRIDGE_ROOT" -name "instruction.txt" 2>/dev/null); do
        session_id=$(basename $(dirname "$instr_file"))
        if echo "$processed_sessions" | grep -q "$session_id"; then
            continue
        fi
        status=$(cat "$BRIDGE_ROOT/$session_id/status" 2>/dev/null)
        if [ "$status" != "INSTRUCTION_READY" ]; then
            continue
        fi

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
            echo "WARN: Could not match '$truncated_name'"
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
