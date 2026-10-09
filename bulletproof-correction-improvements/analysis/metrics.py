"""Judge-free proxy metrics for a correction-eval run - cheap enough to run every iteration.

Usage:
  python3 analysis/metrics.py RUN_OUTPUTS.jsonl [--corpus DIR] [--layer raw|user_sees] [--json]
  python3 analysis/metrics.py NEW.jsonl --compare OLD.jsonl     # side-by-side deltas
  python3 analysis/metrics.py --calibrate                        # agreement with the baseline judges

RUN_OUTPUTS.jsonl rows are the runner's output: {id, engine, input, raw, gated, scored, ms, ...}.
"user_sees" is the `scored` column (verify gate on); "raw" is the model output.

Every metric is deterministic. Higher-is-better unless the name says otherwise (marked ↓).
None of them replaces the judge for meaning changes - see --calibrate for how far they get.
"""
import argparse
import difflib
import json
import re
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).parent
DEFAULT_CORPUS = HERE.parent / "baseline-2026-10-09" / "corpus"

CONTRACTION_EXPANSIONS = re.compile(
    r"\b(do not|does not|did not|cannot|can not|it is|it has|i am|we are|they are|you are|we will|"
    r"i will|you will|has not|have not|is not|are not|was not|were not|would not|should not|"
    r"could not|that is|there is|what is|let us|i would|we would)\b", re.I)
SLANG = {"idk", "thx", "tmrw", "bday", "ngl", "tbh", "omw", "lol", "lmao", "brb", "fyi", "ya",
         "srsly", "lowkey", "gonna", "wanna", "kinda", "gotta", "u", "ur", "pls", "plz", "rn",
         "imo", "btw", "omg", "ugh", "haha", "ok", "mins", "eng", "retro", "intro", "pr"}
CODE_SPAN = re.compile(r"`[^`\n]+`")


def norm(t):
    t = t.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    return " ".join(t.split())


def bare_words(t):
    """Lowercased words without punctuation - case and punctuation have their own metrics."""
    return re.findall(r"[a-z0-9']+", norm(t).lower())


def edit_count(a, b):
    """Word-level edit operations (replace/insert/delete runs, counted by tokens)."""
    sm = difflib.SequenceMatcher(a=bare_words(a), b=bare_words(b), autojunk=False)
    return sum(max(i2 - i1, j2 - j1) for op, i1, i2, j1, j2 in sm.get_opcodes() if op != "equal")


def error_fixed(err, inp, out):
    if "->" not in err:
        return None
    wrong, right = [p.strip() for p in err.split("->", 1)]
    if not wrong or not right:
        return None
    pat = lambda s: re.compile(r"(?<![\w'])" + re.escape(norm(s).lower()) + r"(?![\w'])")
    n_in = len(pat(wrong).findall(norm(inp).lower()))
    if n_in == 0:
        return None
    o = norm(out).lower()
    return len(pat(wrong).findall(o)) < n_in and bool(pat(right).search(o))


def is_lowercase_style(text):
    letters = [c for c in text if c.isalpha()]
    return len(letters) >= 10 and not any(c.isupper() for c in letters)


def load_corpus(d):
    corpus = {}
    for f in sorted(Path(d).glob("slice*.jsonl")):
        for line in f.read_text().splitlines():
            if line.strip():
                c = json.loads(line)
                corpus[c["id"]] = c
    return corpus


def row_flags(case, out):
    """Per-row booleans/numbers; None = metric not applicable to this case."""
    inp = case["input"]
    rejected = out is None or out.startswith("REJECTED(") or out == "ENGINE_FAILED"
    text = inp if rejected else out  # a rejection leaves the user's text as-is
    acc = case["expected"].get("acceptableOutputs", [])
    # Style checks apply only where the case's own target keeps the style
    # (dictation is lowercase by accident, and its fix is capitalization).
    target = acc[0] if acc else inp
    in_slang = {w for w in re.findall(r"[a-z]+", inp) if w in SLANG and w in re.findall(r"[a-z]+", target)}
    out_tokens = set(re.findall(r"[A-Za-z]+", text))
    flags = {
        "rejected": rejected,
        "clean_preserved": norm(text) == norm(inp) if case["expected"]["kind"] == "unchanged" else None,
        "fix_exact": (norm(text) in {norm(a) for a in acc}) if acc else None,
        "fix_echo": (norm(text) == norm(inp)) if acc else None,
        # Word edits away from the nearest acceptable output (or from the input
        # for clean controls): rewording, dropped/added words, missed fixes.
        "extra_edits": min((edit_count(a, text) for a in acc), default=edit_count(inp, text)),
        "lowercase_kept": (not any(c.isupper() for c in text if c.isalpha()))
        if is_lowercase_style(inp) and is_lowercase_style(target) else None,
        "contraction_expanded": bool(len(CONTRACTION_EXPANSIONS.findall(text))
                                     > max(len(CONTRACTION_EXPANSIONS.findall(inp)),
                                           max((len(CONTRACTION_EXPANSIONS.findall(a)) for a in acc), default=0))),
        "slang_kept": all(w in out_tokens for w in in_slang) if in_slang else None,
        "code_kept": all(s in text for s in CODE_SPAN.findall(inp)) if CODE_SPAN.search(inp) else None,
        "must_preserve_kept": all(t in text for t in case.get("mustPreserve", []))
        if case.get("mustPreserve") else None,
        "linebreaks_kept": text.count("\n") == inp.count("\n") if "\n" in inp else None,
    }
    errs = [error_fixed(e, inp, text) for e in case.get("errors", [])]
    errs = [e for e in errs if e is not None]
    flags["errors_fixed"], flags["errors_checkable"] = sum(errs), len(errs)
    return flags


def summarize(rows, corpus, layer):
    by = defaultdict(list)
    for r in rows:
        if r["id"] not in corpus:
            continue
        out = r["raw"] if layer == "raw" else r.get("scored")
        if layer == "raw" and out is None:
            out = "ENGINE_FAILED"
        by[r["engine"]].append((r, row_flags(corpus[r["id"]], out)))
    result = {}
    for eng, items in by.items():
        f = [x[1] for x in items]
        rate = lambda k: (lambda v: round(sum(v) / len(v), 4) if v else None)([x[k] for x in f if x[k] is not None])
        ms = sorted(x[0]["ms"] for x in items)
        fixed, checkable = sum(x["errors_fixed"] for x in f), sum(x["errors_checkable"] for x in f)
        result[eng] = {
            "n": len(f),
            "errors_fixed_rate": round(fixed / checkable, 4) if checkable else None,
            "fix_exact_rate": rate("fix_exact"),
            "clean_preserved_rate": rate("clean_preserved"),
            "lowercase_kept_rate": rate("lowercase_kept"),
            "slang_kept_rate": rate("slang_kept"),
            "code_kept_rate": rate("code_kept"),
            "must_preserve_kept_rate": rate("must_preserve_kept"),
            "linebreaks_kept_rate": rate("linebreaks_kept"),
            "fix_echo_rate ↓": rate("fix_echo"),
            "contraction_expanded_rate ↓": rate("contraction_expanded"),
            "over_edit_rate ↓": round(sum(x["extra_edits"] > 0 for x in f) / len(f), 4),
            "mean_extra_edits ↓": round(sum(x["extra_edits"] for x in f) / len(f), 3),
            "rejected_rate ↓": rate("rejected"),
            "p50_ms ↓": round(ms[len(ms) // 2]),
            "p95_ms ↓": round(ms[int(len(ms) * 0.95)]),
        }
    return result


def print_table(res, other=None):
    engines = sorted(res)
    keys = list(next(iter(res.values())).keys())
    print(f"{'metric':<30}" + "".join(f"{e:>22}" for e in engines))
    for k in keys:
        cells = []
        for e in engines:
            v = res[e][k]
            cell = "-" if v is None else str(v)
            if other and e in other and other[e].get(k) is not None and v is not None and k != "n":
                d = v - other[e][k]
                cell += f" ({'+' if d >= 0 else ''}{round(d, 4)})"
            cells.append(f"{cell:>22}")
        print(f"{k:<30}" + "".join(cells))


def calibrate(corpus):
    """How well the proxies flag what the judges called MUDDLED / bad, on the baseline."""
    cases = [json.loads(l) for l in (HERE / "cases.jsonl").read_text().splitlines() if l.strip()]
    bad_verdicts = {"MUDDLED", "INTRODUCED_ERROR", "ANSWERED"}
    tp = fp = fn = tn = 0
    misses = []
    for c in cases:
        f = row_flags(corpus[c["id"]], c["raw"] or "ENGINE_FAILED")
        flagged = (f["extra_edits"] > 0 or f["contraction_expanded"] or f["lowercase_kept"] is False
                   or f["slang_kept"] is False or f["code_kept"] is False
                   or f["must_preserve_kept"] is False or f["linebreaks_kept"] is False)
        bad = c["verdict"] in bad_verdicts
        tp += flagged and bad
        fp += flagged and not bad
        fn += (not flagged) and bad
        tn += (not flagged) and not bad
        if bad and not flagged:
            misses.append(f"{c['id']} {c['engine']}: {c['note']}")
    print(f"proxy 'any style flag' vs judge MUDDLED/INTRODUCED_ERROR/ANSWERED on {len(cases)} baseline rows")
    print(f"  recall {tp / (tp + fn):.2%}  precision {tp / (tp + fp):.2%}  (tp {tp} fp {fp} fn {fn} tn {tn})")
    print("  judged-bad rows no proxy caught:")
    for m in misses:
        print("   -", m)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outputs", nargs="?")
    ap.add_argument("--corpus", default=str(DEFAULT_CORPUS))
    ap.add_argument("--layer", choices=["raw", "user_sees"], default="user_sees")
    ap.add_argument("--compare")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--calibrate", action="store_true")
    a = ap.parse_args()
    corpus = load_corpus(a.corpus)
    if a.calibrate:
        calibrate(corpus)
        return
    load = lambda p: [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]
    res = summarize(load(a.outputs), corpus, a.layer)
    if a.json:
        print(json.dumps(res, indent=2, ensure_ascii=False))
        return
    print(f"layer: {a.layer}")
    print_table(res, summarize(load(a.compare), corpus, a.layer) if a.compare else None)


if __name__ == "__main__":
    main()
