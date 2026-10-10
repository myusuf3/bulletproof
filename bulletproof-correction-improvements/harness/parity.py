"""Compare a fast_eval run with the Swift runner's output (same prompt + thresholds).

  python3 harness/parity.py FAST.jsonl [SWIFT.jsonl]   # default: qwen-rerun-with-span-scores
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fast_p = sys.argv[1]
swift_p = sys.argv[2] if len(sys.argv) > 2 else ROOT / "baseline-2026-10-09/qwen-rerun-with-span-scores/outputs.jsonl"
load = lambda p: {r["id"]: r for r in map(json.loads, Path(p).read_text().splitlines()) if r["engine"] == "qwen3-4b"}
fast, swift = load(fast_p), load(swift_p)
ids = sorted(set(fast) & set(swift))
raw_same = [i for i in ids if fast[i]["raw"] == swift[i]["raw"]]
gated_same = sum(fast[i]["gated"] == swift[i]["gated"] for i in raw_same)
scored_same = sum(fast[i]["scored"] == swift[i]["scored"] for i in raw_same)
diffs, vmis = [], []
for i in raw_same:
    for a, b in zip(fast[i]["spans"], swift[i]["spans"]):
        for k in ("replacementScore", "originalScore", "suffixScore"):
            if k in a and k in b:
                diffs.append(abs(a[k] - b[k]))
        if a["verdict"] != b["verdict"]:
            vmis.append((i, a["original"], a["replacement"], a["verdict"], b["verdict"]))
print(f"cases {len(ids)}  raw identical {len(raw_same)}  "
      f"(on identical raw) gated identical {gated_same}  scored identical {scored_same}")
if diffs:
    diffs.sort()
    print(f"span score |diff|: median {diffs[len(diffs) // 2]:.4f}  p99 {diffs[int(len(diffs) * .99)]:.4f}  max {diffs[-1]:.4f}  n={len(diffs)}")
for v in vmis:
    print("  verdict mismatch", v)
for i in ids:
    if fast[i]["raw"] != swift[i]["raw"]:
        print(f"  raw differs {i}:\n    swift {swift[i]['raw'][:120]!r}\n    fast  {fast[i]['raw'][:120]!r}")
for i in raw_same:
    if fast[i]["gated"] != swift[i]["gated"] or fast[i]["scored"] != swift[i]["scored"]:
        print(f"  gate differs {i}: swift {swift[i]['gated'][:40]!r}/{swift[i]['scored'][:40]!r} fast {fast[i]['gated'][:40]!r}/{fast[i]['scored'][:40]!r}")
