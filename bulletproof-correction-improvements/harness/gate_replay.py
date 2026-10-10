"""Replay verify-gate rules offline on gate_dataset.py output.

  python3 harness/gate_replay.py /tmp/gate-ds.jsonl
"""
import difflib
import json
import re
import sys
from collections import Counter

rows = [json.loads(l) for l in open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/gate-ds.jsonl")]
GOOD = {"GOOD", "PRESERVED", "PARTIAL"}
BAD = {"MUDDLED", "INTRODUCED_ERROR", "ANSWERED", "BAD_PROBE"}
mean = lambda xs: sum(xs) / len(xs) if xs else None
letters = lambda s: "".join(c for c in s.lower() if c.isalnum())  # Swift: isLetter || isNumber


def lcs_ratio(a, b):
    """2*LCS/(|a|+|b|) - mirrors SpanTriage.similarity in EditSpan.swift."""
    if not a and not b:
        return 1.0
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return 2 * prev[-1] / (len(a) + len(b))


def trivial(s):
    """Case / whitespace / punctuation-only edit: same letters and digits."""
    return letters(s["original"]) == letters(s["replacement"]) and letters(s["original"]) != ""


def typo_fix(s, min_sim=0.6):
    """Original has a word the spell checker flags, the replacement has none, and
    the replacement is a close edit of the original (not a different word)."""
    if not s["orig_misspelled"] or s["repl_misspelled"]:
        return False
    a, b = letters(s["original"]), letters(s["replacement"])
    return lcs_ratio(a, b) >= min_sim


def current(s, floor=-12.0, margin=4.5, suffix=-15.0):
    if s["repl"] is None:
        return None
    r = mean(s["repl"]["mid"])
    o = mean(s["orig"]["mid"]) if s["orig"] else None
    sf = mean(s["repl"]["suf"])
    if r < floor:
        return "belowFloor"
    if o is not None and o > r + margin:
        return "originalMoreLikely"
    if sf is not None and sf < suffix:
        return "suffixBroken"
    return None


def sum_delta(s):
    """Total log-prob advantage of the original over the replacement, middle + suffix
    (the whole rest of the text after the anchor). Positive = original reads better."""
    if s["repl"] is None or s["orig"] is None:
        return None
    return sum(s["orig"]["mid"] + s["orig"]["suf"]) - sum(s["repl"]["mid"] + s["repl"]["suf"])


def token_counts(s):
    return (len(s["repl"]["mid"]) + len(s["repl"]["suf"]), len(s["orig"]["mid"]) + len(s["orig"]["suf"]))


def proposed(s, total_margin=1.0, max_count_diff=1, margin=4.5):
    """The shipped rule (EditSpan.swift ScoredVerdict + SpanTriage)."""
    if trivial(s) or typo_fix(s) or s["repl"] is None or s["orig"] is None:
        return None
    if mean(s["orig"]["mid"]) > mean(s["repl"]["mid"]) + margin:
        return "originalMoreLikely"
    nr, no = token_counts(s)
    if abs(nr - no) <= max_count_diff and sum_delta(s) > total_margin:
        return "totalOriginalMoreLikely"
    return None


def rule(name, skip_trivial=False, typo=False, floor=-12.0, margin=4.5, sum_margin=None, use_mean=True):
    def veto(s):
        if skip_trivial and trivial(s):
            return None
        if typo and typo_fix(s):
            return None
        if use_mean:
            v = current(s, floor, margin)
            if v:
                return v
        if sum_margin is not None:
            d = sum_delta(s)
            if d is not None and d > sum_margin:
                return "sumOriginalMoreLikely"
        return None
    veto.__name__ = name
    return veto


def evaluate(veto, show=False):
    c = Counter()
    lines = []
    for r in rows:
        reasons = [v for v in (veto(s) for s in r["spans"]) if v]
        if not reasons:
            continue
        kind = "good" if r["label"] in GOOD else "bad" if r["label"] in BAD else "other"
        c[kind] += 1
        c[f"{kind}:{r['label']}"] += 1
        lines.append(f"   {kind:5} {r['label']:16} {r['engine'][:5]} {r['id']:20} {reasons[0]:22} {r['note'][:60]}")
    n_good = sum(r["label"] in GOOD for r in rows)
    probes = sorted(r["id"] for r in rows if r["label"] == "BAD_PROBE" and any(veto(s) for s in r["spans"]))
    print(f"{veto.__name__:44} good vetoed {c['good']:3}/{n_good}  bad blocked {c['bad']:3} "
          f"(INTRO_ERR {c['bad:INTRODUCED_ERROR']}, probes {len(probes)}/6 {[p[6:] for p in probes]})")
    if show:
        print("\n".join(sorted(lines)))


if __name__ == "__main__":
    print(Counter(r["label"] for r in rows))
    evaluate(rule("A current"), show="-v" in sys.argv)
    proposed.__name__ = "PROPOSED (shipped)"
    evaluate(proposed, show=True)
    evaluate(rule("B +skip trivial", skip_trivial=True))
    evaluate(rule("C +typo short-circuit", skip_trivial=True, typo=True), show="-v" in sys.argv)
    for f in (-12.0, -13.5, -15.0):
        evaluate(rule(f"C floor {f}", skip_trivial=True, typo=True, floor=f))
    for m in (2, 4, 6, 8, 10):
        evaluate(rule(f"D sum-only margin {m}", skip_trivial=True, typo=True, use_mean=False, sum_margin=m))
    for m in (4, 6, 8):
        evaluate(rule(f"E C + sum margin {m}", skip_trivial=True, typo=True, sum_margin=m))
