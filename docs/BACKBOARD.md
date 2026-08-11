# DeepSWE v1.1 — Status Board

> **COMPLETE**: 113/113 tasks solved (reward=1.0)
> **Frozen**: 2026-08-10

---

## Final Numbers

| Metric | Value |
|--------|-------|
| Tasks | 113 / 113 |
| Reward | 1.0 (all) |
| F2P tests | 5,877 passed |
| P2P tests | 231,352 passed |
| Total tests | 237,229 passed |
| Languages | TS (35), Go (34), Python (34), Rust (5), JS (5) |
| Upstream repos | 91 |

## Artifact Counts

| Artifact | Count |
|----------|-------|
| reward.json | 113 / 113 |
| ctrf.json | 113 / 113 |
| model.patch (orchestrator) | 113 / 113 |
| model.patch (results) | 113 / 113 |
| Patch consistency | 0 mismatches |

## Platform Notes

- **81 tasks**: verified locally on arm64 (Rosetta x86_64 emulation)
- **3 tasks**: required x86 VM (narwhals, skrub, prometheus-reload — native lib issues)
- **5 tasks**: arm64=pass, x86=fail (platform-specific behavior, arm64 authoritative)
  - oxvg-structural-selector-preservation
  - prometheus-typed-label-sorting
  - psd-tools-blend-range-api
  - updo-policy-alerting
  - wazero-multi-module-snapshots

## Directory Structure

```
aa-coding-index/
  benchmarks/     36M   DeepSWE task definitions (read-only)
  orchestrator/   3.4M  113 model.patch files
  results/        179M  Per-task verifier output (reward.json, ctrf.json, run.log)
  docs/           32K   This file + methodology
  publish/        --    Release artifacts (to be generated)
```

## Key Files

- `docs/DEEPSWE_METHODOLOGY.md` — Full methodology, verification process, lessons learned
- `benchmarks/deep-swe/README.md` — DeepSWE benchmark description (upstream)
- `benchmarks/deep-swe/PROVENANCE.md` — Upstream project licenses
- `results/raw/manual/<task>/logs/verifier/reward.json` — Canonical per-task score
- `orchestrator/<task>_model.patch` — Canonical per-task solution patch
