# Findings - correction quality baseline (2026-10-09)

**Hypothesis tested:** "the app muddles what I'm saying and doesn't correct anything."

**Verdict:** half confirmed.
- **"Muddles what I'm saying": confirmed.** About 1 in 6 outputs changes voice, style or meaning (61 of 400 on Qwen, 69 on Apple Intelligence), and on casual writing it's the majority.
- **"Doesn't correct anything": not true of the models.** Qwen fixes 92% of the listed errors and Apple Intelligence 84%. But the app throws away a slice of good fixes through the verify-corrections gate. On dictation it does that silently, so the experience can match the complaint even though the models did the work.

Setup:
- 400 hand-written cases in 5 slices of 80 (spelling, grammar, dictation, paragraphs, casual/technical). Each slice has 70 cases with errors and 10 clean controls.
- Both engines ran through the app's real gate chain with the user's settings (Qwen3-4B, verify corrections on).
- Every inexact output was judged by an agent against `baseline-2026-10-09/judge-rubric.md`.
- Code was at commit `75e4a8a`.

## Headline numbers

The model's own output, before the gates, out of 400 cases per engine:

| | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD (all errors fixed, nothing else changed) | 236 | **285** |
| PRESERVED (clean control untouched) | 43 / 50 | 38 / 50 |
| PARTIAL | 31 | 8 |
| MISSED | 16 | 3 |
| **MUDDLED** | **69** | **61** |
| INTRODUCED_ERROR | 4 | 4 |
| ANSWERED (obeyed the text) | 1 | 1 |
| Listed errors fixed (regex heuristic) | 567 / 679 (84%) | 622 / 679 (92%) |
| p50 / p95 latency | 530 / 1355 ms | 680 / 1836 ms |

By slice: GOOD+PRESERVED / bad (muddled, error or answered) / PARTIAL+MISSED, out of 80:

| Slice | Apple Intelligence | Qwen3-4B |
|---|---|---|
| s1 spelling typos | 73 / 6 / 1 | 77 / 3 / 0 |
| s2 grammar | 60 / 3 / 17 | 72 / 2 / 6 |
| s3 dictation | 59 / 9 / 12 | 71 / 6 / 3 |
| s4 paragraphs | 54 / 11 / 15 | 68 / 10 / 2 |
| s5 casual + technical | **33 / 45 / 2** | **35 / 45 / 0** |

What the user sees (judge-free metrics from `analysis/metrics.py`, measured after the verify gate):

| Metric | Apple Intelligence | Qwen3-4B |
|---|---|---|
| clean text left untouched | 88% | 76% |
| intentional lowercase kept | 30% | **8%** |
| slang kept (idk, tbh, gonna…) | 36% | **18%** |
| backticked code kept | **54%** | 96% |
| line breaks kept | **67%** | 100% |
| output rejected, nothing pasted | 4.75% | 4.25% |

## Root causes, ranked by how much of the complaint they explain

### 1. The prompt teaches formalizing, so casual text gets restyled. This is the main source of "muddles".

- On casual messages Qwen muddled 36 of 37 and Apple Intelligence 27 of 37.
- The dominant theme is capitalizing intentional lowercase (Qwen 41 cases, Apple Intelligence 28). After that come expanding slang (`idk` -> `I don't know`, `tmrw` -> `tomorrow`, `omw` -> `OMG`) and restyling punctuation (Qwen adds em dashes and semicolons 16 times). See `analysis/muddle-taxonomy.md`.
- The prompt asks to "preserve tone and capitalization style", but its few-shot examples demonstrate the opposite:
  - `can u chnage the metting` -> `can you change the meeting` expands slang.
  - `Whats the whether like` -> `What's the weather like?` formalizes.
  - No example shows casual text being left casual.
- Few-shot leakage is real. Qwen replaced the clean sentence `Whether we launch on Monday or Tuesday…` with `What's the weather like?` (s3-079). The lowOverlap gate caught it.
- Apple Intelligence also gets a second instruction channel, the `@Guide` on `Correction.correctedText`. It still expands contractions (`cant` -> `cannot`, `Im` -> `I am`; 8 cases), strips or converts backticks around code (about 13 cases), flattens line breaks and bullets, and once deleted an email sign-off (s4-004).

### 2. The verify-corrections gate throws away good fixes, which is the main in-app source of "doesn't correct anything".

- Out of 36 rejections, 30 were good fixes (Apple Intelligence 16, Qwen 14). Only 6 blocked bad output.
- Examples of fixes it rejected:
  - `resturant` -> `restaurant`
  - `enviroment` -> `environment`
  - `tehcnician` -> `technician`
  - `some times` -> `sometimes`
  - `past` -> `passed` (several times)
- The cause is measured: the scorer uses the mean log-prob per token.
  - A long misspelling splits into several subword tokens that predict each other well, so its mean is high. The correct word is often one rare token.
  - For example, `resturant` scores -6.27 and `restaurant` -11.96 at sentence start, which triggers `originalMoreLikely` (margin 4.5).
  - `technician` scores -13.21, which fails the -12.0 floor.
  - See `analysis/span-scores.md` and `context/pipeline.md` §4.
- Qwen re-run with every score logged: 15 spans vetoed. 13 were good fixes, 1 was a minor capitalization muddle, and only 1 was a real catch (`300` -> `00`). 10 of the vetoes are `belowFloor`. The largest original-over-fix gap on an *accepted* good fix was 4.49, against a veto margin of 4.5, so the margin sits right on the edge of the good distribution.
- The thresholds were tuned on the 43-case bench corpus. At 400 cases they veto about 4% of all outputs, mostly good ones.
- The gate only scores outputs with 1 to 4 changed spans. Heavy muddling (5+ spans) skips scoring entirely, so it judges only the small, usually-correct edits and never the rewrites.
- On the hotkey path a rejection shows an error and pastes nothing. On dictation it **silently pastes the raw transcript** (`DictationController.swift:169`) with no notice and no telemetry. The user's real stats show 0 hotkey gate rejections; dictation isn't counted at all.

### 3. Apple Intelligence under-corrects grammar. This is the "doesn't correct" half, for that engine.

- Apple Intelligence missed or partially fixed 47 cases, against 11 for Qwen.
- Its blind spots are:
  - Agreement across an intervening phrase ("the list of items are").
  - Pronoun case ("Me and him went", "between you and I").
  - Real-word homophones (whether/weather, your/you're, there/their, right/write in dictation).
  - Tense ("are waiting since").
  - Comma splices.
- It also drops the final period on about 30 dictation outputs.
- Qwen shares the pronoun-case and comma-splice blind spots but is otherwise far stronger.

### 4. Qwen occasionally rewrites around words it can't parse. This is the meaning-changing kind of muddle.

Examples:
- `at too thirty` -> `at three thirty` (wrong time).
- `then make a decision we'll regret` -> `before making a decision—we'll regret later` (nonsense).
- `docs to` -> `docs?` (dropped "too").
- `seemed to have a grate time` -> `seemed to have had a great time` (tense change).
- `Priyankas team` -> `Priyankas' team`.
- `300 orders` -> `00 orders`. The verify gate caught this one, its one clear win.

These are rarer (about 10 cases) but worse than style muddles, because they change what the user said.

### 5. Personal vocabulary can learn typos and then block their fix.

- `PersonalVocabulary.observe` learns any spell-checker-unknown word that is "kept" in an accepted output, and protects it on the 2nd sighting.
- If the model *misses* a typo twice, the typo becomes protected, and every later correct fix of it is rejected as `protectedWordRemoved`.
- The eval reproduced this: Apple Intelligence missed `signficantly`, which was learned, and then Qwen's correct fix was rejected (s5-061).
  - The runner accelerated it by observing twice per case. That's fixed now: the vocabulary is frozen during runs.
  - The mechanism itself is real app behaviour.
- The user's real pending vocabulary contains `personible`, a misspelling, with 1 sighting.

### 6. Telemetry hides the problem and pollutes the practice drill.

- Dictation proofreads aren't counted in `proofreadStats`.
- `CorrectionStats` records every word-level diff as a user typo. So `understood` -> `understand` (×7 in real usage) is likely a model tense rewrite being drilled as a spelling mistake.

## What works well

- **Neither model answered a request-like input**, including "ignore previous instructions…". The one exception is "Translate this to Spanish:". Apple Intelligence translated it, and the gate blocked that. Qwen dropped the prefix.
- **Both models left all 10 tricky homophone controls in s2 untouched**, including correct its/it's and their/there.
- **Qwen keeps code, identifiers and line breaks almost perfectly**: 96% backtick spans kept and 100% line breaks kept.
- **The OutputGate basics rarely fire on good output.** lowOverlap fired 2 times, and it did catch the few-shot leak. introducedMisspelling fired 2 times.
- **Qwen at temperature 0 is deterministic,** so it's well suited to A/B testing prompts.

## Caveats

- One run per engine. Apple Intelligence isn't deterministic, so expect ±a few cases per slice.
- Judgments are LLM-agent calls against a written rubric, not human. Contested calls are noted in `analysis/slice-reports.md` (period dropping, capital after a colon, s3-068 ambiguity).
- The judge for each slice also wrote that slice's corpus, so it knew the intended errors. That is useful for precision, but it may make the judge stricter about "muddled" than a casual user would be.
- The corpus is synthetic. Real dictation from the Whistle STT engine may have different error profiles (mishearings, numbers). Real transcripts would be a valuable addition.
- The regex "errors fixed" heuristic undercounts some valid fixes ("was not" instead of "wasn't", "if" instead of "whether"). Treat it as a lower bound.
