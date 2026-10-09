# Fast correction eval harness

Ports the app's Qwen chain (prompt -> Qwen3-4B temp 0 -> cleanResponse -> OutputGate
-> verify-corrections gate) to mlx-lm so prompt experiments run without xcodebuild.
The Swift files stay the source of truth: the prompt is parsed from
`bulletproof/Engines/ProofreadPrompt.swift`, thresholds from `EditSpan.swift`.

## Setup (once)

```bash
cd bulletproof-correction-improvements/harness
uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python -r requirements.txt
swiftc -O spellcheck.swift -o bin/spellcheck      # NSSpellChecker, same call as SpellCheckGate
```

The system (nix) python's MLX has no Metal and runs on CPU - always use `.venv`.

## Run (from `bulletproof-correction-improvements/`)

```bash
harness/.venv/bin/python harness/fast_eval.py --split dev --out /tmp/dev.jsonl        # 295 cases, ~6 min
harness/.venv/bin/python harness/fast_eval.py --cases splits/guard.jsonl --out /tmp/guard.jsonl   # 14 lookalikes, 10 s
python3 harness/report.py /tmp/dev.jsonl /tmp/guard.jsonl                      # METRIC lines
python3 harness/parity.py RUN.jsonl          # vs the Swift runner (only meaningful for the baseline prompt)
```

Generations are cached per prompt hash in `cache/`, so re-scoring an unchanged prompt is instant.

## Parity (2026-10-09, baseline prompt, all 400 cases)

- raw output identical to the Swift runner on 393/400 (the rest are near-ties: `LOL`/`lol`, a trailing-space bullet)
- OutputGate and verify-gate outcome identical on 393/393
- span scores |diff| median 0.016, max 0.25
- metrics within 0.5 pp of the Swift run

Confirm any winning prompt with the Swift runner (`baseline-2026-10-09/README.md`) before shipping.
