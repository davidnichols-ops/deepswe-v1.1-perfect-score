# DeepSWE v1.1 — Release Package

This directory contains the externally verifiable release package for the DeepSWE v1.1 perfect score (113/113).

## Files

| File | Description |
|------|-------------|
| `results.json` | Canonical results manifest — per-task metadata, reward, test counts, SHA256 hashes, patch file lists |
| `checksums.sha256` | SHA256 checksums for every model.patch, reward.json, and ctrf.json |
| `task-breakdown.csv` | Per-task CSV with language, upstream repo, test counts, patch size — for research analysis |
| `verify.sh` | Re-verification script for reproducing the 113/113 result |
| `README.md` | This file |

## Quick Start

```bash
# 1. Verify checksums (no Docker needed)
./verify.sh --check

# 2. Re-verify a single task (requires Docker)
./verify.sh abs-module-cache-flags

# 3. Re-verify all 113 tasks (requires Docker, ~2-3 hours)
./verify.sh --all

# 4. Re-verify 10 random tasks
./verify.sh --random 10
```

## Manifest Schema

`results.json` contains:

```json
{
  "benchmark": "DeepSWE",
  "benchmark_version": "v1.1",
  "model": "glm-5-2",
  "harness": "Devin",
  "date_frozen": "2026-08-10",
  "total_tasks": 113,
  "tasks_solved": 113,
  "total_f2p_tests": 5877,
  "total_p2p_tests": 231352,
  "total_tests": 237229,
  "languages": {"typescript": 35, "go": 34, "python": 34, "rust": 5, "javascript": 5},
  "upstream_repos": 92,
  "tasks": [
    {
      "task_id": "abs-module-cache-flags",
      "language": "go",
      "upstream_repo": "abs-lang/abs",
      "base_commit": "cb1b3b671d0ee9fa9da9f7b02f86967953ffd10a",
      "reward": 1,
      "f2p_total": 20,
      "f2p_passed": 20,
      "p2p_total": 3,
      "p2p_passed": 3,
      "patch_files_count": 3,
      "patch_sha256": "...",
      "reward_sha256": "...",
      "ctrf_sha256": "..."
    }
  ]
}
```

## CSV Columns

`task-breakdown.csv` contains one row per task:

- `task_id`, `language`, `upstream_repo`, `category`, `display_title`
- `reward`, `f2p_total`, `f2p_passed`, `p2p_total`, `p2p_passed`
- `patch_files_count`, `patch_size_bytes`, `patch_sha256`

## Reproducibility

To reproduce the full 113/113 result:

1. Clone this repository.
2. Ensure Docker is installed and running.
3. Run `./verify.sh --all`.
4. Each task pulls its Docker image, builds the verifier, applies the model patch, runs held-out tests, and compares the result against the published `reward.json`.

All 113 tasks should produce `reward=1` with matching F2P/P2P counts.

### Platform Considerations

- Tasks are `linux/amd64` Docker images. On Apple Silicon, Docker Desktop uses Rosetta x86_64 emulation.
- 81 tasks work correctly under Rosetta.
- 3 tasks (narwhals, skrub, prometheus-reload) require native x86-64 for native library compatibility.
- 5 tasks exhibit platform-dependent behavior (pass on arm64, fail on x86). See `docs/DEEPSWE_METHODOLOGY.md` section 3.3 for details.
