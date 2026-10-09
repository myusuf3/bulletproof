# Improvement hypotheses - experiment backlog

Each entry has the evidence behind it, the change to try, the metric that should move, and the regression to watch. They're ordered by expected impact per unit of effort. Evidence ids refer to rows in `analysis/cases.jsonl`. Metrics are from `analysis/metrics.py` unless they say "judge".

## Objective for an autoresearch loop

Maximize what the user experiences as **"it fixed my mistakes and left everything else alone"**.

- **Primary:**
  - `errors_fixed_rate` must not drop. The Qwen baseline is 0.878 on user_sees and about 0.92 raw.
  - Raise `clean_preserved_rate` (0.76), `lowercase_kept_rate` (0.08) and `slang_kept_rate` (0.18).
  - Lower `over_edit_rate` (0.165) and `rejected_rate` (0.0425).
- **Hard constraints:**
  - `code_kept_rate` ≥ 0.96 and `linebreaks_kept_rate` = 1.0.
  - No ANSWERED regressions on the instruction-lookalike cases (s5-065 to s5-070).
  - p95 latency within +20% of baseline (1836 ms).
- **Confirm with the judge:** before accepting a candidate, judge its non-exact rows with `baseline-2026-10-09/judge-rubric.md` and compare MUDDLED and GOOD counts against the baseline in `FINDINGS.md`. The proxy metrics flag 96% of judged-bad rows at 58% precision (`metrics.py --calibrate`). They're good for ranking candidates but blind to subtle meaning changes (s3-058, s4-053).
- **Iteration speed:** Qwen at temperature 0 is deterministic, so a single Qwen-only run (`BULLETPROOF_EVAL_SKIP_AI=1`) is a clean A/B. Use `--compare` against `baseline-2026-10-09/outputs.jsonl`. For prompt-only iteration, the s5 slice plus the s3 clean controls is the most sensitive subset (80 + 10 cases).
- **Overfitting guard:** the corpus is the only test set. Hold out a slice (for example, tune on s1-s4 and check s5, or the reverse), or write fresh cases before declaring a win. Don't put corpus sentences into the prompt.

---

## H1. Rewrite the few-shot examples to demonstrate style preservation

**Impact: high (muddling). Effort: low (`ProofreadPrompt.swift`).**

- **Evidence:**
  - s5 casual: 36 of 37 muddled (Qwen) and 27 of 37 (Apple Intelligence).
  - The capitalization theme accounts for 41 Qwen and 28 Apple Intelligence rows.
  - The current examples expand `u` -> `you` and formalize `Whats the whether like` -> `What's the weather like?`.
  - Few-shot leak: s3-079.
- **Try:** replace the examples with ones that show the minimal fix inside a casual or technical register, for example:
  - lowercase slang with a typo -> the same lowercase slang, typo fixed (`idk if thats rihgt lol` -> `idk if that's right lol`)
  - a missing apostrophe -> the apostrophe added, not expanded (`dont` -> `don't`)
  - a sentence with `` `code` `` and a typo -> the code untouched
  - a multi-line text -> the line breaks kept

  Keep one injection example. Use topics that are unlike the corpus, so the examples don't leak (s3-079).
- **Variants to test:**
  1. Examples as real chat turns (user/assistant pairs) versus inline `->` lines.
  2. An explicit "minimal edit" instruction, e.g. "change only words that are misspelled or ungrammatical; never capitalize, expand abbreviations, or add punctuation the writer chose not to use".
  3. Instruction placement: rules before versus after the examples.

  Load the `attention-aware-prompting` skill. It favors positive framing ("keep X") over prohibitions.
- **Watch:** `lowercase_kept_rate`, `slang_kept_rate`, `clean_preserved_rate` and `over_edit_rate` should rise. **Regression risk:** dictation (s3) *needs* capitalization and punctuation added, so check that s3 `errors_fixed_rate` and judge GOOD don't fall. The prompt has to tell "lowercase on purpose" (casual chat) apart from "lowercase because it's a transcript". The app knows which path it's on, so H6 can pass that in.

## H2. Fix or disable the verify-corrections gate's per-token mean

**Impact: high (lost fixes). Effort: low to medium (`EditSpan.swift`, `SpanScorer.swift`).**

- **Evidence:** 30 of 36 rejections were good fixes. The mechanism is in `analysis/span-scores.md`: a typo's subword pieces raise its mean log-prob, and sentence-start spans have no context.
- **Try, cheapest first:**
  1. **Spell-check short-circuit.** If NSSpellChecker flags the original span word and not the replacement, accept without scoring. This is deterministic and covers the non-word typos (`resturant`, `tehcnician`, `enviroment`). It doesn't cover real-word fixes such as `past` -> `passed` or `some times` -> `sometimes`, which need 2 or 3. The gate's real targets were absurd swaps of *real* words (homophone or name swaps).
  2. **Score with sums, not means.** Compare the total log-prob of the whole sentence with the original span versus with the replacement. This removes the token-count bias.
  3. **Score with more context.** Use the full original text as the anchor, not just the corrected prefix.
  4. **Re-tune the thresholds** on the 400-case distribution. `span-scores.md` lists the accepted-span percentiles that any threshold has to keep.
  5. **Turn the gate off by default.** In this run it blocked 6 bad outputs and threw away 30 good ones.
- **Watch:** `rejected_rate` should fall from 0.0425 towards ~0.01, and the gate should keep the 6 BLOCKED_BAD rows blocked (listed in `analysis/gate-rejections.md`). In particular, s4-022 (`300 orders` -> `00 orders`) must still be blocked.
- **Tooling:** the runner now logs every span's scores, so threshold or metric changes can be replayed offline from `qwen-rerun-with-span-scores/outputs.jsonl` with no model run. That covers re-tuning thresholds; changing the metric itself (2, 3) still needs new scores.

## H3. Add deterministic style guards in code

**Impact: medium-high. Effort: medium. Push rules out of the prompt and into code.**

- **Evidence:** `code_kept_rate` 0.54 on Apple Intelligence, `linebreaks_kept_rate` 0.67 on Apple Intelligence, and `lowercase_kept_rate` 0.08 on Qwen. All three are mechanically checkable.
- **Try (post-processing in `OutputGatedEngine`, or a new layer):**
  - **Backtick spans:** if the input's `` `…` `` spans are missing from the output, restore them verbatim, or reject.
  - **Line breaks:** if the input's line count isn't preserved, reject, or re-align the output line by line.
  - **Casing transfer:** if the input has no uppercase letters at all (and this isn't dictation), lowercase the output's added capitals word by word, except `I`, which is a judgment call.
  - **Slang allowlist:** if a known abbreviation in the input (idk, tbh, omw, lol…) is missing from the output, restore it or reject.
- **Watch:** the targeted rates should go to about 1.0 with no fall in `errors_fixed_rate`. **Risk:** restoring text into an output can create inconsistent sentences. Measure with the judge.

## H4. Stop PersonalVocabulary from learning missed typos

**Impact: medium (a time bomb). Effort: low (`PersonalVocabulary.swift`).**

- **Evidence:** s5-061 (`signficantly` learned, then its fix blocked), and the user's real pending list includes `personible`.
- **Try:**
  - Don't count a word if NSSpellChecker offers a close guess for it (`guesses(forWordRange:...)` within edit distance 2), since it's probably a typo.
  - Or only learn from proofreads where the model changed nothing nearby.
  - Or require sightings across different days.
  - Add a unit test reproducing the s5-061 sequence.
- **Watch:** the new test, plus no change in eval metrics (the runner freezes the vocabulary).

## H5. Make dictation fallbacks visible, and count them

**Impact: medium (diagnosis). Effort: low (`DictationController.swift:169`, `ProofreadTelemetry`).**

- **Evidence:** dictation rejections paste the raw transcript silently and aren't counted. The user's real stats can't show the problem.
- **Try:** record dictation proofread outcomes in `proofreadStats` under a separate key (for example `dictation|…`), and optionally flash a subtle "pasted uncorrected" state in the overlay.
- **Watch:** real-usage telemetry over a week, to compare dictation rejection rates against the hotkey path.

## H6. Use a dictation-specific prompt

**Impact: medium. Effort: low.**

- **Evidence:** s3 needs aggressive punctuation and capitalization, while casual typed text needs the opposite. One prompt is pulled both ways (see the H1 risk). Apple Intelligence also leaves misheard homophones in transcripts (`right down`, `Its`, `then`).
- **Try:** a `ProofreadPrompt.dictationInstructions` variant that says the text is a speech transcript and asks for punctuation, sentence casing and soundalike fixes. `DictationController` already constructs its own proofreader, so it can pass the variant in.
- **Watch:** s3 judge GOOD and `errors_fixed_rate` should rise, with s5 unaffected.

## H7. Stop the practice drill from learning model rewrites

**Impact: low-medium (quality of the practice feature). Effort: low.**

- **Evidence:** real `correctionStats` has `understood -> understand` ×7, `til -> until` and `know -> knows`. These are probably rewrites, not typos.
- **Try:** only record a pair when the typed word is misspelled per NSSpellChecker, which excludes real-word substitutions and slang expansions.
- **Watch:** a unit test, plus inspecting real `correctionStats` after a week.

## H8. Try another local model

**Impact: unknown. Effort: low (the catalog already has it).**

- **Evidence:** Qwen3-4B is strong at fixing errors but restyles casual text. `ModelCatalog` already lists `mlx-community/gemma-3-4b-it-4bit`, which isn't installed here.
- **Try:**
  - Install Gemma (Settings > Models) and run the same 400 cases with `TEST_RUNNER_BULLETPROOF_EVAL_LOCAL_MODEL=mlx-community/gemma-3-4b-it-4bit`.
  - Separately, try a larger Qwen (8B 4-bit) if memory and latency allow.
  - Compare after H1, since a better prompt may close the gap.
- **Watch:** the full metric table, plus p95 latency.

## H9. Gate on edits beyond the errors (a muddle gate)

**Impact: medium. Effort: high. Try after H1 and H3.**

- **Evidence:** the verify gate ignores outputs with 5+ spans, which is where rewrites live. Meaning changes (s3-007 `accept` -> `accepts`, s3-013 `too thirty` -> `three thirty`) pass every gate.
- **Try:**
  - Flag spans that replace a correctly spelled, non-homophone word with a different word.
  - Or compute the edit-span count relative to the number of misspelled words and refuse outputs that edit far more than there are errors.
  - Possibly fall back to a span-wise merge that keeps only spans touching a misspelled word.
- **Watch:** `over_edit_rate` should fall, while `errors_fixed_rate` (grammar fixes edit real words) and judge GOOD on s2 hold.

## H10. Constrain or retune Apple Intelligence's guided generation

**Impact: low-medium (Apple Intelligence only). Effort: low.**

- **Evidence:** Apple Intelligence expands contractions (8), strips backticks (about 13) and flattens line breaks. Its `@Guide` says "Identical wording otherwise", which isn't sufficient.
- **Try:** a more specific `@Guide` (for example "keep contractions, abbreviations, capitalization, backticks and line breaks exactly as written"). Or split the output into two fields, a list of `edits` (typo -> fix) plus the corrected text, and apply the edits in code. That makes muddling structurally impossible.
- **Watch:** Apple Intelligence `contraction_expanded_rate`, `code_kept_rate` and `linebreaks_kept_rate`.

---

## Gaps in what was gathered

1. **No real transcripts from Whistle.** s3 is synthetic. Capturing 50 real dictation transcripts (with consent, offline) would ground H6.
2. **Apple Intelligence was run once.** Run it 3× to measure its variance before trusting deltas under about 5 cases per slice.
3. **No gate span scores for Apple Intelligence outputs.** The re-run was Qwen-only. Rerun with Apple Intelligence if H2 needs Apple Intelligence-specific tuning.
4. **The judge is an LLM.** Have a human spot-check about 30 MUDDLED/GOOD calls, especially in s5, where "capitalized casual text" drives most MUDDLED verdicts.
5. **Paragraphs longer than about 200 words and inputs near the context limit weren't tested.**
