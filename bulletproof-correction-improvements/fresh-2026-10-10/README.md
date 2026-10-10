# Fresh generalization set (written 2026-10-10, after the loop converged)

35 cases written *after* tuning, before running any model on them, to check for overfitting to the
400-case corpus. Topics avoid the corpus and the prompt's few-shot examples; acceptable outputs follow the
"keep the writer's style exactly" policy, not model output. Never tune on this set.
Ids keep the slice prefixes (s1-…s5-) so per-slice metrics and the dictation routing (s3-) work.

Run: `./fresh-2026-10-10/run.sh` from `bulletproof-correction-improvements/` (current chain vs the baseline chain at 2856ecb).
