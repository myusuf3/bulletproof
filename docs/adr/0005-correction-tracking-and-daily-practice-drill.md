# 0005. Correction tracking and the daily practice drill

Date: 2026-08-20

## Status

Accepted

## Context

bulletproof fixes typos invisibly, which means users never learn from their
own mistakes - the app is a crutch, not a teacher. We already harvest safe
word-level signals from accepted corrections (the personal vocabulary), and
the word-level diff (`EditDiff`) built for the scored gate can tell exactly
which word a correction replaced. The product question: can bulletproof turn
recurring typos into a practice habit without weakening its privacy stance
(nothing the user writes is stored in a form that reconstructs what they
wrote)?

## Decision

Track and drill **single words only**:

- `CorrectionStats` records clean one-word substitutions (typo -> fix) from
  every accepted correction, extracted via `EditDiff`. Only alphabetic
  single-word swaps count - case-only changes, punctuation-only changes, and
  multi-word rewrites are ignored, because they are not drillable spelling
  knowledge. Lowercased words, capped at 300 entries (lowest counts evicted),
  persisted in UserDefaults. Same privacy line as the vocabulary: words,
  never sentences.
- A **once-a-day drill** (`PracticeSchedule`: day-stamp gate plus a streak
  that resets when a day is skipped) runs the user's top typos as a
  Monkeytype-style typing game: the typo stream is shown, the user types the
  fix, space submits. `DrillSession` is a pure state machine; matching is
  case- and whitespace-forgiving because the drill trains spelling, not
  shift-key discipline.
- The drill lives in a **dedicated window with its own palette** (charcoal,
  dim monospaced stream, single yellow accent) rather than a settings pane -
  it is a focused game, and borrowing Monkeytype's visual language signals
  that instantly. A Practice settings pane holds the word list, streak, and
  the daily entry point; it unlocks after five recurring typos exist.

Alternatives rejected: storing sentence-level history for richer practice
(breaks the privacy line); spaced-repetition scheduling (real complexity for
unproven engagement - the daily gate is the habit-sized v1); embedding the
drill inside Settings (cramped, no focus, wrong register for a game).

## Consequences

- A new class of local data exists (the user's typo words). It is covered by
  the same words-only privacy posture and must stay that way.
- Drill quality depends on `EditDiff`'s one-word heuristics; systematic
  multi-word errors (their/they're as contraction rewrites) never become
  drill material. Acceptable: those are grammar, not spelling recall.
- The daily gate and streak are per-machine (UserDefaults), not synced.
- The seed threshold (5 recurring typos) means new users see a locked pane;
  the empty state explains why.
