# Verify-gate span scores (Qwen3-4B re-run)

Re-run of all 400 cases on Qwen3-4B only, logging every span the verify gate scores
(mean log-prob per token of the replacement and of the original in context; thresholds:
floor -12.0, originalMoreLikely margin 4.5, suffix floor -15.0 - see `context/pipeline.md`).
Vocabulary frozen for this run, so `protectedWordRemoved` artifacts from the baseline are gone.

- Determinism: 400/400 raw outputs identical to the baseline Qwen run (temperature 0).
- Spans scored: 645; verdicts: {'accepted': 581, 'unscored': 49, 'belowFloor': 10, 'originalMoreLikely': 5}
- Outputs the judges called GOOD/PRESERVED (identical raw) that the gate vetoes: 13 of 323

## Every vetoed span

| id | judged | verdict | original -> replacement | orig score | repl score | suffix |
|---|---|---|---|---|---|---|
| s1-006 | GOOD | belowFloor | `accomodate` -> `accommodate` | -11.12 | -15.25 | -3.58 |
| s1-011 | GOOD | belowFloor | `some times` -> `sometimes` | -5.45 | -12.75 | -3.51 |
| s1-021 | GOOD | originalMoreLikely | `resturant` -> `restaurant` | -6.27 | -11.96 | -2.92 |
| s1-050 | GOOD | originalMoreLikely | `begining` -> `beginning` | -5.92 | -11.86 | -2.04 |
| s1-056 | GOOD | belowFloor | `presentaion` -> `presentation` | -7.41 | -12.33 | -2.71 |
| s1-059 | GOOD | originalMoreLikely | `enviroment` -> `environment` | -4.14 | -10.31 | -2.30 |
| s1-063 | GOOD | belowFloor | `tehcnician` -> `technician` | -6.44 | -13.21 | -2.84 |
| s1-076 | MUDDLED | belowFloor | `confirm` -> `Confirm` | -13.70 | -12.47 | -2.57 |
| s2-047 | GOOD | belowFloor | `past` -> `passed` | -10.88 | -13.01 | -2.27 |
| s3-039 | GOOD | belowFloor | `we past` -> `We passed` | -11.22 | -13.05 | -2.99 |
| s3-066 | GOOD | belowFloor | `i past` -> `I passed` | -11.31 | -12.29 | -2.40 |
| s4-022 | INTRODUCED_ERROR | originalMoreLikely | `300` -> `00` | -0.49 | -6.64 | -3.24 |
| s4-026 | GOOD | belowFloor | `unit` -> `Unit` | -11.70 | -12.67 | -2.15 |
| s5-033 | GOOD | originalMoreLikely | `the fucntion retuns` -> `The function returns` | -4.97 | -9.69 | -2.66 |
| s5-070 | GOOD | belowFloor | `explian` -> `explain` | -11.52 | -12.23 | -0.97 |

## Score distribution of accepted spans on GOOD outputs

Where legitimate corrections land - any new threshold or metric has to keep these.

replacementScore n=419: min -11.98, p5 -10.62, p25 -5.99, median -3.40, p75 -1.50, max -0.00
originalScore - replacementScore n=401: p50 -3.19, p90 1.33, p95 2.31, max 4.49  (veto fires above 4.5)
