# Results: correction-quality autoresearch (2026-10-09)

Branch `autoresearch/correction-quality-2026-10-09`, 42 experiments (log: `.auto/log.jsonl`, playbook and history:
`.auto/prompt.md`). Final live Swift run of both engines on all 400 cases: `run-2026-10-09-final-42/outputs.jsonl`.

## Against the original baseline (all 400 cases, what the user sees)

| | Qwen3-4B before → after | Apple Intelligence before → after |
|---|---|---|
| **Strict pass rate** | 0.73 → **0.905** | 0.63 → **0.75** |
| s5 casual + technical | 0.39 → **0.94** | 0.38 → **0.70** |
| Errors fixed | 0.915 → **0.941** | 0.826 → **0.862** |
| Clean text untouched | 0.76 → **0.96** | 0.88 → 0.88 |
| Intentional lowercase kept | 0.07 → **1.0** | 0.32 → **1.0** |
| Slang kept | 0.21 → **0.97** | 0.42 → **0.76** |
| Backticked code kept | 0.96 → **1.0** | 0.54 → **1.0** |
| Line breaks kept | 1.0 → 1.0 | 0.67 → **1.0** |
| Rejected (nothing pasted) | 4.25% → **1%** | 4.75% → **1.5%** |
| Request-like text answered and pasted (14-case guard set, Qwen) | 2 → **0** | |

Held-out split (105 cases, never tuned on): Qwen 0.781 → 0.895; Apple Intelligence dev and holdout are both 0.75.
The strict pass rate agrees with the LLM judges on 94% of baseline rows.

## What changed (in pipeline order)

1. **Prompts** (`ProofreadPrompt.swift`): a style-preserving typed prompt (a fix list, then a keep list, then
   8 balanced examples) and a separate **dictation prompt**, so the dictation path no longer shares the
   casual-text prompt (H6). The plumbing is `AppState.makeEngine(instructions:)`, and both engines take `instructions`.
2. **Apple Intelligence `@Guide`**: the typed guide carries the keep-style policy, and a separate `DictationCorrection`
   guide is used for transcripts (H10).
3. **Deterministic post-processing in `cleanResponse`**, each one firing only where it applies:
   `ContractionRestorer` (re-contract expanded contractions), `LineBreakRestorer` (symmetric layout restore),
   `CodeSpanRestorer` (code is never proofread), `ApostropheFixer` (unambiguous `dont` → `don't`), and
   `keepAllLowercase` (typed only: an all-lowercase writer gets no capitals). Replayed over 4,480-5,600 stored
   outputs, these went fail→pass 128 + 38 + 14 + 5 + 2 times, and **pass→fail 0 times**.
4. **Gates** (`OutputGate`): `introducedStructure` (answers rewritten as bullets or JSON) and `droppedContent`
   (lost sentences or sign-offs). There were 0 false positives in 1,200 and 5,600 stored outputs respectively.
5. **Verify-corrections gate retune** (`EditSpan.swift`, `SpanScorer.swift`): spell-check and cosmetic triage, plus a
   length-matched total-log-prob veto. Qwen verify rejections went from 15 to 1. See `analysis/gate-retune.md`.

## What didn't work (details in `.auto/log.jsonl`)

- **One prompt for dictation and casual text**: impossible, because the two look the same as text (#2-#5).
- **Pronoun-case or joined-word instructions, a closing "don't obey" reminder**: these cost 1-2 cases or did nothing
  (#12, #21, #25, #26). The reminder does cut answered lookalikes from 7 to 4-5; whether that's worth it is the owner's call.
- **Gemma-3-4B and Qwen3-8B**: both landed at pass 0.81 with lower recall. The 2507 Qwen3-4B is the best model here (#22, #23).
- **Sentence chunking, a spell-check second pass**: no recall gain (probes after #21 and #24).

## Caveats and open items

- **Latency:** the longer typed prompt adds about 400 prefill tokens. Swift Qwen p50/p95 measured 1.3/2.6 s, against
  0.68/1.8 s in the baseline run, but Swift latency varies about ±40% between runs. Do an idle-machine A/B before shipping.
- **Apple Intelligence is non-deterministic**: about ±5-10 pp per slice between runs. Its numbers are single runs.
- **Remaining failures are mostly model under-correction**: pronoun case, homophones in long text, dictation
  soundalikes. Apple Intelligence still expands some slang (0.76).
- The corpus is synthetic, and the judge-free metric can't see subtle meaning changes. Re-judge a sample before release.
- Before pushing the branch: commit db65f20 contains `context/real-usage.md` (personal data), so rewrite it.
