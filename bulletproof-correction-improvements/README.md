# bulletproof-correction-improvements

Everything gathered while evaluating how well bulletproof's proofreading corrects text, set up as a starting point for automated research on prompts, gates and models.

**Question:** "the app muddles what I'm saying and doesn't correct anything." Is that true, and why?

**Short answer:** the models fix most errors (Qwen3-4B 92%, Apple Intelligence 84%), but both restyle casual text heavily. The prompt's own examples teach this. The verify-corrections gate also throws away about 4% of outputs, and 30 of its 36 rejections were good fixes. On dictation those rejections are silent. Details are in `FINDINGS.md`.

## Start here

| Read | For |
|---|---|
| `FINDINGS.md` | The analysis: numbers, root causes ranked, what works, caveats |
| `HYPOTHESES.md` | The experiment backlog (H1-H10): objective, metrics, evidence, risks, and gaps in the data |
| `errors.txt` | Every failure example from the baseline, grouped by engine and failure type (human-readable) |
| `context/pipeline.md` | How a correction flows through the code: the prompt verbatim, gates, thresholds, file:line pointers |
| `context/real-usage.md` | The developer's real settings and telemetry (personal, so review before publishing) |

## Layout

```
bulletproof-correction-improvements/
├── README.md, FINDINGS.md, HYPOTHESES.md, errors.txt
├── baseline-2026-10-09/                   the run itself (see its README for re-running)
│   ├── corpus/slice{1..5}.jsonl           400 cases: input, acceptableOutputs, errors ("wrong -> right"), mustPreserve, tags
│   ├── outputs.jsonl                      800 rows (400 × 2 engines): raw, gated, scored (= what the user sees), ms
│   ├── scored.jsonl                       outputs joined with corpus + deterministic categories
│   ├── judged/s{1..5}.jsonl               judge verdicts for every non-exact row
│   ├── judge-rubric.md                    the exact rubric - reuse it for comparable verdicts
│   ├── analyze.py, report.py              scored.jsonl and errors.txt generators
│   ├── runner/ZZScratchCorrectionEval.swift   the eval test (copy into bulletproofTests/ to run)
│   └── qwen-rerun-with-span-scores/outputs.jsonl   Qwen re-run logging every verify-gate span score
├── analysis/
│   ├── cases.jsonl                        ★ one row per (case, engine), everything joined - the main dataset
│   ├── metrics.py                         judge-free proxy metrics; --compare for A/B, --calibrate vs judges
│   ├── build_analysis.py                  regenerates cases.jsonl and the .md files below
│   ├── muddle-taxonomy.md                 bad outputs bucketed by theme (capitalization, slang, code…)
│   ├── gate-rejections.md                 all 36 rejections with judged verdicts
│   ├── span-scores.md                     why the verify gate vetoes good fixes, with score distributions
│   └── slice-reports.md                   the five judges' written reports
└── context/
    ├── pipeline.md, real-usage.md
    ├── source-snapshot/                   the relevant Swift files frozen at commit 75e4a8a
    ├── prior-bench/                       the repo's earlier 43-case bench corpus and its reports
    ├── corpus-generators/                 the scripts that produced each slice (take an output path argument)
    └── 0002-…, 0005-…, 0007-… .md         related ADRs (local inference, correction tracking, dictation)
```

## `analysis/cases.jsonl` fields

`id`, `slice`, `slice_name`, `engine`, `kind` (fix/unchanged), `tags`, `input`, `errors`, `mustPreserve`, `acceptable`, `raw` (model output), `gated`, `user_sees` (after the verify gate; `REJECTED(...)` means nothing pasted), `raw_cat` / `user_sees_cat` (deterministic), `verdict` (GOOD / PRESERVED / PARTIAL / MISSED / MUDDLED / INTRODUCED_ERROR / ANSWERED), `verdict_source` (judge or exact-match), `gate_verdict` (ATE_GOOD_FIX / BLOCKED_BAD), `note` (the judge's reason), `missed_errors` (s4 only), `errors_fixed_regex`, `ms`.

## The research loop

1. Change one thing (the prompt in `bulletproof/Engines/ProofreadPrompt.swift`, a gate, the model).
2. Run Qwen-only (deterministic, about 10 minutes for 400 cases; the s5 slice alone takes 2 minutes). Runs share one GPU, so run them one at a time; running them in parallel slows each one and distorts latency. See `baseline-2026-10-09/README.md`.
3. `python3 analysis/metrics.py NEW/outputs.jsonl --compare baseline-2026-10-09/outputs.jsonl`
4. For promising candidates, judge the non-exact rows with `baseline-2026-10-09/judge-rubric.md`, then run `build_analysis.py`-style joins and compare verdict counts with `FINDINGS.md`.
5. Record the result next to the baseline as `run-YYYY-MM-DD-<change>/`, with the same file names.

The objective, constraints and overfitting guard are defined at the top of `HYPOTHESES.md`.

## Provenance

- **Date and code:** 2026-10-09, commit `75e4a8a` (v0.0.19), macOS 26 (Darwin 25.6), Apple silicon.
- **Models:** Apple Intelligence on-device (`SystemLanguageModel`, permissive guardrails) and `mlx-community/Qwen3-4B-Instruct-2507-4bit` at temperature 0.
- **Corpus:** written for this eval by five agents (one per slice). It's original text, not copied from external sources.
- **Judging:** each agent judged its own slice against the rubric.
