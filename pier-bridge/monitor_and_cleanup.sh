#!/usr/bin/env bash
# monitor_and_cleanup.sh — Monitor Pier run and clean up Docker images after each task
# This prevents the disk from filling up during long runs

set -euo pipefail

JOBS_DIR="/tmp/pier-full-run-3"
BRIDGE_ROOT="/tmp/pier-bridge"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/benchmarks/deep-swe/tasks"

echo "Starting monitor + cleanup loop..."
echo "Will remove Docker images after each task's verifier completes"

cleaned_tasks=""

while true; do
    # Check if Pier is still running
    PIER_PID=$(cat "$JOBS_DIR/pier.pid" 2>/dev/null || echo "")
    if [ -n "$PIER_PID" ] && ! kill -0 "$PIER_PID" 2>/dev/null; then
        echo "Pier process exited. Doing final cleanup..."
        docker container prune --force 2>/dev/null || true
        docker builder prune --all --force 2>/dev/null || true
        echo "Done."
        break
    fi

    # Find tasks with verifier results that haven't been cleaned up yet
    for reward_file in $(find "$JOBS_DIR" -name "reward.json" 2>/dev/null); do
        task_dir=$(echo "$reward_file" | sed 's|/verifier/reward.json||')
        task_truncated=$(basename "$task_dir" | sed 's|__.*||')

        # Skip if already cleaned
        if echo "$cleaned_tasks" | grep -q "$task_truncated"; then
            continue
        fi

        # Get the ext_id from the task.toml
        # Match truncated name to full task name
        full_task=""
        while IFS= read -r candidate; do
            if [[ "$candidate" == "$task_truncated"* ]]; then
                full_task="$candidate"
                break
            fi
        done < /tmp/published_tasks.txt

        if [ -z "$full_task" ]; then
            continue
        fi

        toml_file="$TASKS_DIR/$full_task/task.toml"
        if [ ! -f "$toml_file" ]; then
            continue
        fi

        ext_id=$(grep "ext_id" "$toml_file" 2>/dev/null | sed 's/.*= "//;s/"//')
        if [ -z "$ext_id" ]; then
            continue
        fi

        image_tag="public.ecr.aws/d3j8x8q7/swe-bench-202605:${ext_id}-v1.1"

        # Remove the Docker image
        if docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "$image_tag"; then
            echo "Cleaning up image for: $full_task"
            docker rmi "$image_tag" 2>/dev/null || true
            docker container prune --force 2>/dev/null || true
            docker builder prune --all --force 2>/dev/null || true
            freed=$(df -h / | awk 'NR==2{print $4}')
            echo "  Disk free: $freed"
        fi

        cleaned_tasks="$cleaned_tasks $task_truncated"
    done

    sleep 30
done
