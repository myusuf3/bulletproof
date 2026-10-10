# Correction eval - 2026-10-09 baseline

400 hand-written cases run through Apple Intelligence and Qwen3-4B using the
app's real chain: engine -> `OutputGate` -> verify-corrections (`ScoredGateEngine`).
This is the baseline to diff prompt or gate changes against.

- Code: commit `75e4a8a` (v0.0.19), prompt as in `bulletproof/Engines/ProofreadPrompt.swift` at that commit
- Settings: Qwen3-4B (`mlx-community/Qwen3-4B-Instruct-2507-4bit`), verify corrections on, the user's personal vocabulary (a scratch copy, so the real one was untouched)
- One run per engine. Apple Intelligence output varies between runs.
- Qwen ran second, after Apple Intelligence, in the same process.

## Files

| Path | What |
|---|---|
| `corpus/slice{1..5}.jsonl` | Cases, 80 per slice (70 with errors, 10 clean controls). Fields: `input`, `expected.acceptableOutputs`, `errors` ("wrong -> right"), `mustPreserve`, `tags` |
| `outputs.jsonl` | Raw run output, one row per (id, engine): `raw` (model), `gated`, `scored` (what the user sees; `REJECTED(...)` = nothing pasted), `ms` |
| `scored.jsonl` | `outputs.jsonl` joined with the corpus, plus deterministic categories (`raw_cat`, `gated_cat`, `scored_cat`) |
| `judged/s{1..5}.jsonl` | Agent verdicts for every non-exact-match row: `verdict` (GOOD / PARTIAL / MISSED / MUDDLED / INTRODUCED_ERROR / ANSWERED), `gate_verdict` (ATE_GOOD_FIX / BLOCKED_BAD), `note` |
| `analyze.py`, `report.py` | Scoring and report scripts. `report.py . ../errors.txt` rebuilds `../errors.txt` |
| `qwen-rerun-with-span-scores/outputs.jsonl` | All 400 cases re-run on Qwen only with the updated runner (frozen vocabulary, `spans` field with every verify-gate score) |
| `judge-rubric.md` | The rubric the judge agents used. Reuse it so new verdicts are comparable |
| `runner/ZZScratchCorrectionEval.swift` | The test runner, current version (not compiled from here; see below) |

Slices: s1 spelling typos, s2 grammar, s3 dictation transcripts, s4 paragraphs, s5 casual + technical.

## Re-running

```bash
D=bulletproof-correction-improvements/baseline-2026-10-09   # run from the repo root
OUT=/tmp/eval-run   # use a fresh directory per run
mkdir -p $OUT && cp -R $D/corpus $D/analyze.py $D/report.py $OUT/
cat $OUT/corpus/slice*.jsonl > $OUT/all.jsonl
cp $D/runner/ZZScratchCorrectionEval.swift bulletproofTests/

TEST_RUNNER_BULLETPROOF_EVAL_CORPUS=$OUT/all.jsonl TEST_RUNNER_BULLETPROOF_EVAL_OUT=$OUT/outputs.jsonl \
  xcodebuild test -project bulletproof.xcodeproj -scheme bulletproof -destination 'platform=macOS' \
  -only-testing:bulletproofTests/ZZScratchCorrectionEval
# Qwen only: about 10 minutes for 400 cases (the s5 slice alone takes 2). Both engines take about 15.
# Add TEST_RUNNER_BULLETPROOF_EVAL_SKIP_AI=1 for Qwen only (deterministic, so it's best for A/B tests).
# Add TEST_RUNNER_BULLETPROOF_EVAL_LOCAL_MODEL=<hf repo id> to evaluate another installed local model.

rm bulletproofTests/ZZScratchCorrectionEval.swift
python3 $OUT/analyze.py $OUT/outputs.jsonl   # writes $OUT/scored.jsonl, prints deterministic summary
```

`analyze.py` alone gives exact-match and per-error-fixed numbers with no
judging. `report.py <dir> <errors.txt>` needs a `judged/` directory. New outputs
that differ from this run need fresh judgments, because the verdicts here are
keyed to these exact outputs.

## Runner changes after the baseline run

`outputs.jsonl` was produced by the first version of the runner. The version in `runner/` differs in five ways:

1. **Frozen vocabulary.** In the baseline the scratch vocabulary could learn during the run, and it observed each accepted output twice. That's how Apple Intelligence's missed `signficantly` became protected and then vetoed Qwen's correct fix of s5-061 as `protectedWordRemoved`. The runner now passes `isUnknownWord: { _ in false }`, so runs are order-independent.
2. **One gate pass.** The scored gate wraps the model output directly instead of re-running the OutputGate.
3. **Single scoring pass.** `scored` is derived from the logged span verdicts, not by running `ScoredGateEngine` again. That matched the real gate on 400/400 rows and made the run about 25% faster.
4. **Configurable local model** via `BULLETPROOF_EVAL_LOCAL_MODEL` (default Qwen3-4B). That model both generates and scores, as in the app.
5. **Span scores.** Each row gets a `spans` array: `original`, `replacement`, `replacementScore`, `originalScore`, `suffixScore`, and `verdict` (accepted / belowFloor / originalMoreLikely / suffixBroken / unscored). Missing scores are omitted from the JSON.

The `qwen-rerun-with-span-scores/` run uses the new runner.

## Baseline numbers (raw model, 400 cases each)

| | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD + PRESERVED | 279 | 323 |
| MUDDLED | 69 | 61 |
| PARTIAL + MISSED | 47 | 11 |
| INTRODUCED_ERROR | 4 | 4 |
| Clean controls changed (of 50) | 7 | 12 |
| Verify gate: good fixes thrown away / bad outputs blocked | 16 / 3 | 14 / 3 |
| p50 / p95 latency | 530 / 1355 ms | 680 / 1836 ms |

Most of the muddling is in s5 (casual text): both models capitalize
deliberate lowercase, expand slang, and add formal punctuation. Apple
Intelligence also expands contractions and strips code backticks.
