import json, sys
from collections import Counter, defaultdict
from pathlib import Path
S = Path(sys.argv[1])
rows = [json.loads(l) for l in open(S / "scored.jsonl")]
judged = {}
for f in sorted((S / "judged").glob("s*.jsonl")):
    for l in open(f):
        if l.strip():
            j = json.loads(l); judged[(j["id"], j["engine"])] = j
for r in rows:
    j = judged.get((r["id"], r["engine"]))
    if j:
        r["verdict"], r["gate_verdict"], r["note"] = j["verdict"], j.get("gate_verdict"), j.get("note", "")
    else:
        r["verdict"] = "PRESERVED" if r["raw_cat"] == "preserved" else "GOOD"
        r["gate_verdict"], r["note"] = None, ""
ENG = ["appleIntelligence", "qwen3-4b"]
NAME = {"appleIntelligence": "Apple Intelligence", "qwen3-4b": "Qwen3-4B (your current engine)"}
SL = {"s1": "spelling typos", "s2": "grammar", "s3": "dictation transcripts", "s4": "paragraphs", "s5": "casual + technical"}

def user_sees(r):
    """What actually lands in the user's text with verify-corrections on."""
    if r["scored"].startswith("REJECTED"):
        return "unchanged (gate rejected)"
    return r["verdict"]

out = []
w = out.append
w("BULLETPROOF CORRECTION EVAL - Apple Intelligence vs Qwen3-4B")
w("Run 2026-10-09. 400 hand-written cases (350 with errors, 50 clean controls), 5 slices x 80.")
w("Every case ran through the real app chain: engine -> OutputGate -> verify-corrections (scored) gate,")
w("matching your settings (verifyCorrections=on). 'raw' = model output, 'user sees' = what gets pasted.")
w("Verdicts: exact matches auto-graded; everything else judged by one agent per slice.")
w("")
w("=" * 78); w("SUMMARY (raw model verdict, 400 cases per engine)"); w("=" * 78)
cats = ["GOOD", "PRESERVED", "PARTIAL", "MISSED", "MUDDLED", "INTRODUCED_ERROR", "ANSWERED"]
w(f"{'verdict':<18}" + "".join(f"{NAME[e].split(' (')[0]:>20}" for e in ENG))
for c in cats:
    w(f"{c:<18}" + "".join(f"{sum(1 for r in rows if r['engine']==e and r['verdict']==c):>20}" for e in ENG))
w("")
w("Verify-corrections gate (scored) rejections - when this fires, NOTHING is pasted:")
for e in ENG:
    g = Counter(r["gate_verdict"] for r in rows if r["engine"] == e and r["scored"].startswith("REJECTED"))
    w(f"  {NAME[e]:<32} threw away good fix: {g['ATE_GOOD_FIX']:>3}   blocked bad output: {g['BLOCKED_BAD']:>3}")
w("")
w("Per slice - GOOD+PRESERVED / MUDDLED / PARTIAL+MISSED (out of 80):")
for s, label in SL.items():
    parts = []
    for e in ENG:
        rs = [r for r in rows if r["engine"] == e and r["slice"] == s]
        ok = sum(r["verdict"] in ("GOOD", "PRESERVED") for r in rs)
        mud = sum(r["verdict"] in ("MUDDLED", "INTRODUCED_ERROR", "ANSWERED") for r in rs)
        miss = sum(r["verdict"] in ("PARTIAL", "MISSED") for r in rs)
        parts.append(f"{NAME[e].split(' (')[0]}: {ok:>2} / {mud:>2} / {miss:>2}")
    w(f"  {s} {label:<24} " + "    ".join(parts))
w("")
w("Clean controls changed (50 per engine; should be 0):")
for e in ENG:
    n = sum(1 for r in rows if r["engine"] == e and r["kind"] == "unchanged" and r["verdict"] != "PRESERVED")
    w(f"  {NAME[e]:<32} {n}")
w("")
for e in ENG:
    ms = sorted(r["ms"] for r in rows if r["engine"] == e)
    w(f"Latency {NAME[e]:<32} p50 {ms[len(ms)//2]:.0f} ms   p95 {ms[int(len(ms)*.95)]:.0f} ms")

GROUPS = [
    ("GATE THREW AWAY A GOOD FIX (user sees no correction)", lambda r: r["gate_verdict"] == "ATE_GOOD_FIX"),
    ("MUDDLED (meaning/voice/style changed)", lambda r: r["verdict"] == "MUDDLED"),
    ("INTRODUCED_ERROR", lambda r: r["verdict"] == "INTRODUCED_ERROR"),
    ("ANSWERED (obeyed the text instead of correcting)", lambda r: r["verdict"] == "ANSWERED"),
    ("PARTIAL (some errors left in)", lambda r: r["verdict"] == "PARTIAL"),
    ("MISSED (nothing fixed)", lambda r: r["verdict"] == "MISSED"),
]
def fmt(t): return t.replace("\n", "\\n")
for e in ENG:
    w(""); w("#" * 78); w(f"# FAILURE EXAMPLES - {NAME[e]}"); w("#" * 78)
    for title, pred in GROUPS:
        rs = [r for r in rows if r["engine"] == e and pred(r)]
        if not rs: continue
        w(""); w(f"--- {title}: {len(rs)} ---")
        for r in sorted(rs, key=lambda r: r["id"]):
            w(f"[{r['id']} | {SL[r['slice']]}] {r['note']}")
            w(f"  input:     {fmt(r['input'])}")
            w(f"  model:     {fmt(r['raw'] or 'ENGINE_FAILED: ' + str(r['rawError']))}")
            if r["scored"] != r["raw"]:
                w(f"  user sees: {fmt(r['scored'])}")
            if r["errors"]:
                w(f"  expected:  {'; '.join(r['errors'])}")
            w("")
Path(sys.argv[2]).write_text("\n".join(out) + "\n")
print("\n".join(out[:45]))
