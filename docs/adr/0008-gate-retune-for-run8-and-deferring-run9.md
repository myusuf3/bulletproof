# 0008. Retune the output gate for the run8 fine-tune and defer run9

Date: 2026-10-15

## Status

Accepted

## Context

v0.0.22 shipped run8 of the Bulletproof Proofreader (Qwen3 4B fine-tune,
pinned to the Hugging Face tag `run8-final`). Unlike run5, run8 makes
grammar edits: verb forms, added function words, word order. Every
correction still passes the same checks before it is pasted: cleanup, the
always-on `OutputGate`, the spell check on words the model introduced, and,
when Verify corrections is on, `ScoredGateEngine`, which scores each edited
span with the local model and vetoes ones that look implausible.

Those checks were calibrated on run5. On the full 2,171-case eval they
rejected 23 run8 outputs, 17 of which were correct. The causes:

- The scorer vetoed inflection fixes ("eat" -> "eats", "reopen" ->
  "reopened") and fixes that only move words. The log-prob margins of good
  and bad edits overlap, so no threshold separates them.
- The spell checker flagged lowercase names and days ("wednesday",
  "tyler's") that people who type in lowercase write that way.
- A few others: a non-English dictionary picked for mostly-English text,
  "dependancy" being in the macOS dictionary, and two rewordings rejected as
  dropped content.

The scorer's real catches on run8 were almost all numbers ("300" -> "00",
"12" -> "2"), which a deterministic rule can catch with no model call.

Every rule was measured offline before any app change: rows keep their span
scores even when rejected, so `gate-retune/replay.py` reproduced the shipped
gate exactly (19,936 rows, 15 models, 0 disagreements) and replayed each
candidate rule without rerunning a model.

## Decision

**Make the gate model-agnostic where possible, and stop scoring edits it
can classify.** Shipped in v0.0.23 (PR #36):

- `OutputGate` rejects a correction that loses or changes a number
  (`changedNumber`). Numbers are compared as multisets with separators
  removed, so reformatting ("7 15 am" -> "7:15 a.m.") and new numbers
  ("q three" -> "Q3") pass. This is on for every engine.
- `SpellCheckGate` accepts a lowercase word whose capitalized form is spelled
  right.
- `SpanTriage.isInflection` accepts a span that swaps one content word for
  another form of it (shared stem of 3+ letters, known endings), without
  scoring. Apostrophes and the bare "e" ending are excluded, so
  "your"/"you're" and "breath"/"breathe" are still scored.
- `SpanTriage.isReordering` skips scoring when the output is the input's
  words in a different order.

The Python mirror (`harness/fast_eval.py`, `harness/spellcheck.swift`)
carries the same rules, and the chain parity check showed 0 differences on
4,300 pairs.

Measured on the full chain with run8: verify on, 2,030 -> 2,041 passes
(93.5% -> 94.0%) and critical failures 2 -> 1; default settings, 93.8% ->
94.0%. No new critical case, regression set unchanged.

**Rejected:**

- *Retuning `originalVetoMargin` / `totalVetoMargin`.* The overlap means any
  threshold that frees the good fixes also frees the bad ones.
- *Trusting English words in text detected as non-English.* It let a sealed
  critical failure through on two checkpoints, even when limited to
  respellings.
- *A stricter number rule that compared numbers as written.* It rejected
  correct dictation fixes.

**Defer run9.** No retraining for now. The remaining misses are spread thin
(verb patterns, word order, a late error left in long texts, dialect
normalized against the style policy), and every eval and training example is
synthetic. Real misses go into `eval/regressions/` (as `r-001` did) and
decide what run9 trains on. Revisit with ~20 real misses or a pattern the
synthetic data does not cover.

## Consequences

- No model change and no download: the rules apply to whichever proofreader
  a user has.
- The gate trusts structure over the scorer for inflections and reorderings,
  so a wrong form of the right word ("walks" -> "walked") is now pasted rather
  than vetoed. The eval found no such case; it should be watched in real
  misses.
- A correction that drops or alters a number is now always refused, even if
  the user wanted it; the user gets a message and their text is untouched.
- Gate changes must keep the Swift app and `fast_eval.py` in lockstep and be
  checked with the parity script and `severity.py` (release gate: no new
  critical case).
- Verify corrections stays off by default, so its gains reach only users who
  turn it on.
- Known remaining failures: a question turned into a statement (2 cases,
  a cheap gate check is the next app-side candidate), "dependancy", two
  rewordings rejected as dropped content, and one critical ("Pricng" ->
  "Price").
