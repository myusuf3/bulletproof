# Results: correction-quality autoresearch (2026-10-09)

Branch `autoresearch/correction-quality-2026-10-09`, 104 experiments (log: `.auto/log.jsonl`, playbook and history:
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

## Latest live run (#104, corrected metric, `run-2026-10-10-live-104/`)

| | Qwen3-4B, original → now | Apple Intelligence, original → now |
|---|---|---|
| **Pass (all 400, what the user sees)** | 0.735 → **0.923** (dev 0.929, holdout 0.905) | 0.635 → **0.810** (dev 0.814, holdout 0.800) |
| s5 casual + technical | 0.39 → **0.94** | 0.38 → **0.81** |
| Errors fixed | 0.915 → **0.956** | 0.826 → **0.888** |
| Clean text untouched | 0.76 → **0.96** | 0.88 → **0.96** |
| Lowercase / slang / code / line breaks kept | → **1.0 / 1.0 / 1.0 / 1.0** | → **1.0 / 0.88 / 1.0 / 1.0** |
| Rejected (nothing pasted) | 4.25% → **0.5%** | 4.75% → **0.75%** |
| Median latency | 609 ms → **399 ms** | ~0.7 s (unchanged) |

Both engines are deterministic (Qwen at temperature 0, Apple Intelligence greedy since #62), so these are exact.

**Beyond the corpus (live Swift, #104):**

| Set (never tuned on) | Qwen3-4B | Apple Intelligence |
|---|---|---|
| Fresh set 1 (35 cases, #45/#66) | 0.971 | 0.829 |
| Fresh set 2 (30 realistic messages written after #100, #101) | 26/30 | 25/30 |
| Robustness: 101 unusual inputs + 14 multilingual | 106/115 | 85/115 |
| Smart typography probes (12) keep the writer's punctuation | 12/12 | 11/12 |

Probing unusual inputs found these real bugs, all fixed and each checked by replay over every stored output
(0 pass→fail):
- #72: correct non-English fixes rejected by the English spell check.
- #73: German `im` / French `dont` turned into English contractions.
- #75: typo-dense corrections rejected as rewrites.
- #76, #85, #100: URLs, emails, file paths, API routes, hashtags and backslash tokens (`¯\_(ツ)_/¯`) "corrected".
- #77: invisible trailing spaces added before line breaks.
- #78: code inside ``` fences edited.
- #86 (app only): mlx-swift-lm's streaming detokenizer dropped emoji modifiers, flag halves, ZWJ, ❤️/1️⃣ and
  Thai/Hindi marks (`👍🏽` → `👍`, pasted silently).
- #88 (app only): the 3-chars-per-token output budget truncated Hindi, Tamil, Bengali, Burmese and emoji runs
  (Bengali pasted at 74%).
- #90: the writer's own edge `<text>`/`</text>` tags deleted as "leaked prompt markers".
- #93, #100 (Apple Intelligence): stripped HTML/XML markup and invented symbols (`$€1,299.99`) were pasted; both
  are now rejected (`droppedMarkup`, `introducedSymbol`).
- #94, #98, #102: abbreviations the model expanded weren't restored when adjacent (`u tmrw`) or not in the table
  (`min`, `ttyl`, `thurs`).
- #95, #97: smart apostrophes, quotes, `—` and `…` flattened to ASCII.
- #103: Swift and harness word-alignment keys disagreed on combining marks (Thai vowel signs).

The Swift chain (`cleanResponse` + `OutputGate.rejection`) matches the harness mirror on 3,218 stored and synthetic
pairs (#87, #103, `harness/swift_chain_parity.py`), so the metric scores what ships. Apple Intelligence-only
limits: it strips markup (now blocked, not pasted), rewords more, and fails (error, nothing pasted) on Hindi,
Tamil, Bengali and Burmese.

## Metric correction (#53)

`metrics.py` failed some outputs that *exactly match* one of the case's own acceptable outputs, because the
errors regex names a single variant (`q three -> Q3` while "Q three" is listed acceptable; `could have`
while "could've" is). An exact acceptable match now counts its errors as fixed. Applied to every run equally,
this moves the original baseline to Qwen .735 / AI .635 and the final #48 run to Qwen .915 / AI .78, so the
deltas are unchanged. Agreement with the LLM judges goes from 94.0% to 94.5%. The tables above use the old metric.

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

Live Swift on the fresh set (#66): Qwen **0.971** (= Python), Apple Intelligence **0.829**. Running the code from
before #64 gives byte-identical AI output on all 35 fresh cases, so #64's AI guide gain (dev +8, holdout 0) is
neutral out of sample: no gain, no harm.

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
   outputs, these went fail→pass 128 + 38 + 14 + 5 + 2 times, and **pass→fail 0 times**. Later additions
   (#76-#81): `LinkRestorer`, fenced-code restore, exact whitespace around line breaks, misplaced apostrophes and
   run-together phrases (`alot`). Also 0 pass→fail. Full order: `PIPELINE.md` §3.
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
- **Apple Intelligence was non-deterministic** (±5-10 pp per slice between runs) until greedy decoding (#62). Its
  numbers before #62 are single runs; from #62 on they're exact.
- **Remaining failures are mostly model under-correction**: pronoun case, homophones in long text, dictation
  soundalikes. Apple Intelligence still expands some slang (0.88) and rewords more than Qwen (out of sample:
  0.83 vs 0.97 on the fresh set, #66; 85 vs 106 of 115 robustness inputs, #104), so **Qwen is the recommended default**.
- The corpus is synthetic, and the judge-free metric can't see subtle meaning changes. Re-judge a sample before release.
- Before pushing the branch: commit db65f20 contains `context/real-usage.md` (personal data), so rewrite it.
