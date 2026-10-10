# Verify-gate retune (2026-10-09)

Branch `fix/verify-gate-token-bias`. Replaces the per-token-mean floor with spell-check triage plus a
length-matched total-log-prob comparison. Reproduce with:

```bash
harness/.venv/bin/python harness/gate_dataset.py /tmp/gate-ds.jsonl   # scores every 1-4-span output, both engines
python3 harness/gate_replay.py /tmp/gate-ds.jsonl                      # rule comparison table
```

## Data
- 610 outputs with 1-4 changed spans (both engines' baseline outputs, all scored by Qwen as in the app), 1,218 spans,
  labelled with the baseline judges' row verdicts.
- The 6 bad edits from `ScoringDistributionProbe` (jon-john, profanity-censored, dialect-erased, effect→affect,
  brand-capitalized, priya-maya).
- Validation set not used for tuning: the 43-case bench corpus's acceptable outputs (67 good outputs).

## Why the old gate failed
The scorer's per-token mean is biased by tokenization. A misspelling splits into subword pieces that predict
each other, while the correct word is often one rare token. So `resturant` scores -6.27 and `restaurant` scores -11.96. Real-word
fixes and the gate's real targets overlap entirely on the mean: past→passed -13.01 and some times→sometimes -12.75 are good fixes,
while effect→affect -12.59 and profanity→broken -12.57 are bad ones. No floor separates them.

## New rule (`EditSpan.swift` `ScoredVerdict` + `SpanTriage`, `SpanScorer.swift`)
1. **Cosmetic spans aren't scored:** these have the same letters and digits ignoring case, so they're casing, spacing or punctuation edits.
2. **Typo fixes aren't scored:** the original has a word NSSpellChecker flags, the replacement has none, and the
   letters are close (2·LCS/(|a|+|b|) ≥ 0.6). So `Y'all ain't gonna` → `You'll never` (0.35) is still scored.
3. **originalMoreLikely** (mean margin 4.5) is kept. It catches name swaps (Priya→Maya +4.95).
4. **totalOriginalMoreLikely (new):** compares summed log-prob of span + rest of text, original versus replacement,
   **only when the two differ by ≤ 1 token**. Totals are biased toward fewer tokens just as means are
   biased toward more, so unmatched lengths fall back to rule 3. Veto when the original's total exceeds the replacement's by more than 1.0.
5. The floor (-12) and the parked suffix check are removed.

## Result

| | good outputs vetoed | bad blocked | probes caught |
|---|---|---|---|
| old gate | **28 / 480** | 7 | effect→affect, priya-maya, profanity |
| new gate | **1 / 480** | 6 | effect→affect, priya-maya, profanity |
| bench (held out), old → new | 0 / 67 → 0 / 67 | | |

- Still blocked: `300 orders` → `00 orders` (s4-022) and `ya i'll` → `Yes, I'll` (s5-032, ×2 engines).
- No longer blocked: 1 minor muddle (s1-076 `confirm` → `Confirm`, now cosmetic) and Apple Intelligence's s5-028 and s5-052 (slang or backtick muddles the old
  floor caught by accident). The verify gate isn't a style gate; style belongs to the prompt track and H3.
- The 1 remaining good veto is `accomodate` → `accommodate`. NSSpellChecker on this machine doesn't flag `accomodate`,
  and the mean margin then fires.
- Margin sensitivity: anything from 0.5 to 2.0 for the total margin gives the same good-veto count. The largest good total delta is +0.18.
- Never caught by either gate: jon-john, dialect-erased, brand-capitalized. The vocabulary and protected-word rule own those.

## Caveats
- Tuned on 15 or so informative spans plus 6 probes. The held-out bench corpus agrees, but bad real-word swaps are rare
  in this corpus. Add more probe swaps before tightening.
- `hasMisspelling` depends on the machine's NSSpellChecker dictionary (including learned words).

## Confirmed with the Swift runner (Qwen, all 400 cases, `run-2026-10-09-gate-retune/outputs.jsonl`)
- Raw outputs identical to the baseline re-run (400/400), so every difference comes from the gate.
- Verify-gate rejections went from 15 to **1**. The one left is s4-022 `300` → `00`, the real catch. The 13 good fixes and
  1 minor muddle (s1-076) that were vetoed now go through.
- User-visible: pass_rate 0.7325 → 0.7625, errors_fixed_rate 0.916 → 0.950, rejected_rate 0.040 → 0.005.
- 474 of 645 spans are triaged (not scored), which saves two forward passes each on the paste path.
