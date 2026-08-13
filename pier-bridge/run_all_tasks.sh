#!/usr/bin/env bash
# run_all_tasks.sh — Starts Pier with all DeepSWE tasks using the DevinBridgeAgent
# Pier runs one task at a time (--n-concurrent 1)
# The interactive Devin session polls for bridge sessions and solves each task

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS_DIR="/tmp/pier-full-run"
BRIDGE_ROOT="/tmp/pier-bridge"

mkdir -p "$JOBS_DIR" "$BRIDGE_ROOT"
rm -rf "$BRIDGE_ROOT"/*

# Start Pier with all tasks
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
echo "Pier started with PID $PIER_PID"
echo "Jobs dir: $JOBS_DIR"
echo "Bridge root: $BRIDGE_ROOT"
echo "Log: $JOBS_DIR/pier.log"
