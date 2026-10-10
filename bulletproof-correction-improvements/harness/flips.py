"""Which cases flipped pass<->fail between two runs, and why - read this after every run.

  python3 harness/flips.py NEW.jsonl OLD.jsonl [--layer gated|user_sees|raw] [--all]

--all also lists cases that fail in both (with the failing checks), grouped by slice.
"""
import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "analysis"))
import metrics as M  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("new")
ap.add_argument("old")
ap.add_argument("--layer", default="gated", choices=["raw", "gated", "user_sees"])
ap.add_argument("--all", action="store_true")
a = ap.parse_args()
corpus = M.load_corpus(M.DEFAULT_CORPUS)
col = {"raw": "raw", "gated": "gated", "user_sees": "scored"}[a.layer]
load = lambda p: {r["id"]: r for r in map(json.loads, Path(p).read_text().splitlines()) if r["id"] in corpus}
new, old = load(a.new), load(a.old)


def why(case, f):
    r = []
    if f["rejected"]:
        r.append("rejected")
    for k in ("contraction_expanded", "missed_caps"):
        if f[k]:
            r.append(k)
    if f["case_edits"]:
        r.append(f"case_restyled×{f['case_edits']}")
    for k in ("lowercase_kept", "slang_kept", "code_kept", "must_preserve_kept", "linebreaks_kept"):
        if f[k] is False:
            r.append(k.replace("_kept", "_lost"))
    if case["expected"]["kind"] == "unchanged":
        if not f["clean_preserved"]:
            r.append("clean_changed")
    else:
        if f["errors_fixed"] < f["errors_checkable"]:
            r.append(f"unfixed {f['errors_checkable'] - f['errors_fixed']}/{f['errors_checkable']}")
        if f["extra_edits"]:
            r.append(f"extra_edits×{f['extra_edits']}")
    return ", ".join(r)


gained, lost, both = [], [], []
for i in sorted(set(new) & set(old)):
    case = corpus[i]
    fn, fo = M.row_flags(case, new[i][col]), M.row_flags(case, old[i][col])
    if fn["pass"] and not fo["pass"]:
        gained.append((i, case, fo, old[i][col], new[i][col]))
    elif fo["pass"] and not fn["pass"]:
        lost.append((i, case, fn, old[i][col], new[i][col]))
    elif not fn["pass"]:
        both.append((i, case, fn, new[i][col]))

print(f"gained {len(gained)}  lost {len(lost)}  net {len(gained) - len(lost):+d}  (of {len(set(new) & set(old))}, layer {a.layer})")
for title, items in (("LOST (passed before, fails now)", lost), ("GAINED", gained)):
    if items:
        print(f"\n== {title}")
    for i, case, f, o, n in items:
        print(f"{i} [{why(case, f)}]\n   in : {case['input'][:160]!r}\n   old: {o[:160]!r}\n   new: {n[:160]!r}")
if a.all:
    print("\n== STILL FAILING")
    for i, case, f, n in both:
        print(f"{i} [{why(case, f)}]\n   in : {case['input'][:160]!r}\n   out: {n[:160]!r}")
