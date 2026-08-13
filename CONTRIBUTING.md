# Contributing

This repository contains the verified results of a DeepSWE v1.1 benchmark run. The primary way to contribute is **re-verification** — independently confirming that the 113/113 result reproduces.

## Re-verification

### Quick check (no Docker needed)

```bash
cd publish/deepswe-v1.1
./verify.sh --check
```

This verifies SHA256 checksums for all 113 model patches, reward.json, and ctrf.json files.

### Full re-verification (requires Docker)

```bash
# Single task
./verify.sh abs-module-cache-flags

# All 113 tasks (~2-3 hours)
./verify.sh --all

# 10 random tasks
./verify.sh --random 10
```

Each task:
1. Pulls the Docker image from `public.ecr.aws`
2. Builds the verifier image with held-out tests
3. Applies the model patch to a pristine checkout
4. Runs the test suite
5. Compares the result against the published `reward.json`

## Adding New Model Results

If you want to add results from a different model:

1. Run the DeepSWE benchmark with your model using [Pier](https://github.com/datacurve-ai/pier)
2. Create a new directory: `results/<model-name>/`
3. Follow the same structure as `results/raw/manual/`
4. Generate a manifest and checksums
5. Open a PR

## Reproducing the Devin-Side Solving Workflow

The 113/113 result was produced by a human directing Devin (GLM-5.2 High) interactively.
The harness configuration (system prompts, prefill, tool-calling protocol) is proprietary
to Devin and is not included in this repo. Therefore, the solving workflow cannot be
reproduced from this repo alone.

To attempt a comparable run:
1. Install [Devin](https://devin.ai) and select GLM-5.2 High as the model
2. Clone the [DeepSWE benchmark](https://github.com/datacurve-ai/deep-swe) tasks
3. For each task, start a Devin session with the task instruction
4. Direct the agent to explore, implement, test, and produce a patch
5. Verify each patch with `publish/deepswe-v1.1/verify.sh <task-name>`

Note: your results may differ. The 100% score depended on both the harness and the
operator's judgment. See [README — What This Does NOT Prove](README.md#what-this-does-not-prove).

## Pier Bridge Setup (Phase 2 Re-Verification)

The `pier-bridge/` directory contains a cooperative Pier agent for re-applying patches
through Pier's verifier. To run it:

### Prerequisites

1. **Pier** — install from [github.com/datacurve-ai/pier](https://github.com/datacurve-ai/pier)
2. **Docker** — required for verifier containers
3. **Python 3.10+** — for the bridge agent
4. **Node.js 18+** — for verify.sh

### Running the bridge

```bash
# 1. Generate the task list
ls benchmarks/deep-swe/tasks/ | sort > /tmp/published_tasks.txt

# 2. Start Pier with the bridge agent
pier run --agent pier-bridge/devin_bridge_agent.py --tasks /tmp/published_tasks.txt

# 3. In another terminal, run the handler
cd pier-bridge
./handler_only.sh
```

The handler auto-detects the repo root from its own location. Override with:
```bash
REPO_ROOT=/path/to/deepswe-v1.1-perfect-score ./handler_only.sh
```

### Important notes

- `handler_only.sh` only prunes Docker images matching `public.ecr.aws/` by default.
  Override with `DOCKER_PREFIX=...` or set to empty to skip image pruning.
- The bridge uses a file-based protocol (`instruction.txt`, `command.txt`, `output.json`,
  `done`) in `/tmp/pier-bridge/`. Clean up with `rm -rf /tmp/pier-bridge/` after runs.
- Pier is not pinned to a specific version. Check `pier --version` and report
  compatibility issues.

## Reporting Issues

If a task fails re-verification:
- Open an issue with the task ID, the error output, and your platform (OS, architecture)
- Note that 5 tasks have known platform-dependent behavior (see `docs/DEEPSWE_METHODOLOGY.md` section 3.3)

## License

- Solution patches and results: MIT (see [LICENSE](LICENSE))
- DeepSWE task definitions: Apache-2.0 (see `benchmarks/deep-swe/LICENSE`)
- Upstream project code: respective licenses (see `benchmarks/deep-swe/PROVENANCE.md`)
