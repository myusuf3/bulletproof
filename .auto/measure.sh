#!/bin/bash
# Fast eval of the current ProofreadPrompt.instructions on Qwen3-4B (temp 0).
# Emits METRIC lines; writes .auto/runs/{dev,guard}.jsonl and last.json.
set -euo pipefail
cd "$(dirname "$0")/.."
# Opt-in checkpoint: the real Swift runner on both engines (~15 min, not the fast loop).
[ "${SWIFT_VERIFY:-0}" != "1" ] || exec ./.auto/swift_verify.sh
B=bulletproof-correction-improvements
PY=$B/harness/.venv/bin/python
mkdir -p .auto/runs
# Pre-check (<1s): the prompt parses out of the Swift file.
python3 -c "import sys; sys.path.insert(0,'$B/harness'); import fast_eval as F; i,_=F.load_prompt(); assert len(i) > 50, 'instructions too short / unparsed'"
# Keep the previous run for flips.py.
[ -f .auto/runs/dev.jsonl ] && cp .auto/runs/dev.jsonl .auto/runs/prev-dev.jsonl
$PY $B/harness/fast_eval.py --cases $B/splits/guard.jsonl --out .auto/runs/guard.jsonl 2> >(grep -v -i warn >&2)
$PY $B/harness/fast_eval.py --split dev --out .auto/runs/dev.jsonl 2> >(grep -v -i warn >&2)
python3 $B/harness/report.py .auto/runs/dev.jsonl .auto/runs/guard.jsonl --json .auto/runs/last.json
