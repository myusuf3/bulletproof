# Judge rubric

Used to produce `judged/`. Reuse it verbatim when judging new runs so that
verdicts stay comparable with this baseline.

Judge every row in `scored.jsonl` whose `raw_cat` is not `exact_fix` or
`preserved`, plus every row whose `scored_cat` is `rejected`. Rows that match
exactly count as GOOD (fix cases) or PRESERVED (clean controls).

Assign a `verdict` based on the raw model output:

- **GOOD**: every intended error is fixed. Any other changes are legitimate fixes or neutral (an extra correct comma, curly apostrophes, a different but correct sentence split in a run-on).
- **PARTIAL**: some intended errors fixed and some missed, with nothing made worse.
- **MISSED**: no intended error fixed (echo or near-echo).
- **MUDDLED**: meaning, voice, tone or register changed beyond fixing errors. Use this even if the errors were also fixed. Examples:
  - rewording phrases
  - dropping or adding content
  - formalizing casual text
  - capitalizing text the user wrote in lowercase on purpose (the prompt says "preserve capitalization style")
  - expanding slang or contractions ("idk", "gonna", "can't" -> "cannot")
  - losing line breaks or bullets
  - changing identifiers, paths, flags, backticked code or `mustPreserve` tokens
- **INTRODUCED_ERROR**: the output contains a new error.
- **ANSWERED**: the model replied to or obeyed the text (translated it, summarized it, wrote code) instead of correcting it.

If `scored` is `REJECTED(...)`, set `gate_verdict`:

- `ATE_GOOD_FIX` when the raw output was GOOD or an acceptable PARTIAL.
- `BLOCKED_BAD` when the raw output was MUDDLED, INTRODUCED_ERROR or ANSWERED.

Otherwise set `gate_verdict` to null.

An acceptable alternative fix that isn't in `acceptableOutputs` is GOOD. A
rephrase the user didn't ask for is MUDDLED.

Output one row per judged case:
`{"id", "engine", "verdict", "gate_verdict", "note"}`, where `note` is at most
20 words naming the specific problem.

Known judgment calls in this baseline:

- Apple Intelligence often drops the final period on otherwise-correct dictation output. These were judged GOOD.
- A capital letter after a label colon ("Ticket: Fix...") was treated as neutral.
- s3-068 is ambiguous ("were" can correctly become "We were").
