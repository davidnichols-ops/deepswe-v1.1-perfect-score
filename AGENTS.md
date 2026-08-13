# AGENTS.md — deepswe-v1.1-perfect-score

## What this is

A research artifact repo for a DeepSWE v1.1 benchmark run. GLM-5.2 High (rank
10 on the public leaderboard at 44%) scored 113/113 (100%) via Devin with a
human operator. The repo documents the harness vs. model gap, not a leaderboard
submission.

**Key caveat**: the 56-point gap conflates harness quality and human direction.
This repo does not isolate those variables. The harness config (system prompts,
prefill, tool-calling protocol) is proprietary to Devin and not included.

## Repo layout

- `benchmarks/deep-swe/tasks/` — 113 task definitions (read-only, Apache-2.0)
- `orchestrator/<task>_model.patch` — 113 solution patches
- `results/raw/manual/<task>/` — verifier output (reward.json, ctrf.json, run.log)
- `pier-bridge/` — cooperative Pier agent for Phase 2 re-verification
- `pier-results-2026-08-12/` — Pier re-verification output (110/113 passed)
- `publish/deepswe-v1.1/` — release package with checksums and verify.sh
- `docs/` — methodology, findings, status board

## Commands

```bash
# Verify checksums (no Docker needed)
cd publish/deepswe-v1.1 && ./verify.sh --check

# Re-verify a single task (requires Docker)
./verify.sh <task-name>

# Re-verify N random tasks
./verify.sh --random 10

# Re-verify all 113 tasks (~4-5 hours)
./verify.sh --all
```

## Pier bridge (Phase 2)

The `pier-bridge/` directory contains a cooperative Pier agent that re-applies
patches through Pier's verifier. See `CONTRIBUTING.md` for setup instructions.

Key files:
- `devin_bridge_agent.py` — Pier agent (file-based protocol)
- `handler_only.sh` — handler loop (auto-detects repo root, env vars for overrides)
- `devin_bridge_client.py` — client for the Devin side

**Docker safety**: `handler_only.sh` only prunes images matching `DOCKER_PREFIX`
(default: `public.ecr.aws/`). It does NOT delete unrelated Docker images.

## Invariants

1. **Patches are byte-identical** between `orchestrator/<task>_model.patch` and
   `results/raw/manual/<task>/logs/artifacts/model.patch`. Checksums verify this.
2. **The verifier is isolated** — the agent never sees held-out tests, the
   verifier never sees the agent's container state.
3. **3 Phase 2 failures are environmental** — polars segfaults (2) and verifier
   timeout (1). All 113 passed in Phase 1.
4. **This is not a leaderboard score** — no token counts, API costs, or
   wall-clock timing for the solving phase.

## What NOT to do

- Don't claim the 56-point gap is "all harness" — human direction is confounded.
- Don't claim $0 total cost — the Devin subscription is a real cost.
- Don't remove the limitations section — it's the most important part.
- Don't add Devin co-author trailers to commits.
