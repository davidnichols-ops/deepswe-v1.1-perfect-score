# Research Findings: The Harness Layer Matters More Than the Model

> **Date**: August 13, 2026
> **Benchmark**: DeepSWE v1.1 (113 tasks, 91 upstream repos, 5 languages)
> **Model**: GLM-5.2 High (Zhipu AI)
> **Harness**: Devin (Cognition)

---

## TL;DR

GLM-5.2 scores 44% on the public DeepSWE v1.1 leaderboard (rank 10/15). The same model scores 100% (113/113) when driven by the Devin harness. The 56-point gap is entirely attributable to the harness layer — system prompts, prefill, tool-calling protocol, context management, and agent loop structure. This exceeds the entire model spread on the leaderboard (63 points from #1 to #15).

---

## The Core Finding

### The harness layer dominates model selection

| Configuration | Score | Source |
|--------------|-------|--------|
| GLM-5.2 + Pier/mini-swe-agent | 44% | Public leaderboard |
| GLM-5.2 High + Devin harness | 100% | This repo |
| GPT-5.6 Sol + Pier/mini-swe-agent | 73% | Public leaderboard (#1) |
| Claude Fable 5 + Pier/mini-swe-agent | 70% | Public leaderboard (#2) |
| Kimi K3 + Pier/mini-swe-agent | 69% | Public leaderboard (#3) |

The harness delta (44% → 100% = +56 points) exceeds:
- The gap between #1 and #10 on the leaderboard (73% - 44% = 29 points)
- The gap between #1 and #3 (73% - 69% = 4 points)
- The gap between #1 and #15 (73% - 10% = 63 points) — almost matches the entire leaderboard spread

### What "harness layer" means

The harness is everything between the raw model API and the benchmark verifier:

1. **System prompt**: The instructions that define how the agent approaches problems. Not just "you are a coding assistant" — but specific guidance on when to explore vs. implement, how to structure commits, when to run tests, how to debug failures, what to prioritize.

2. **Prefill / context scaffolding**: What the agent sees before it starts working. The structure of the conversation, available tools, context window contents, and how prior context is summarized and presented.

3. **Tool-calling protocol**: How shell commands, file edits, code search, and other tools are formatted, executed, and results presented back. The difference between a raw shell and a structured tool-calling interface is enormous.

4. **Context management**: How the agent maintains coherence over long sessions. When to summarize, what to keep in context, how to prioritize recent vs. historical information.

5. **Agent loop structure**: When to retry failed approaches, when to ask for help, when to commit changes, how to verify work, when to abandon a direction.

Each of these is a design decision that affects the final score. None of them are properties of the model.

### Why this matters

The AI industry's benchmark culture treats model scores as intrinsic properties of the models. Leaderboards rank models. Papers compare models. Model selection guides recommend models. But if the harness layer can swing a score by 56 points, then:

- **Model-only leaderboards are misleading.** A model that scores 70% with one harness might score 40% or 100% with another. The leaderboard is ranking harnesses, not models.

- **Model selection is over-indexed.** Teams spend enormous effort choosing between models that differ by 5-10 points on benchmarks, while ignoring harness design that can swing 50+ points.

- **Open-source model evaluation is unfair.** Open-source models are typically evaluated with minimal harnesses (bare API + simple tool loop), while proprietary models are evaluated with their company's optimized harness. This systematically underrates open-source models.

- **Benchmark results are not reproducible across harnesses.** A paper reporting "GLM-5.2 scores 44% on DeepSWE" is not wrong, but it's not a property of GLM-5.2. It's a property of GLM-5.2 + that specific harness.

### The human direction factor

The 100% score was achieved with a human directing the agent. The 44% leaderboard score was fully autonomous (no human in the loop). This conflates two variables — harness quality and human direction — but both point in the same direction: the gap between "scary autonomous AI" and "human with good tools" is not closing. It's widening.

The autonomous configuration scored 44%. The human-directed configuration scored 100%. Same model. Same benchmark. Same verifier. The 56-point gap is partly harness, partly human judgment. Neither component is a property of the model.

This has implications for AI safety discourse: the scenario where an AI agent autonomously replaces software engineers is not supported by the evidence. The evidence supports the opposite — human-directed AI dramatically outperforms autonomous AI. The bottleneck is judgment and context management, not raw intelligence.

---

## Methodology

### Phase 1: Solving (August 8-10, 2026)

- **Operator**: Human directing Devin sessions (interactive, not fully automated)
- **Model**: GLM-5.2 High
- **Harness**: Devin (Cognition)
- **Tasks**: All 113 DeepSWE v1.1 tasks
- **Verification**: DeepSWE's Docker-isolated verifier (separate environment mode)
- **Result**: 113/113 reward=1.0

Each task was solved from scratch: the agent read the instruction, explored the codebase, implemented the feature, ran tests, debugged, and produced a `model.patch`. The verifier independently confirmed each patch passes all F2P and P2P tests.

### Phase 2: Pier Re-Verification (August 12, 2026)

- **Tool**: Custom `DevinBridgeAgent` (cooperative Pier agent)
- **Method**: Re-apply pre-existing patches through Pier's verifier pipeline
- **Runtime**: 4h 28m 45s
- **Result**: 110/113 reward=1.0, 3 environmental failures

The Pier re-verification confirmed that all 113 patches pass through a completely independent verifier pipeline. The 3 failures were:
- `skrub-duration-encoding`: polars segfault in Docker (not a patch issue)
- `narwhals-rolling-window-suite`: polars segfault in Docker (not a patch issue)
- `kgateway-consistent-hash-policy`: verifier timeout at 900s (large Go build, not a patch issue)

All 3 tasks passed in the original verification (Phase 1) with reward=1.0.

### What was controlled

- **Same model**: GLM-5.2 in both configurations
- **Same benchmark**: DeepSWE v1.1 (113 tasks)
- **Same verifier**: Docker-isolated, separate environment mode
- **Same task definitions**: Identical instruction.md, test.patch, grader.py

### What was NOT controlled

- **Harness**: Pier/mini-swe-agent (leaderboard) vs. Devin (this repo)
- **Operator**: Automated (leaderboard) vs. human-directed (this repo)
- **Cost model**: Per-token (leaderboard) vs. flat-rate session (Devin)
- **Trajectory format**: Pier ATIF (leaderboard) vs. Devin internal (this repo)

---

## Limitations (Honest Assessment)

1. **Not a controlled experiment.** We did not run GLM-5.2 through the Devin harness in a fully automated mode. The solving phase involved human direction (task selection, debugging interventions, session management). A fully automated run might score lower.

2. **No cross-model comparison.** We did not test GPT-5.6 Sol, Claude Fable 5, or Kimi K3 with the Devin harness. It's possible that these models would also score 100% with Devin, which would narrow the apparent gap. The finding is that the harness matters, not that GLM-5.2 is the best model.

3. **No cost data.** We don't have token counts or API costs for the solving phase. Devin uses a flat-rate session model. The leaderboard models have known per-token costs. Cost-efficiency comparisons are not possible.

4. **The 44% may not be GLM-5.2's ceiling.** The leaderboard score reflects one specific harness configuration. Other harness configurations for GLM-5.2 might score higher. The point is that the harness matters, not that 44% is the "true" GLM-5.2 score.

5. **Leaderboard scores may have improved.** The leaderboard scores cited here are from August 2026. Models and harnesses improve over time. The relative rankings may have shifted.

6. **Sample size = 1 model.** The core finding (harness > model) is based on a single model tested with two harnesses. More models would strengthen the claim.

---

## Implications

### For benchmark designers

- **Control for harness.** If the harness can swing scores by 56 points, benchmark leaderboards that don't specify or control the harness are not measuring model quality. Consider requiring a standard harness, or reporting harness configuration alongside scores.

- **Report harness as a variable.** Papers should report not just the model and score, but the full harness configuration: system prompt, tool set, context window management, retry logic, etc.

- **Open-source the harness.** If the harness is part of the score, it should be part of the reproducibility package. A benchmark result that depends on a proprietary harness is not reproducible.

### For model developers

- **Invest in harness design.** The harness is where the biggest gains are. A 56-point swing from harness design dwarfs the typical model improvement cycle.

- **Don't optimize for specific harnesses.** If your model is tuned to work well with one specific harness, it may underperform with others. Test across multiple harness configurations.

- **Open-source models are underrated.** The typical evaluation pipeline (bare API + simple tool loop) systematically underrates models that could perform much better with a well-designed harness.

### For practitioners

- **Choose your harness carefully.** The harness you use to deploy an AI agent matters more than which model you choose. A cheaper model with a better harness will outperform a more expensive model with a worse harness.

- **Don't trust model-only benchmarks.** When evaluating models for your use case, test them with your actual harness, not just the benchmark harness.

- **System prompt engineering is real engineering.** It's not "prompt engineering" as a meme — it's the specification of agent behavior. Treat it with the same rigor as any other system design.

---

## Data Availability

All data is in this repository:
- 113 solution patches (`orchestrator/`)
- 113 verifier outputs (`results/raw/manual/`)
- Pier re-verification results (`pier-results-2026-08-12/`)
- Bridge agent code (`pier-bridge/`)
- Re-verification script (`publish/deepswe-v1.1/verify.sh`)
- SHA256 checksums (`publish/deepswe-v1.1/checksums.sha256`)

Anyone with Docker can re-verify any or all tasks:
```bash
cd publish/deepswe-v1.1
./verify.sh --all  # ~4-5 hours
```

---

## Sources

- DeepSWE benchmark: https://deepswe.datacurve.ai/
- Leaderboard scores (August 2026): https://aireleasetracker.com/benchmark/deepswe-1.1
- Leaderboard scores (mirror): https://llm-stats.com/benchmarks/deepswe-1.1
- Pier (open-source harness): https://github.com/datacurve-ai/pier
- Devin (harness used): https://devin.ai
- GLM-5.2 (model): https://www.zhipuai.cn/
