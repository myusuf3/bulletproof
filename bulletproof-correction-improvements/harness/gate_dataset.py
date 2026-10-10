"""Build the verify-gate research dataset: every 1-4-span output from both engines
(Qwen scores all of them, as in the app), with per-span features for offline rule replay.

  harness/.venv/bin/python harness/gate_dataset.py OUT.jsonl

Row label comes from the baseline judges (analysis/cases.jsonl, raw verdict).
Adds the ScoringDistributionProbe bad edits as label BAD_PROBE.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fast_eval as F  # noqa: E402

PROBES = [
    ("probe-jon-john", "We hired Jon yesterday.", "We hired John yesterday."),
    ("probe-profanity", "This fucking build has been broken all day.", "This broken build has been broken all day."),
    ("probe-dialect", "Y'all ain't gonna believe what happened at the demo.", "You'll never believe what happened at the demo."),
    ("probe-effect-affect", "the effect of caffeine on sleep", "the affect of caffeine on sleep"),
    ("probe-brand-caps", "The app is called bulletproof, all lowercase.", "The app is called Bulletproof, all lowercase."),
    ("probe-priya-maya", "ok I'll send the deck to Priya", "ok I'll send the deck to Maya"),
]


class Scorer(F.Qwen):
    def detail(self, anchor, middle, suffix):
        """(middle_sum, middle_n, suffix_sum, suffix_n) with the Swift slicing rules; None if unscorable."""
        mx = self.mx
        enc = lambda s: self.tok.encode(s, add_special_tokens=True)
        join = lambda x, y: x if not y else y if not x else x + " " + y
        at = enc(anchor) if anchor else []
        wm = enc(join(anchor, middle))
        full = wm if not suffix else enc(join(join(anchor, middle), suffix))
        if wm[: len(at)] != at or full[: len(wm)] != wm:
            return None
        ms, me = max(len(at), 1), len(wm)
        if me <= ms:
            return None
        logits = self.model(mx.array(full)[None]).astype(mx.float32)[0]
        logp = logits - mx.logsumexp(logits, axis=-1, keepdims=True)
        tok = lambda s, e: [float(x) for x in logp[s - 1:e - 1][mx.arange(e - s), mx.array(full[s:e])].tolist()]
        mid = tok(ms, me)
        suf = tok(me, len(full)) if len(full) > me else []
        return {"mid": mid, "suf": suf}


def main():
    out = Path(sys.argv[1])
    root = HERE.parent
    cases = {(c["id"], c["engine"]): c for c in map(json.loads, (root / "analysis/cases.jsonl").read_text().splitlines())}
    qwen_fast = {r["id"]: r for r in map(json.loads, Path("/tmp/parity-all.jsonl").read_text().splitlines())}
    items = []
    for (cid, eng), c in cases.items():
        raw = c["raw"]
        if eng == "qwen3-4b":
            raw = qwen_fast[cid]["raw"]
            label = c["verdict"] if raw == c["raw"] else "UNJUDGED"
        else:
            label = c["verdict"]
        if raw is None:
            continue
        items.append((cid, eng, c["input"], raw, label, c["note"]))
    for pid, i, o in PROBES:
        items.append((pid, "probe", i, o, "BAD_PROBE", ""))

    sc = Scorer()
    words = set()
    rows = []
    for cid, eng, inp, raw, label, note in items:
        spans = F.edit_spans(inp, raw)
        if not (1 <= len(spans) <= F.MAX_SPANS_TO_SCORE):
            continue
        srows = []
        for sp in spans:
            if not sp["replacement"].strip(" "):
                continue
            r = sc.detail(sp["anchor"], sp["replacement"], sp["suffix"])
            o = sc.detail(sp["anchor"], sp["original"], sp["suffix"]) if sp["original"].strip() else None
            srows.append({**sp, "repl": r, "orig": o})
            words.update(F.word_tokens(sp["original"]) + F.word_tokens(sp["replacement"]))
        rows.append({"id": cid, "engine": eng, "input": inp, "raw": raw, "label": label, "note": note, "spans": srows})
    bad = F.misspelled(sorted(words))
    for r in rows:
        for s in r["spans"]:
            s["orig_misspelled"] = [w for w in F.word_tokens(s["original"]) if w in bad]
            s["repl_misspelled"] = [w for w in F.word_tokens(s["replacement"]) if w in bad]
    out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    print(f"rows {len(rows)} spans {sum(len(r['spans']) for r in rows)}", file=sys.stderr)


if __name__ == "__main__":
    main()
