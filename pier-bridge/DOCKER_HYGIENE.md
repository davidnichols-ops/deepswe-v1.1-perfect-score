# Docker Hygiene Protocol

## Rules

1. **Pull on demand only.** Never pre-pull SWE-bench images. Pier pulls each
   task's image when it starts that task. Pre-pulling all 113 images consumes
   ~400GB and will fill the disk.

2. **Delete after verify.** Once a task's verifier finishes and the reward is
   recorded, remove that task's Docker image:
   ```bash
   docker rmi public.ecr.aws/d3j8x8q7/swe-bench-202605:<ext_id>-v1.1
   ```

3. **No build cache.** After any Docker build, prune the build cache:
   ```bash
   docker builder prune --all --force
   ```

4. **No dangling images.** Remove dangling images after builds:
   ```bash
   docker image prune --force
   ```

5. **No stopped containers.** Remove stopped containers after each task:
   ```bash
   docker container prune --force
   ```

6. **No hello-world or test images.** Remove them after testing:
   ```bash
   docker rmi hello-world:latest
   ```

7. **Monitor disk before runs.** Before starting a Pier run, ensure at least
   15GB free:
   ```bash
   df -h / | awk 'NR==2{print $4}'
   ```
   If less than 15GB free, run the cleanup script below.

8. **One image at a time.** Pier runs tasks sequentially (`--n-concurrent 1`).
   Only one task image should exist on disk at any time. The previous task's
   image should be removed before the next task's image is pulled.

## Cleanup Script

```bash
#!/usr/bin/env bash
# docker-cleanup.sh — Remove all unused Docker resources
set -euo pipefail

echo "Before:"
docker system df

# Prune build cache
docker builder prune --all --force 2>/dev/null

# Prune stopped containers
docker container prune --force 2>/dev/null

# Prune unused networks
docker network prune --force 2>/dev/null

# Prune dangling images
docker image prune --force 2>/dev/null

# Remove hello-world if present
docker rmi hello-world:latest 2>/dev/null || true

echo ""
echo "After:"
docker system df

echo ""
df -h /
```

## Post-Task Cleanup (for Pier runs)

After each task's verifier completes, run:

```bash
# Get the task's ext_id from task.toml
ext_id=$(grep ext_id benchmarks/deep-swe/tasks/<task>/task.toml | sed 's/.*= "//;s/"//')

# Remove the task's Docker image
docker rmi public.ecr.aws/d3j8x8q7/swe-bench-202605:${ext_id}-v1.1 2>/dev/null || true

# Prune stopped containers
docker container prune --force 2>/dev/null
```

## Disk Monitoring

- **Green**: >20GB free — safe to run
- **Yellow**: 10-20GB free — run cleanup script before starting
- **Red**: <10GB free — stop all runs, run cleanup, restart Docker Desktop
