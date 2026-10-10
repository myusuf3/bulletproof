#!/bin/bash
# Hard constraints. Prints only violations. Runs after a passing measure.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
B=bulletproof-correction-improvements
xcrun swiftc -parse bulletproof/Engines/ProofreadPrompt.swift 2>&1 | head -20
python3 - <<'PY'
import json, re, sys
from pathlib import Path
sys.path.insert(0, "bulletproof-correction-improvements/harness")
import fast_eval as F
last = json.loads(Path(".auto/runs/last.json").read_text())
base = json.loads(Path(".auto/baseline.json").read_text())
bad = []
def need(ok, msg):
    if not ok: bad.append(msg)
need(last["errors_fixed_rate"] >= base["errors_fixed_rate"] - 0.01, f"errors_fixed_rate {last['errors_fixed_rate']} < baseline-0.01")
need(last.get("code_kept_rate", 1) >= 0.96, f"code_kept_rate {last.get('code_kept_rate')} < 0.96")
need(last.get("linebreaks_kept_rate", 1) == 1.0, f"linebreaks_kept_rate {last.get('linebreaks_kept_rate')} != 1.0")
need(last["answered_count"] <= base["answered_count"], f"answered_count {last['answered_count']} > baseline {base['answered_count']} ({last.get('answered_ids')})")
for s in ("s1", "s2", "s3", "s4", "s5"):
    need(last[f"pass_{s}"] >= base[f"pass_{s}"] - 0.05, f"pass_{s} {last[f'pass_{s}']} dropped >5pp vs baseline {base[f'pass_{s}']}")
need(last["p95_ms"] <= base["p95_ms"] * 1.3, f"p95_ms {last['p95_ms']} > 1.3x baseline")
instr, ex = F.load_prompt()
dinstr, _ = F.load_prompt("dictationInstructions")
for name, text in (("instructions", instr), ("dictationInstructions", dinstr)):
    need(len(text) <= 3000, f"{name} {len(text)} chars > 3000 (input cap / context budget)")
need(not ex, "static let examples (chat-turn few-shot) isn't wired into the Swift engines - keep examples inline in instructions")
# Overfitting guard: no 6-word run from any eval input may appear in the prompt.
words = lambda t: re.findall(r"[a-z0-9']+", t.lower())
pw = " ".join(words(instr + " " + dinstr))
srcs = [json.loads(l)["input"] for f in list(F.CORPUS.glob("slice*.jsonl")) + [Path("bulletproof-correction-improvements/splits/guard.jsonl")] for l in f.read_text().splitlines() if l.strip()]
for s in srcs:
    w = words(s)
    for i in range(len(w) - 5):
        g = " ".join(w[i:i + 6])
        if f" {g} " in f" {pw} ":
            bad.append(f"prompt contains eval text: '{g}'")
            break
for b in bad: print("CHECK FAILED:", b)
sys.exit(1 if bad else 0)
PY
