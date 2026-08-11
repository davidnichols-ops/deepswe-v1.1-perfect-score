# Devin Operating Direction — DeepSWE 1.1 Completion Run

**Audience:** Devin CLI operating through the configured GLM-5.2 harness.
**Workspace:** `~/aa-coding-index`
**Benchmark:** DeepSWE 1.1 / Harbor task format.
**Completion target:** `113/113` tasks with `reward=1.0`.
**Operating claim:** This run is intended to reproduce and preserve a technical benchmark result; do not call it a world record until the result is independently reproducible and compared against the published leaderboard or an explicitly documented comparison set.

> This is an operating directive, not a suggestion. Follow it in order. Prefer a small verified patch over a clever unverified patch. The benchmark is a hostile integration test: the model, shell, repository, dependency graph, Docker image, patch extractor, verifier, architecture, and evidence pipeline can all fail independently.

---

## 0. Mission

Finish every unfinished DeepSWE 1.1 task in the local benchmark index and leave an auditable artifact set proving the result.

A task is complete only when all of the following are true:

1. The solution is represented by a clean `git diff <base_commit> HEAD` patch.
2. The patch applies to a pristine checkout of the task's base commit.
3. The isolated verifier applies the patch and its hidden test patch successfully.
4. `reward.json` exists in the canonical results location and has `reward=1`.
5. Every F2P test passes and every P2P test passes.
6. The verifier's `ctrf.json` and `run.log` are retained.
7. The model patch and captured result patch are byte-identical.
8. No credentials, runtime state, build products, caches, or unrelated files enter the patch.
9. The result is recorded with task name, base commit, platform, image, command, exit status, timestamps, and artifact paths.

Do not report a task as solved from local unit tests alone. Do not report a benchmark score from a count of solution files alone. The authoritative per-task score is:

```text
results/raw/manual/<task>/logs/verifier/reward.json
```

Secondary copies may exist under `orchestrator/results/`; never use them as the sole source of truth.

---

## 1. Runtime and model contract

Use the Devin CLI harness with the configured GLM-5.2 model:

```text
model = glm-5-2
```

Do not silently substitute another model, provider, temperature, system prompt, or tool protocol during the benchmark run. If a fallback is required, stop the affected task batch, record the deviation, and label the result as a non-equivalent experiment.

The benchmark runner is the execution authority. Devin is responsible for repository understanding, implementation, patch hygiene, local validation, and artifact capture. The hidden verifier is responsible for scoring.

Do not expose hidden test files to the agent during task solving. Do not read or use `tests/test.patch`, hidden grader logic, or reference solution patches as implementation hints during a live solve. Those files are allowed for offline audit only after the task's submitted result is frozen.

---

## 2. Mandatory startup sequence

Run this sequence before touching a task:

```bash
set -euo pipefail

cd ~/mac-ai-os
uv run app agent doctor --provider devin --json
uv run app agent brief --provider devin --task "Finish DeepSWE 1.1: solve every unfinished task and produce independently verified reward=1 artifacts"
uv run app agent start --provider devin --role implementation --task "DeepSWE 1.1 completion run using GLM-5.2 and the Devin CLI harness"
uv run app onboard --json
uv run app refresh
uv run app task list

cd ~/aa-coding-index
pwd
find .. -name AGENTS.md -print
cat ../AGENTS.md 2>/dev/null || true
cat .config/devin/AGENTS.md 2>/dev/null || true
git status --short --branch
```

If MAOS or agent registration is unavailable, record the exact failure and continue only with local evidence. Never paste credentials into prompts, logs, scripts, commits, or result files.

Before starting Docker work, inspect capacity and active processes:

```bash
df -h .
docker info
docker ps -a --format '{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | head -50
```

Require practical free disk headroom before pulling images. DeepSWE images are large and Docker Desktop's storage can corrupt when the disk fills. Work in batches of at most 3–4 tasks and keep no more than approximately five benchmark images cached at once.

---

## 3. Build the task inventory from evidence

Never trust a stale progress file. Recompute the inventory from task definitions and canonical verifier output.

```bash
cd ~/aa-coding-index

find benchmarks/deep-swe/tasks -mindepth 1 -maxdepth 1 -type d -print | sort > /tmp/deepswe.tasks
find orchestrator -maxdepth 1 -name '*_model.patch' -print | sort > /tmp/deepswe.patches
find results/raw/manual -path '*/logs/verifier/reward.json' -print | sort > /tmp/deepswe.rewards

python3 - <<'PY'
import json
from pathlib import Path
root = Path('.')
tasks = sorted(p.name for p in (root/'benchmarks/deep-swe/tasks').iterdir() if p.is_dir())
rows = []
for task in tasks:
    reward_path = root/'results/raw/manual'/task/'logs/verifier/reward.json'
    patch_path = root/'orchestrator'/f'{task}_model.patch'
    reward = None
    if reward_path.exists():
        try:
            reward = json.loads(reward_path.read_text())
        except json.JSONDecodeError:
            reward = {'parse_error': True}
    rows.append((task, reward, patch_path.exists()))
solved = [r for r in rows if isinstance(r[1], dict) and r[1].get('reward') == 1]
print(f'tasks={len(rows)} solved_by_canonical_reward={len(solved)}')
for task, reward, patch in rows:
    good = isinstance(reward, dict) and reward.get('reward') == 1
    if not good:
        print(f'PENDING {task} reward={reward!r} patch={patch}')
PY
```

Classify each task as exactly one of:

- `DONE_VERIFIED`: canonical `reward.json` proves reward 1 and artifacts are intact.
- `DONE_NEEDS_AUDIT`: reward 1 exists but artifact integrity, provenance, or platform evidence is incomplete.
- `PENDING`: no valid reward 1.
- `BLOCKED_ENVIRONMENT`: unable to run because of Docker, architecture, dependency, or infrastructure failure.
- `INVALID_RESULT`: reward file is malformed, contradictory, or produced by the wrong harness.

Prioritize `INVALID_RESULT`, then `PENDING`, then `DONE_NEEDS_AUDIT`. Do not rerun verified tasks unless performing a documented determinism sample or repairing missing evidence.

Maintain a machine-readable ledger such as `results/deepswe-run-ledger.jsonl`. Append only; never rewrite history. Each record must include:

```json
{
  "task": "task-name",
  "model": "glm-5-2",
  "harness": "devin-cli",
  "base_commit": "...",
  "platform": "arm64-rosetta|native-x86_64",
  "image": "...",
  "attempt": 1,
  "status": "verified|blocked|invalid",
  "reward_path": "results/raw/manual/task/logs/verifier/reward.json",
  "command": "...",
  "exit_code": 0,
  "timestamp_start": "...",
  "timestamp_end": "...",
  "notes": "..."
}
```

---

## 4. Parallelism and delegation limits

Use **no more than two concurrent subagents**, and use them only for discovery or setup:

- locating the task's relevant source files;
- identifying package-manager and test commands;
- preparing a clean container or workspace;
- diagnosing an environment failure.

Do not delegate implementation to subagents. The primary Devin orchestrator performs implementation, review, patch extraction, and verification. Two subagents agreeing is not evidence; run the command yourself.

Do not run all 113 containers concurrently. Do not pull every image up front. Do not run local training, model conversion, or unrelated heavyweight workloads during the benchmark.

---

## 5. Per-task solve protocol

For each `PENDING` task, create an isolated work directory or container based on the task metadata. Read only public task inputs:

```bash
cat benchmarks/deep-swe/tasks/<task>/task.toml
cat benchmarks/deep-swe/tasks/<task>/instruction.md
cat benchmarks/deep-swe/tasks/<task>/environment/Dockerfile
```

Do not read hidden verifier inputs while solving. Determine the repository, base commit, language, package manager, build command, and likely test command from the task environment and public source.

### 5.1 Establish a clean baseline

1. Start from the declared base commit.
2. Confirm the working tree is clean.
3. Run the smallest relevant existing test suite before editing.
4. Record baseline exit status and failures.
5. Confirm the task's source checkout is not sharing mutable state with another task.

If the baseline itself fails, distinguish pre-existing failures from your change. Do not “fix” unrelated baseline failures unless the task requires it.

### 5.2 Understand before editing

Trace the public behavior end-to-end:

- Find the public API, command, or entry point named by the instruction.
- Find adjacent types, validation, error handling, and serialization code.
- Find the existing test conventions and fixture patterns.
- Search for analogous behavior elsewhere in the repository.
- Identify compatibility constraints and supported versions.
- Note whether the requested behavior is synchronous, asynchronous, streaming, transactional, or stateful.

Prefer the smallest change that satisfies the requested contract and preserves existing behavior. Do not redesign unrelated architecture.

### 5.3 Implement narrowly

Rules:

- Modify production code first; do not rely on changing tests.
- Preserve public API compatibility unless the instruction explicitly requires a breaking change.
- Match local naming, formatting, error, and typing conventions.
- Handle boundary cases implied by the instruction, not only the happy path.
- Avoid broad dependency upgrades.
- Never alter Dockerfiles, CI policy, credentials, or verifier files to manufacture a pass.
- Never copy the reference solution into the implementation.
- Never add generated files, caches, binaries, `node_modules`, `.venv`, `.gocache`, `dist`, `build`, or `__pycache__` to the patch.

### 5.4 Test incrementally

After each meaningful change:

1. Run the narrowest relevant test.
2. Run the package or module suite.
3. Run the repository regression suite if affordable.
4. Re-run the exact behavior with a real input or command.
5. Inspect the diff and status.

A green test command is necessary but not sufficient. Verify the actual behavior against actual input. If the same failure repeats three times, stop tweaking parameters and change the diagnostic approach.

### 5.5 Freeze a clean patch

Before extraction:

```bash
git status --short
git diff --check
git diff --stat
git diff <base_commit> HEAD > /artifacts/model.patch
```

The patch must be a normal Git diff from the task base commit. It must not contain agent runtime state, hidden tests, secrets, unrelated edits, or build output.

Verify patch application on a pristine checkout before trusting it:

```bash
git diff --exit-code <base_commit> -- . ':!tests'
git apply --check /artifacts/model.patch
```

The exact commands may differ inside Harbor, but the invariants do not.

---

## 6. Isolated verifier protocol

The verifier must run in a separate pristine environment. Use the task's declared Docker image and verifier files. The canonical pattern is:

```bash
cd ~/aa-coding-index
TASK=<task>
IMG=$(sed -n 's/^docker_image[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "benchmarks/deep-swe/tasks/$TASK/task.toml")
VERIFY_ROOT="/tmp/deepswe-verify/$TASK"
rm -rf "$VERIFY_ROOT"
mkdir -p "$VERIFY_ROOT/artifacts"
cp "orchestrator/${TASK}_model.patch" "$VERIFY_ROOT/artifacts/model.patch"

docker pull "$IMG"
docker build -t "deepswe-verifier-$TASK" "benchmarks/deep-swe/tasks/$TASK/tests"
docker run --rm \
  -v "$VERIFY_ROOT:/logs" \
  "deepswe-verifier-$TASK" \
  /tests/test.sh
```

Capture the complete verifier output, not only the reward:

```bash
mkdir -p "results/raw/manual/$TASK/logs/verifier"
cp "$VERIFY_ROOT/verifier/reward.json" "results/raw/manual/$TASK/logs/verifier/"
cp "$VERIFY_ROOT/verifier/ctrf.json" "results/raw/manual/$TASK/logs/verifier/"
cp "$VERIFY_ROOT/verifier/run.log" "results/raw/manual/$TASK/logs/verifier/"
cp -R "$VERIFY_ROOT/verifier/reports" "results/raw/manual/$TASK/logs/verifier/" 2>/dev/null || true
```

If the verifier emits `reward.txt=-1`, treat it as a crash sentinel unless a valid `reward.json` supersedes it. Diagnose the crash; never convert it into a pass.

The grader's semantics are strict:

```text
reward=1 iff F2P total > 0, every F2P passes, and zero P2P tests fail
```

Check all fields:

```bash
python3 - <<'PY'
import json, sys
from pathlib import Path
p = Path('results/raw/manual')
failed = []
for reward_path in sorted(p.glob('*/logs/verifier/reward.json')):
    d = json.loads(reward_path.read_text())
    ok = (
        d.get('reward') == 1 and
        d.get('f2p_total', 0) > 0 and
        d.get('f2p_passed') == d.get('f2p_total') and
        d.get('p2p_passed') == d.get('p2p_total')
    )
    if not ok:
        failed.append((str(reward_path), d))
print(f'checked={len(list(p.glob("*/logs/verifier/reward.json")))} invalid={len(failed)}')
for row in failed:
    print(row)
if failed:
    sys.exit(1)
PY
```

---

## 7. Architecture policy

The benchmark images are generally `linux/amd64`. On Apple Silicon, Docker Desktop may use Rosetta x86 emulation.

Use arm64/Rosetta for ordinary tasks when the verifier is deterministic and native extensions are not implicated. Use a native x86-64 Linux machine for tasks involving architecture-sensitive native libraries, segfaults, incompatible wheels, timing behavior, or unexplained emulation failures.

Record platform in every ledger row. Do not silently mix platform results.

If a task passes on arm64 and fails on native x86, repeat the run and investigate whether the difference is deterministic platform behavior. A platform difference is not automatically flakiness. Preserve both results and identify which platform is authoritative for the reported run.

Known classes requiring extra scrutiny:

- Rust compiler/runtime behavior;
- Go runtime and duration ordering;
- Python native extensions such as Polars, PyArrow, or PSD parsers;
- WASM runtimes;
- timing-sensitive servers and reload tests.

---

## 8. Failure handling

Classify failures before changing code:

### Model failure
The model misunderstood the requirement or produced an incomplete implementation. Re-read the public instruction and trace the affected code path.

### Protocol failure
The model emitted a valid action in a format the harness did not parse. Inspect tokenizer/output/parser/executor layers independently before blaming the model.

### Harness failure
The CLI, container, patch extractor, mount, or test command is wrong. Reproduce with a tiny smoke case.

### Repository failure
The task checkout, dependency lockfile, base commit, or package manager is inconsistent. Compare against the declared environment.

### Infrastructure failure
Docker daemon, disk, network, remote VM, or native extension failed. Preserve logs and retry only after the environment is repaired.

After two identical failures, ask whether the tool or approach is wrong. After three, change approach rather than endlessly adjusting flags.

Never:

- edit hidden tests;
- weaken or skip the grader;
- modify `test.sh` to return success;
- claim success from a timeout;
- reuse a stale result from another commit or model;
- delete contradictory evidence;
- hide a failed task by removing its directory.

---

## 9. Batch lifecycle and disk hygiene

Operate in small batches:

1. Select 3–4 tasks with compatible resource profiles.
2. Pull/build only those images.
3. Solve and verify each task.
4. Capture all artifacts and ledger rows.
5. Remove stopped containers and obsolete images.
6. Recheck disk space before the next batch.

Example cleanup after artifacts are safely copied:

```bash
docker rm -f <container-id> 2>/dev/null || true
docker rmi -f "deepswe-verifier-$TASK" 2>/dev/null || true
docker system df
```

Use `docker system prune -af` only when it is known not to remove active work. Never destroy a container or image before its logs, patch, and verifier outputs are captured.

---

## 10. Final audit before declaring 113/113

Run an independent audit from a fresh shell:

```bash
cd ~/aa-coding-index

# Count task definitions.
find benchmarks/deep-swe/tasks -mindepth 1 -maxdepth 1 -type d | wc -l

# Validate every canonical reward.
# Validate every reward has matching CTRF.
# Validate every task has a model patch.
# Validate orchestrator and captured model patches are byte-identical.
# Validate no patch contains build/cache/credential files.
# Validate all patches are syntactically valid git diff output.
```

The audit must report:

- task definitions: `113`;
- canonical reward files: `113`;
- `reward=1`: `113`;
- F2P total and passed totals: equal for every task;
- P2P total and passed totals: equal for every task;
- CTRF files: `113`;
- orchestrator patches: `113`;
- captured patches: `113`;
- patch mismatches: `0`;
- invalid or contradictory artifacts: `0`.

Run a deterministic re-verification sample across languages and repositories. At minimum select five diverse tasks, document the original and rerun reward, and require matching outcomes unless a platform explanation is recorded.

Review the final diff of the index itself. Do not commit generated verifier output or large benchmark artifacts unless that is explicitly part of the repository's intended release structure.

---

## 11. Reporting language

Use precise language:

- Say **“113/113 canonical verifier rewards are 1.0”** when the audit proves it.
- Say **“5,877 F2P and 231,352 P2P tests passed”** only when those exact totals are computed from the captured artifacts.
- Say **“verified on Apple Silicon under Rosetta”** or **“verified on native x86-64”**, never simply “verified” when platform matters.
- Say **“technical world-record candidate”** until an independent leaderboard comparison or public reproducibility package establishes the record.
- Do not imply official recognition from a local benchmark run.

Final report format:

```markdown
# DeepSWE 1.1 Completion Report

## Result
- Tasks: 113/113
- Reward: 113/113 at 1.0
- Model: GLM-5.2 (`glm-5-2`)
- Harness: Devin CLI
- F2P: <passed>/<total>
- P2P: <passed>/<total>
- Platforms: <summary>
- Re-verification sample: <N>/<N> matching

## Evidence
- Canonical rewards: <path>
- CTRF reports: <path>
- Run logs: <path>
- Model patches: <path>
- Ledger: <path>
- Audit command and exit code: <command>, 0

## Exceptions
- <platform-specific behavior, infrastructure failures, or none>

## Record status
- Local result: confirmed by artifact audit.
- World-record status: <confirmed by external comparison | candidate pending independent comparison>.
```

Do not add Devin co-author trailers, “Generated with Devin” lines, or AI branding to commits.

---

## 12. Persistence and handoff

At the end of every session:

1. Save the current ledger and progress summary.
2. Save the next pending task list.
3. Record any hard-won lesson in MAOS.
4. Update the MAOS task only when the evidence supports the update.
5. Close the MAOS agent identity with the actual result, not a self-attested success.
6. Leave Docker and the working tree in a known state.

Example:

```bash
cd ~/mac-ai-os
uv run app onboard record deepswe_<slug> "<specific reproducible lesson>" --source incident
uv run app agent end <agent-id> \
  --summary "DeepSWE batch completed with captured verifier evidence" \
  --result "<exact verified counts, paths, platform, and remaining unknowns>"
```

The final standard is simple: **the score is an evidence-backed property of the verifier artifacts, not a story the agent tells about its own work.**
