# DeepSWE v1.1 — Perfect Score (113/113)

This repository contains the complete results of solving all 113 tasks in the [DeepSWE v1.1](https://deepswe.datacurve.ai/) benchmark, achieving a perfect score of 113/113 (reward=1.0 on every task).

## Results

| Metric | Value |
|--------|-------|
| **Tasks solved** | **113 / 113 (100%)** |
| Total F2P tests passed | 5,877 |
| Total P2P tests passed | 231,352 |
| Total tests passed | 237,229 |
| Upstream repositories | 92 |
| Languages | TypeScript (35), Go (34), Python (34), Rust (5), JavaScript (5) |

### Performance by Language

| Language | Tasks | F2P Tests | P2P Tests | Total Tests | Patch Size |
|----------|-------|-----------|-----------|-------------|------------|
| TypeScript | 35 | 1,726 | 72,295 | 74,021 | 1,120 KB |
| Go | 34 | 1,377 | 70,727 | 72,104 | 886 KB |
| Python | 34 | 2,245 | 69,341 | 71,586 | 936 KB |
| Rust | 5 | 192 | 486 | 678 | 134 KB |
| JavaScript | 5 | 337 | 18,503 | 18,840 | 162 KB |
| **Total** | **113** | **5,877** | **231,352** | **237,229** | **3,238 KB** |

## What is DeepSWE?

DeepSWE is a benchmark for evaluating AI agents on real-world software engineering tasks. Each task is drawn from an active open-source repository and requires implementing a feature that is verified by held-out tests in an isolated Docker environment. The benchmark uses the [Harbor](https://www.harborframework.com/docs/tasks) task format with separate verifier environments.

## Repository Structure

```
aa-coding-index/
  benchmarks/              DeepSWE v1.1 task definitions (upstream, read-only)
    deep-swe/
      tasks/<task>/        113 task dirs: instruction.md, tests/, solution/, task.toml
      README.md            Benchmark description
      PROVENANCE.md        Upstream project licenses
      LICENSE              Apache-2.0 (Datacurve AI)
  orchestrator/            113 model.patch files (the solutions)
    <task>_model.patch     Git diff from base_commit to solution HEAD
  results/                 Per-task verifier output
    raw/manual/<task>/
      logs/
        artifacts/
          model.patch      Copy of the submitted patch
        verifier/
          reward.json      Binary reward + F2P/P2P pass fractions
          ctrf.json        Machine-readable test report (CTRF format)
          run.log          Raw test suite stdout/stderr
          reports/         Base and new CTRF reports
  docs/                    Methodology documentation
    DEEPSWE_METHODOLOGY.md Full methodology, verification process, lessons learned
    BACKBOARD.md           Concise status board
  publish/                 Release package for external verification
    deepswe-v1.1/
      results.json         Canonical results manifest (all 113 tasks)
      checksums.sha256     SHA256 hashes for every artifact
      task-breakdown.csv   Per-task CSV for research analysis
      verify.sh            Re-verification script
      README.md            Release package documentation
```

## Verifying the Results

### Quick check (checksums only)

```bash
cd publish/deepswe-v1.1
./verify.sh --check
```

### Re-verify a single task

```bash
./verify.sh abs-module-cache-flags
```

### Re-verify all 113 tasks

```bash
./verify.sh --all
```

### Re-verify N random tasks

```bash
./verify.sh --random 10
```

Re-verification requires Docker and network access to `public.ecr.aws` for pulling task images. See `docs/DEEPSWE_METHODOLOGY.md` for the full verification process.

## Platform Notes

- 81 tasks verified locally on macOS (Apple Silicon, Rosetta x86_64 emulation)
- 3 tasks required a native x86-64 VM (polars/pyarrow native library issues)
- 5 tasks exhibit platform-dependent behavior (pass on arm64, fail on x86). The arm64 results are authoritative. See methodology doc for details.

## License

- **Solution patches and results** (`orchestrator/`, `results/`, `publish/`, `docs/`): MIT. See [LICENSE](LICENSE).
- **DeepSWE task definitions** (`benchmarks/`): Apache-2.0 (Datacurve AI). See `benchmarks/deep-swe/PROVENANCE.md` for upstream project licenses.
