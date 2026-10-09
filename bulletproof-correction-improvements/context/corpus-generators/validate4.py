import json, re, sys
from collections import Counter
lines = open(sys.argv[1]).read().splitlines()
rows = [json.loads(l) for l in lines]
assert len(rows) == 80, len(rows)
ids = [r["id"] for r in rows]
assert len(set(ids)) == 80 and ids == [f"s4-{i:03d}" for i in range(1, 81)]
kinds = Counter(r["expected"]["kind"] for r in rows)
print("kinds", kinds)
def cnt(s, t): return len(re.findall(r"(?<!\w)" + re.escape(s) + r"(?!\w)", t))
flags = 0
for r in rows:
    if r["expected"]["kind"] == "fix":
        outs = r["expected"]["acceptableOutputs"]
        assert outs and r["errors"]
        assert all(o != r["input"] for o in outs)
        assert all(o.count("\n") == r["input"].count("\n") for o in outs)
        for e in r["errors"]:
            w, rt = e.split(" -> ")
            ok = cnt(w, r["input"]) > cnt(w, outs[0]) or (w in rt and cnt(rt, outs[0]) > cnt(rt, r["input"]))
            if not ok:
                flags += 1; print("FLAG", r["id"], e)
    else:
        assert r["errors"] == [] and "acceptableOutputs" not in r["expected"]
    wc = len(r["input"].split())
    if not 40 <= wc <= 200: print("WORDS", r["id"], wc)
print("flags", flags)
print("linebreak cases", sum("\n" in r["input"] for r in rows))
print("total errors", sum(len(r["errors"]) for r in rows))
print("two outputs", sum(len(r["expected"].get("acceptableOutputs", [])) > 1 for r in rows))
print("errors/case dist", Counter(len(r["errors"]) for r in rows if r["errors"]))
