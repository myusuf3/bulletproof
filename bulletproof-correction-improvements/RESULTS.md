# Results: correction-quality autoresearch (2026-10-09)

Branch `autoresearch/correction-quality-2026-10-09`, 42 experiments (log: `.auto/log.jsonl`, playbook and history:
`.auto/prompt.md`). Final live Swift run of both engines on all 400 cases: `run-2026-10-09-final-42/outputs.jsonl`.

## Against the original baseline (all 400 cases, what the user sees; final live Swift run #48)

| | Qwen3-4B before → after | Apple Intelligence before → after |
|---|---|---|
| **Strict pass rate** | 0.73 → **0.91** | 0.63 → **0.77** |
| s5 casual + technical | 0.39 → **0.95** | 0.38 → **0.76** |
| Errors fixed | 0.915 → **0.943** | 0.826 → **0.876** |
| Clean text untouched | 0.76 → **0.96** | 0.88 → **0.92** |
| Intentional lowercase kept | 0.07 → **1.0** | 0.32 → **1.0** |
| Slang kept | 0.21 → **1.0** | 0.42 → **0.88** |
| Backticked code kept | 0.96 → **1.0** | 0.54 → **1.0** |
| Must-preserve tokens kept | 0.61 → **1.0** | 0.59 → **0.93** |
| Line breaks kept | 1.0 → 1.0 | 0.67 → **1.0** |
| Rejected (nothing pasted) | 4.25% → **0.75%** | 4.75% → **1%** |
| Request-like text answered and pasted (14-case guard set, Qwen) | 2 → **0** | |

Outputs: `run-2026-10-10-final-48/outputs.jsonl`. Later fixes: #46 SpellCheckGate locale, #47 SlangRestorer.

Held-out split (105 cases, never tuned on): Qwen 0.781 → 0.895; Apple Intelligence dev and holdout are both 0.77.
The strict pass rate agrees with the LLM judges on 94% of baseline rows.

## Out-of-sample check (fresh set, `fresh-2026-10-10/`)

35 new cases written after tuning, before any model saw them, on topics outside the corpus and the prompt
examples. Python harness, Qwen3-4B, what the user sees:

| | Baseline chain (2856ecb) | Current chain |
|---|---|---|
| Pass rate | 0.714 | **0.914** |
| s5 casual + technical | 0.20 | **0.90** |
| Lowercase / slang kept | 0 / 0 | **1.0 / 1.0** |
| Clean text untouched | 0.50 | **0.88** |
| Errors fixed | 0.929 | 0.929 |

The gain on fresh cases (+0.20) is at least as large as on the tuning set (+0.15), so this isn't overfitting.
It also found a **gate bug**, now fixed (#46): the gate used the system dictionary (en_CA here) with per-word
language guessing. That rejected the US "neighbor" and *accepted* "teh", "alot" and "accomodate". On English systems
`SpellCheckGate` now flags a word only if both the US and British dictionaries do. Fresh set .914 → .943;
dev and holdout user_sees +1 each (the last verify-gate veto of a good fix, "accomodate", is gone). Over 406
introduced words in every stored output, no new word is flagged.

## What changed (in pipeline order)

1. **Prompts** (`ProofreadPrompt.swift`): a style-preserving typed prompt (a fix list, then a keep list, then
   8 balanced examples) and a separate **dictation prompt**, so the dictation path no longer shares the
   casual-text prompt (H6). The plumbing is `AppState.makeEngine(instructions:)`, and both engines take `instructions`.
2. **Apple Intelligence `@Guide`**: the typed guide carries the keep-style policy, and a separate `DictationCorrection`
   guide is used for transcripts (H10).
3. **Deterministic post-processing in `cleanResponse`**, each one firing only where it applies:
   `ContractionRestorer` (re-contract expanded contractions), `LineBreakRestorer` (symmetric layout restore),
   `CodeSpanRestorer` (code is never proofread), `SlangRestorer` (chat abbreviations the model expanded), `ApostropheFixer` (unambiguous `dont` → `don't`), and
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

- **Latency, measured and fixed (#49, #50):** the longer typed prompt (460 vs 158 tokens) made Qwen 1.92x slower
  (paired A/B), all from re-prefilling the instructions on every call. `LocalModelEngine` now builds the system
  prompt's KV cache once (`PrefixCacheStore`) and copies it into each session. The shipping config is now
  **0.57x the original app's median latency** (353 vs 609 ms paired; Swift all-400 p50 1304 → 401 ms, p95
  2577 → 1837 ms). Outputs are identical on 398/400 (2 near-tie flips, pass unchanged). Apple Intelligence
  exposes no KV cache, so its latency is unchanged (p50 ~0.68 s).
- **Apple Intelligence is non-deterministic**: about ±5-10 pp per slice between runs. Its numbers are single runs.
- **Remaining failures are mostly model under-correction**: pronoun case, homophones in long text, dictation
  soundalikes. Apple Intelligence still expands some slang (0.76).
- The corpus is synthetic, and the judge-free metric can't see subtle meaning changes. Re-judge a sample before release.
- Before pushing the branch: commit db65f20 contains `context/real-usage.md` (personal data), so rewrite it.
