# Outside Review Response

This document addresses every point raised in the outside review
(`deepswe_outside_review.md`) and records what was fixed, mitigated, or
acknowledged as a limitation.

---

## 1. Confusing / misleading framing

### 1.1 "Not apples-to-apples" — FIXED

**Issue**: Headline claimed harness-only gap, but human direction was a
confounded variable. The caveat was buried in "What This Does NOT Prove".

**Fix**: Rewrote the headline to include "with a human in the loop". Added
"Operator" row to the result table (None vs. Human in the loop). Changed
"The only difference is the harness layer" to "The difference is the harness
layer **plus human direction**". Added limitation #7 explicitly stating the
two variables are confounded and neither was isolated.

### 1.2 "Phase 2 is not a re-solve" — ACKNOWLEDGED

**Issue**: Pier re-verification applies pre-existing patches, does not re-solve.

**Fix**: Added limitation #6 explicitly: "Phase 2 is re-verification, not
re-solving." The README and docs already described Phase 2 as "re-applies
pre-existing patches" but did not call out the implication for the harness
claim. Now it does.

### 1.3 "aa-coding-index everywhere" — FIXED

**Issue**: Internal codename `aa-coding-index` appeared in README, docs, and
hard-coded in `handler_only.sh`.

**Fix**: Replaced all `aa-coding-index/` references in the README repo structure
diagram with `deepswe-v1.1-perfect-score/`. Fixed `handler_only.sh` to
auto-detect the repo root from the script's location (no hard-coded path).
Checked `docs/DEEPSWE_METHODOLOGY.md` and `docs/BACKBOARD.md` for remaining
references.

---

## 2. Missing / incomplete reproducibility artifacts

### 2.1 "No harness configuration shared" — MITIGATED

**Issue**: The entire argument is about the harness, but zero harness config
is in the repo.

**Mitigation**: Added "Harness Configuration (What We Can Share)" section to
README. Disclosed what is in the repo (pier-bridge code, patches, results),
what is NOT (Devin's proprietary system prompts, prefill, session settings),
and why (proprietary to Cognition/Devin). Listed what an independent researcher
would need to test the claim. Honestly labeled the result as "an existence
proof, not a reproducible experiment."

**Not fully fixable**: Devin's harness is proprietary. We cannot open-source
it. The mitigation is transparency about what is and isn't available.

### 2.2 "No cost/token/wall-clock data" — ACKNOWLEDGED

**Issue**: $0 cost claim is unsupported — no token counts for solving phase.

**Fix**: Rewrote limitation #3 to clarify: "$0" refers to API spend only
(GLM-5.2 was on a free promo tier). The Devin subscription is a real cost
(flat-rate, not per-token). We cannot compute equivalent per-token costs
without token counts, which we don't have. The cost comparison with leaderboard
models is explicitly marked as unsupported.

### 2.3 "No environment metadata" — FIXED

**Issue**: No AGENTS.md, no install instructions, no pinned Pier version.

**Fix**: Created `AGENTS.md` with repo layout, commands, invariants, and
what-not-to-do. Added "Pier Bridge Setup" section to `CONTRIBUTING.md` with
prerequisites (Pier, Docker, Python 3.10+, Node 18+), running instructions,
and notes about the file-based protocol. Pier version is not pinned because
the bridge is compatible with any recent Pier; noted this explicitly.

### 2.4 "Invalid ORCID" — FIXED

**Issue**: `CITATION.cff` had `orcid: "https://github.com/davidnichols-ops"`
which is not an ORCID iD.

**Fix**: Removed the `orcid` field entirely. Citation tools will no longer
flag it. An ORCID iD can be added later if the author registers one.

---

## 3. Technical / code issues

### 3.1 "handler_only.sh not portable" — FIXED

**Issue**: `REPO_ROOT="/Users/david/aa-coding-index"` hard-coded to one machine.

**Fix**: Replaced with auto-detection: `REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`.
Added env var override documentation in the script header. The script now works
from any checkout location.

### 3.2 "handler_only.sh relies on files not in repo" — DOCUMENTED

**Issue**: `TASKS_FILE` and `JOBS_DIR` point to `/tmp/` paths generated at
runtime.

**Fix**: Made both configurable via env vars with defaults. Added instructions
in `CONTRIBUTING.md` for generating the task list: `ls benchmarks/deep-swe/tasks/
| sort > /tmp/published_tasks.txt`. The `/tmp/` paths are runtime artifacts by
design (Pier generates them during a run), but now they're documented and
overridable.

### 3.3 "CI does not re-verify the benchmark" — ACKNOWLEDGED

**Issue**: CI only checks checksums and result.json structure, doesn't run
the verifier in Docker.

**Status**: Acknowledged as a limitation. Running `verify.sh --random N` in CI
requires Docker-in-Docker or a Docker-enabled runner, plus network access to
`public.ecr.aws`. This is a CI infrastructure change that requires a
Docker-enabled GitHub Actions runner. Noted as a future improvement. The
checksum verification still provides integrity assurance — it just doesn't
prove patch correctness (which the original verifier runs already did).

### 3.4 "handler_only.sh can delete wrong Docker images" — FIXED

**Issue**: `docker rmi` removed ALL images except the active container's image.

**Fix**: Replaced with scoped cleanup that only removes images matching
`DOCKER_PREFIX` (default: `public.ecr.aws/`). Added `DOCKER_PREFIX` env var
for configuration. Set to empty string to skip image pruning entirely. The
script header documents this clearly.

### 3.5 "result.json internally confusing" — FIXED

**Issue**: 113 total, 1 errored, but docs said 2 failed + 1 errored. Numbers
appeared not to add up.

**Fix**: Added "Interpreting result.json" section to README explaining: the 2
polars segfaults count as completed-with-failure (reward=0), not errored. Only
the kgateway timeout counts as errored. So: 110 passed + 2 failed (reward=0) +
1 errored = 113 total.

### 3.6 "Floating-point test counts" — FIXED

**Issue**: `f2p_passed: 49.929...` looks like fractional test counts.

**Fix**: Added explanation in the same "Interpreting result.json" section:
these are averages across tasks, not raw counts. Raw per-task counts are in
the individual `reward.json` files.

---

## 4. Documentation nits

### "underrate" typo — FIXED

`docs/FINDINGS.md` line 146: "underrate" → "underrated".

### CONTRIBUTING.md missing solving workflow — FIXED

Added "Reproducing the Devin-Side Solving Workflow" section with steps and
a note that results may differ (pointing to the limitations section).

### README structure diagram root label — FIXED

`aa-coding-index/` → `deepswe-v1.1-perfect-score/`.

---

## 5. What was solid (no action needed)

The reviewer confirmed:
- Checksum verification passes for all 340 hashes
- 113 tasks, 113 patches, 113 result sets — all consistent
- Patches are byte-identical between orchestrator/ and results/
- verify.sh is clear and well-documented
- Limitations section is unusually honest

No action needed on these.

---

## 6. Bottom line — what we did and didn't do

| Reviewer recommendation | Status |
|---|---|
| 1. Share system prompts/prefill/tool-format/loop settings | **Cannot** — proprietary to Devin. Documented what's available and what isn't. |
| 2. Fully automated Devin run with timing and cost | **Future work** — not done in this iteration. |
| 3. CI job that runs verify.sh --random N in Docker | **Future work** — needs Docker-enabled runner. |
| 4. Fix handler_only.sh paths and document Pier bridge | **Done** — auto-detect root, env vars, CONTRIBUTING.md section. |
| 5. Correct CITATION.cff ORCID and aa-coding-index references | **Done** — ORCID removed, all references renamed. |

The repo is now a more honest artifact: the framing doesn't overclaim, the
code is portable, the docs explain the confusing parts, and the limitations
are prominent rather than buried. The two recommendations that require new
experiments (automated Devin run, Docker CI) are future work.
