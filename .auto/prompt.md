# Autoresearch: proofreading correction quality (prompt track)

## Objective
Make bulletproof's corrections do **"fix my mistakes and leave everything else alone"** on the
user's engine, Qwen3-4B (`mlx-community/Qwen3-4B-Instruct-2507-4bit`, temperature 0), by
changing the system prompt `ProofreadPrompt.instructions` in
`bulletproof/Engines/ProofreadPrompt.swift`.

**Product policy (decided by the user, 2026-10-09): keep the writer's style exactly.**
`idk if thats rihgt lol` → `idk if that's right lol`. Don't capitalize deliberate
lowercase, expand slang or contractions (`idk`, `tmrw`, `omw`, `cant`→`can't`, not `cannot`), add
em dashes or semicolons, reword, or change code, identifiers, line breaks or bullets.
Text that is *meant* to be capitalized (formal prose, dictation transcripts whose target has sentence
casing) should still get sentence casing and punctuation fixed.

Background (read once): `bulletproof-correction-improvements/FINDINGS.md` (root causes),
`HYPOTHESES.md` (H1 and H6 are this track), `analysis/muddle-taxonomy.md`, `context/pipeline.md` §1.

### Why the prompt is the bottleneck (measured)
Of Qwen's ~88 bad outcomes in 400 cases: about 50 are style restyling (32 of them only
capitalization or punctuation, mostly s5 casual), 14 were verify-gate vetoes of good fixes (fixed
before this loop, see analysis/gate-retune.md), about 12 change the meaning, and 11 under-correct. The current few-shot examples *teach*
formalizing (`can u` → `can you`, `Whats the whether like` → `What's the weather like?`) and leaked
verbatim once (s3-079 became "What's the weather like?").

## Metrics
- **Primary**: `pass_rate` (fraction, **higher is better**). Strict per-case pass on the dev split
  (295 cases), measured after the model and OutputGate (`gated` layer). A case passes when it isn't rejected, no
  style check broke (casing restyled on a lowercase-start target, missing capitals the target has,
  slang/code/mustPreserve/line breaks lost, contractions expanded), clean controls come back untouched,
  every listed error is fixed, and there are 0 word edits beyond the nearest acceptable output. It agrees with the
  LLM judges on 94% of baseline rows and wrongly passes only 3 bad ones (all punctuation-level). Baseline **0.7627**.
- The verify-corrections gate was retuned before the loop started (commit 1c8ac5a,
  `bulletproof-correction-improvements/analysis/gate-retune.md`). It now vetoes about 1% of dev, mostly real
  catches, so `pass_rate_user_sees` ≈ `pass_rate`. The harness mirrors the new gate.
- **Secondary**: `pass_s1..s5` (s5 casual is where the headroom is, at 0.42; s3 dictation is the regression
  risk), `errors_fixed_rate`, `clean_preserved_rate`, `lowercase_kept_rate`, `slang_kept_rate`,
  `case_restyled_rate`, `over_edit_rate`, `answered_count` (guard set plus corpus lookalikes, lower is better),
  `pass_rate_user_sees` (with the verify gate), `p50_ms`/`p95_ms`, `prompt_chars`.

## How to Run
`./.auto/measure.sh` takes about 6-8 min (all 295 dev cases plus 14 guard cases, uncached). It prints `METRIC name=value` lines
and writes `.auto/runs/{dev,guard}.jsonl` and `last.json`. Generations are cached per prompt hash, so an
unchanged prompt re-measures in seconds.

**After every run, read the flips.** This is where the ideas come from:
```
python3 bulletproof-correction-improvements/harness/flips.py .auto/runs/dev.jsonl .auto/runs/prev-dev.jsonl
python3 bulletproof-correction-improvements/harness/flips.py .auto/runs/dev.jsonl .auto/runs/dev.jsonl --all   # all remaining failures
```
Also look at `.auto/runs/guard.jsonl` raw outputs when `answered_count` moves.

## Files in Scope
- `bulletproof/Engines/ProofreadPrompt.swift`, **only the `instructions` string literal**. It's a Swift
  multi-line string (`"""`) where a trailing `\` joins lines. Keep the doc comment above it accurate.
  The harness parses this exact literal, so what you measure is what ships.

## Off Limits
- Everything under `bulletproof-correction-improvements/` (corpus, splits, metrics, harness, judge rubric):
  changing the measuring stick to make a number move is cheating. If you find a real metric bug,
  stop and write it in "What's Been Tried" instead of fixing it in-loop.
- `cleanResponse`, `userPrompt`, the engines, the gates and thresholds (`EditSpan.swift`, `SpanScorer.swift`,
  `OutputGate.swift`). The gate is a separate deliberate track.
- Adding `static let examples` (chat-turn few-shot). The harness can run it, but the Swift engines don't
  wire it in, so it wouldn't ship. `checks.sh` rejects it. Put ideas for it in `ideas.md`.
- Don't run the holdout split (`--split holdout`) in-loop. It's for checkpoints only (see below).

## Constraints (enforced by `.auto/checks.sh`)
- `errors_fixed_rate` ≥ baseline − 0.01 (0.948). Leaving typos in to keep style is not a win.
- `code_kept_rate` ≥ 0.96, `linebreaks_kept_rate` = 1.0.
- `answered_count` ≤ baseline (8). See the finding below.
- No slice's pass rate may drop more than 5 pp below baseline (this stops trading dictation for casual text).
- p95 latency ≤ 1.3× baseline. Latency is noisy (±40% run to run), so this check is deliberately loose.
- `instructions` ≤ 3000 chars. `LocalModelEngine.maxInputCharacters` subtracts the prompt from the
  4096-token KV budget, and a unit test requires the input cap to stay above 2000 chars.
- **Overfitting guard:** no 6-word run from any corpus or guard input may appear in the prompt. Write
  examples on topics unlike the corpus (it covers meetings, deploys, PRs, landlords, travel, dinner, etc.).

## Noise and decision rule
- Qwen at temperature 0 is deterministic for a given prompt. But any prompt change perturbs near-tie tokens:
  between the Swift and Python runtimes, about 2% of cases flip on numeric noise alone. **Treat |Δ pass_rate| ≤ 0.01
  (≤ 3 cases) as noise.** Keep only if the primary improves by more than that and the flips make sense (gains are the
  targeted failure class, losses aren't a new failure class). For a small but real-looking gain, confirm with a
  semantically equivalent rewording of the same idea before building on it.
- Simpler and shorter prompts win ties. Prompt length costs latency on every call.

## Known tensions and pitfalls
- **Dictation versus casual.** The same prompt proofreads dictation transcripts (s3: all lowercase, no
  punctuation, *needs* casing and punctuation) and casual typing (s5: lowercase on purpose, needs neither).
  The prompt doesn't know which path it's on. Distinguishing cues: transcripts have no punctuation at all and run-on
  sentences, while casual typing has its own punctuation (`!!`, `?`, `,`, emoji, `lol`). A proper per-path prompt is
  H6, outside this loop. Watch `pass_s3`.
- **Few-shot leakage.** Small models copy example outputs verbatim (s3-079). Keep examples short and
  generic, and keep the `<text>…</text> -> …` inline format.
- **Instruction lookalikes.** Qwen *answers* 8 of 14 fresh lookalikes in the guard set (it wrote JSON,
  listed puppy names, translated to French, said "YES"). The corpus's 6 lookalikes all pass, so FINDINGS.md
  under-reports this. Two of the 8 get pasted over the user's text (g-10, g-13). Improving it is a bonus,
  and regressing it is blocked.
- **Apple Intelligence shares this prompt** (`AppleIntelligenceEngine` uses the same `instructions`). It
  can't run in this harness. At checkpoints, note anything that might hurt it, such as relying on chat-format quirks.
- Capitalization after a label colon (`Note: Call…`) and a trailing period on casual text are judgment calls.
  Don't over-fit to them.

## Checkpoints (every ~5 kept experiments, and before stopping)
1. Holdout: `harness/.venv/bin/python harness/fast_eval.py --split holdout --out /tmp/holdout.jsonl` (run from
   `bulletproof-correction-improvements/`), then `python3 analysis/metrics.py /tmp/holdout.jsonl --layer gated --ids splits/holdout.txt`.
   Baseline holdout pass_rate (gated) is in "What's Been Tried". If dev improves but holdout doesn't, you're overfitting.
2. Record the result below. Don't tune on the holdout failures.

## What's Been Tried
- **Baseline** (commit 75e4a8a prompt): dev pass_rate 0.7627 (s1 .949, s2 .915, s3 .831, s4 .695,
  s5 .424), errors_fixed .958, lowercase_kept .06, slang_kept .29, case_restyled .125, answered 8/14 guard.
  Holdout (gated, 105 cases): pass_rate 0.781 (s1 1.0, s2 .857, s3 .905, s4 .714, s5 .429), errors_fixed .939.
- Remaining dev failures at baseline: about 38 in s5 (casing restyle, slang uppercased or expanded, em dashes), about 10 in s4
  (rewording one or two words, `I and Lena`), about 8 in s3 (missed fixes or extra edits), and a few clean controls changed.
