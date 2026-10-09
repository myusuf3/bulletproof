"""Deterministic first-pass scoring of eval outputs against the corpus.

Usage: python3 analyze.py <out.jsonl>... -> writes scored.jsonl + prints summary.
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

S = Path(__file__).parent
CORPUS = {}
for f in sorted((S / "corpus").glob("slice*.jsonl")):
    for line in f.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            c = json.loads(line)
            CORPUS[c["id"]] = c


def norm(t: str) -> str:
    t = t.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    return " ".join(t.split())


def loose(t: str) -> str:
    """Case/trailing-punct-insensitive, for 'fixed the words but differs in polish'."""
    return re.sub(r"[.!?]+$", "", norm(t)).lower()


def error_fixed(err: str, inp: str, out: str):
    """Per-error heuristic: wrong side gone and right side present (word-boundary, case-insensitive)."""
    if "->" not in err:
        return None
    wrong, right = [p.strip() for p in err.split("->", 1)]
    if not wrong or not right:
        return None
    o = norm(out).lower()
    w, r = norm(wrong).lower(), norm(right).lower()
    pat = lambda s: re.compile(r"(?<![\w'])" + re.escape(s) + r"(?![\w'])")
    in_count = len(pat(w).findall(norm(inp).lower()))
    if in_count == 0:
        return None
    return len(pat(w).findall(o)) < in_count and bool(pat(r).search(o))


def classify(case, text):
    """Category for one visible output (raw, gated or scored)."""
    inp = case["input"]
    if text.startswith("REJECTED(") or text == "ENGINE_FAILED":
        return "rejected" if text.startswith("REJECTED(") else "engine_failed"
    if case["expected"]["kind"] == "unchanged":
        return "preserved" if norm(text) == norm(inp) else "corrupted_clean"
    acc = [norm(a) for a in case["expected"]["acceptableOutputs"]]
    if norm(text) in acc:
        return "exact_fix"
    if norm(text) == norm(inp):
        return "no_change"
    if loose(text) in {loose(a) for a in acc}:
        return "fix_minor_diff"
    return "changed_other"


rows = []
for path in sys.argv[1:]:
    for line in Path(path).read_text().splitlines():
        if line.strip():
            rows.append(json.loads(line))

out_rows = []
summary = defaultdict(Counter)
err_stats = defaultdict(Counter)
for r in rows:
    case = CORPUS[r["id"]]
    raw = r["raw"] if r["raw"] is not None else "ENGINE_FAILED"
    errs = [error_fixed(e, case["input"], raw) for e in case.get("errors", [])]
    errs_known = [e for e in errs if e is not None]
    rec = {
        **r,
        "slice": r["id"].split("-")[0],
        "kind": case["expected"]["kind"],
        "errors": case.get("errors", []),
        "acceptable": case["expected"].get("acceptableOutputs", []),
        "mustPreserve": case.get("mustPreserve", []),
        "raw_cat": classify(case, raw),
        "gated_cat": classify(case, r["gated"]),
        "scored_cat": classify(case, r["scored"]),
        "raw_errors_fixed": sum(errs_known),
        "raw_errors_checkable": len(errs_known),
    }
    out_rows.append(rec)
    for layer in ("raw", "gated", "scored"):
        summary[(r["engine"], layer)][rec[f"{layer}_cat"]] += 1
        summary[(r["engine"], layer, rec["slice"])][rec[f"{layer}_cat"]] += 1
    err_stats[r["engine"]]["fixed"] += sum(errs_known)
    err_stats[r["engine"]]["checkable"] += len(errs_known)
    if r["scored"].startswith("REJECTED("):
        err_stats[r["engine"]]["rej:" + r["scored"]] += 1

(S / "scored.jsonl").write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in out_rows) + "\n")

for key in sorted(summary, key=lambda k: (k[0], k[1], k[2] if len(k) > 2 else "")):
    c = summary[key]
    print(" / ".join(key), dict(sorted(c.items())), "n=", sum(c.values()))
for eng, c in err_stats.items():
    print(eng, "raw per-error fixed:", c["fixed"], "/", c["checkable"],
          {k: v for k, v in c.items() if k.startswith("rej:")})
lat = defaultdict(list)
for r in rows:
    lat[r["engine"]].append(r["ms"])
for eng, ms in lat.items():
    ms.sort()
    print(eng, "p50 ms", round(ms[len(ms) // 2]), "p95 ms", round(ms[int(len(ms) * 0.95)]))
