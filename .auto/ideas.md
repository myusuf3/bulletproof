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
- **Verify gate (H2):** a spell-check short-circuit for non-word typos, skip scoring for case-only and whitespace-merge
  spans, and compare full-sentence sums instead of per-token means. Probe bad edits (jon-john, profanity, effect→affect,
  priya-maya) score −12.55 to −12.59, and good real-word fixes (past→passed, some times) score −12.29 to −13.05, so a floor
  alone can't separate them.
- **Dictation prompt (H6):** `DictationController` builds its own proofreader, so it can pass a transcript-specific prompt.
- Chat-turn few-shot (`static let examples`): needs `ChatSession` history in LocalModelEngine and a transcript in
  AppleIntelligenceEngine. The harness already supports it.
- Deterministic style guards (H3): casing transfer and slang restore in code.
- Qwen3-8B or Gemma-3-4B (H8) once the prompt has converged.
