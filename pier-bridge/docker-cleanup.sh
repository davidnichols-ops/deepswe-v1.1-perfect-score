#!/usr/bin/env bash
# docker-cleanup.sh — Remove all unused Docker resources
# Usage: bash docker-cleanup.sh [--aggressive]
#
# --aggressive: also remove ALL SWE-bench images (use only between runs)

set -euo pipefail

echo "=== Before cleanup ==="
docker system df 2>&1
echo ""
df -h / 2>/dev/null
echo ""

# Prune build cache
echo "Pruning build cache..."
docker builder prune --all --force 2>/dev/null

# Prune stopped containers
echo "Pruning stopped containers..."
docker container prune --force 2>/dev/null

# Prune unused networks
echo "Pruning unused networks..."
docker network prune --force 2>/dev/null

# Prune dangling images
echo "Pruning dangling images..."
docker image prune --force 2>/dev/null

# Remove hello-world if present
docker rmi hello-world:latest 2>/dev/null || true

# If --aggressive, remove ALL SWE-bench images
if [ "${1:-}" = "--aggressive" ]; then
    echo ""
    echo "=== Aggressive: removing ALL SWE-bench images ==="
    docker images --format "{{.Repository}}:{{.Tag}}" | grep "swe-bench" | while read img; do
        echo "Removing: $img"
        docker rmi "$img" 2>/dev/null || true
    done
fi

echo ""
echo "=== After cleanup ==="
docker system df 2>&1
echo ""
df -h / 2>/dev/null
