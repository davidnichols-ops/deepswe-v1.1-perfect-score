#!/usr/bin/env bash
# apply_patch_via_bridge.sh — Apply an existing patch through the Pier bridge
# Usage: apply_patch_via_bridge.sh <session_id> <task_name>

set -euo pipefail

SESSION_ID="$1"
TASK_NAME="$2"
BRIDGE="/tmp/pier-bridge/$SESSION_ID"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/results/raw/manual/$TASK_NAME/logs/artifacts"
PATCH_FILE="$PATCH_DIR/model.patch"

if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: Patch file not found: $PATCH_FILE"
    exit 1
fi

send_and_wait() {
    echo "$1" > "$BRIDGE/command.txt"
    echo "COMMAND_READY" > "$BRIDGE/status"
    for i in $(seq 1 300); do
        status=$(cat "$BRIDGE/status" 2>/dev/null)
        if [ "$status" = "OUTPUT_READY" ]; then
            cat "$BRIDGE/output.json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'exit={d[\"return_code\"]}'); print(d['stdout'][:3000]); print('--- stderr ---'); print(d['stderr'][:2000])"
            return 0
        fi
        sleep 1
    done
    echo "TIMEOUT"
    return 1
}

# Base64 encode the patch and apply it in the container
B64=$(base64 < "$PATCH_FILE")
PATCH_SIZE=${#B64}

echo "Applying patch for $TASK_NAME ($PATCH_SIZE bytes b64)..."

# Apply the patch, create a branch, commit, and write to /logs/artifacts/model.patch
send_and_wait "echo '$B64' | base64 -d > /tmp/model.patch && cd /app && git checkout -b solution 2>/dev/null || git checkout solution 2>/dev/null; git reset --hard HEAD~0 2>/dev/null; git apply /tmp/model.patch && git add -A && git config user.email 'dev@example.com' && git config user.name 'Dev' && git commit -m 'solution' && cp /tmp/model.patch /logs/artifacts/model.patch && echo 'PATCH_APPLIED_OK'"

# Signal done
touch "$BRIDGE/done"
echo "DONE" > "$BRIDGE/status"
echo "Done signal sent for $TASK_NAME"
