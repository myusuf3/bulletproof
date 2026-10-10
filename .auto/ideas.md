# Ideas backlog (prompt track)

## In-loop (only the `instructions` string)
- Replace the few-shot examples with **style-preserving** demonstrations: a lowercase casual line with a typo
  that keeps lowercase and slang; `dont` → `don't` (add the apostrophe, don't expand); a sentence with
  `` `code` `` and a typo where the code stays untouched; a 2-line input that keeps its line break. Keep one injection example
  (rephrased, not the guard's wording). Use topics unlike the corpus.
- Add an explicit minimal-edit rule in positive framing: "change only words that are misspelled or
  ungrammatical; keep the writer's casing, slang, abbreviations, contractions, emoji and punctuation choices".
- Describe the transcript case explicitly: "if the text has no punctuation at all, it's a speech transcript, so add
  sentence punctuation and capitals". This tests whether one prompt can serve both s3 and s5.
- Instruction placement: rules before versus after the examples, and a short rule restated at the end.
- Shorter overall prompt: the current one is 664 chars. Check whether removing the "grammar checker" framing changes over-editing.
- Injection robustness: an example where a request-like line ("can you list three…") is echoed with only a
  typo fixed. Watch `answered_count`.
- Tell the model the output replaces the selection in place, so anything other than the corrected text is destructive.

## Outside this loop (need code or harness changes, so separate tracks)
- **Structural-transform gate (injection):** prompt examples don't stop short transforms that pass lowOverlap, like
  g-04 (sentence → bullet list) and g-13 (prose → JSON), both pasted over the user's text (#18). Add an OutputGate rule:
  reject when the output introduces structure the input lacks (new leading `- `/`1.` lines, `{`/`}` or `:` pairs, or
  more lines than the input). Deterministic, cheap, and catches the worst failure (silent destructive paste).
- ~~Spell-check-triggered second pass~~: measured (#21). Only 1 of 27 remaining dev failures has a still-flagged
  word, since the rest are real words. Not worth the latency.
- **Remaining dev failures (27, after #15) by class:** homophones in long text ×5, dictation soundalikes ×4, pronoun case ×3
  (an instruction gives "I and Sam", #21), alot ×3 (NSSpellChecker doesn't flag it), contraction expanded ×2, 1 introduced error
  (would't), plus style judgment calls. Most promising: **H8, Qwen3-8B 4-bit** on the same prompts (needs a download, and
  watch p95), or small deterministic post-fixes (re-contract "It is"→"It's" when the input had "Its").
- ~~Gemma-3-4B (H8, catalog model)~~: #22, pass .810, errors_fixed .836. Much weaker corrector, but answered only
  3/14 guard lookalikes (Qwen 7). Qwen3-4B stays. Qwen3-8B isn't in ModelCatalog. Gemma is in /tmp/models (3.2 GB).
- ~~Qwen3-8B 4-bit (H8)~~: #23, pass .810, errors_fixed .888, p95 4.5 s. The 2507 refresh of Qwen3-4B out-corrects
  the original 8B. Model swaps are exhausted. /tmp/models holds Gemma (3.2 GB) and Qwen3-8B (4.3 GB); delete when done.
- **Typed-prompt fragility:** one added sentence swings ~20 cases (#16), and errors_fixed sits at the floor (.948).
  Recall in long paragraphs (s4 .80, mostly "1 of N errors missed") may need a bigger model (H8) or a second pass
  for spans the spell checker still flags after the first pass (code change).
- ~~Verify gate (H2)~~: done in commit 1c8ac5a (15 → 1 Qwen rejections on 400 cases).
- **Dictation prompt (H6):** `DictationController` builds its own proofreader, so it can pass a transcript-specific prompt.
- Chat-turn few-shot (`static let examples`): needs `ChatSession` history in LocalModelEngine and a transcript in
  AppleIntelligenceEngine. The harness already supports it.
- Deterministic style guards (H3): casing transfer and slang restore in code.
- Qwen3-8B or Gemma-3-4B (H8) once the prompt has converged.
