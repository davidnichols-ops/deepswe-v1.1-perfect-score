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

## Reporting Issues

If a task fails re-verification:
- Open an issue with the task ID, the error output, and your platform (OS, architecture)
- Note that 5 tasks have known platform-dependent behavior (see `docs/DEEPSWE_METHODOLOGY.md` section 3.3)

## License

- Solution patches and results: MIT (see [LICENSE](LICENSE))
- DeepSWE task definitions: Apache-2.0 (see `benchmarks/deep-swe/LICENSE`)
- Upstream project code: respective licenses (see `benchmarks/deep-swe/PROVENANCE.md`)
