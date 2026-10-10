"""Invariants of the post-processing chain (cleanResponse mirror). Run after changing any restorer.

  python3 harness/invariants.py

1. Echo: when the model returns the input unchanged, only ApostropheFixer (a typo fixer) may change it.
   Every restorer must be a no-op on an echo.
2. Idempotence: post_process(post_process(x)) == post_process(x) on every stored output.
3. Blocked answers stay blocked (#117): every stored guard-set or synthetic answer the OutputGate rejects
   or rewrite (introducedStructure, appendedContent, overExpansion, lowOverlap, droppedContent, droppedMarkup,
   introducedSymbol) must still be rejected after the full post-processing chain. A restorer that strips what a
   gate keys on (#116 stripped the outer braces of a JSON answer) launders an answer into the user's text.
Exit code 1 on any violation.
"""
import glob
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import fast_eval as F  # noqa: E402

corpora = list((ROOT / "baseline-2026-10-09/corpus").glob("*.jsonl")) + [
    ROOT / p for p in ("fresh-2026-10-10/slice_fresh.jsonl", "long-2026-10-10/slice_long.jsonl",
                       "multilingual-2026-10-10/slice_multilingual.jsonl", "adversarial-2026-10-10/slice_adversarial.jsonl",
                       "splits/guard.jsonl")]
inputs = [json.loads(l)["input"] for f in corpora for l in open(f) if l.startswith("{")]
inputs += ["", "   ", "ok", "🙂", "`", "``", "a`b", "```\nlet x = 1\n```", "- item\n- item two", "lol", "i",
           "U.S.A.", "e.g. this", "email me at bo@ex.com", "https://example.com/a_b?c=d", "\n\nhello\n\n",
           "tab\tseparated", "C'est", "rock 'n' roll", "‘quoted’ text", "dont_cache = 1"]

restorers = [("slang", F.restore_slang), ("contraction", F.restore_contractions),
             ("linebreak", F.restore_line_breaks), ("code", F.restore_code_spans),
             ("links", F.restore_links), ("typography", F.restore_typography),
             ("apostrophe-style", F.match_apostrophe_style), ("lowercase", F.keep_all_lowercase)]
violations = [(name, t) for t in inputs for name, fn in restorers if fn(t, t) != t]

outputs = [r for f in [ROOT / "baseline-2026-10-09/outputs.jsonl", *ROOT.glob("run-*/outputs.jsonl"),
                        *ROOT.glob("fresh-2026-10-10/*outputs.jsonl"), ROOT / "long-2026-10-10/outputs.jsonl",
                        ROOT / "multilingual-2026-10-10/outputs.jsonl"]
           if f.exists() for r in map(json.loads, open(f)) if r.get("raw")]
non_idempotent = []
for r in outputs:
    typed = not r["id"].startswith("s3")
    once = F.post_process(r["input"], r["raw"], typed)
    if F.post_process(r["input"], once, typed) != once:
        non_idempotent.append(r["id"])

BLOCKING = {"introducedStructure", "appendedContent", "overExpansion", "lowOverlap", "droppedContent",
            "droppedMarkup", "introducedSymbol"}
# Answers only: guard-set (instruction lookalike) inputs, every stored generation for them, and synthetic
# answer shapes. Corpus corrections are excluded on purpose: there a restorer clearing introducedStructure
# (e.g. LineBreakRestorer removing a break the model added) is the intended rescue, not laundering.
guard_inputs = [json.loads(l)["input"] for l in open(ROOT / "splits/guard.jsonl") if l.startswith("{")]
answer_rows = [(r["input"], r["raw"], True) for f in HERE.glob("cache/gen-*.jsonl")
               for r in map(json.loads, open(f)) if r.get("raw") and r["input"] in guard_inputs]
for g in guard_inputs:  # synthetic answers in the shapes models produce
    answer_rows += [(g, x, True) for x in (
        '{"answer": "%s"}' % g[:20], "- first point\n- second point\n- third point", "1. Step one\n2. Step two",
        "Sure! Here is what you asked for:\n\n" + g, g + "\n\nHere you go: done.", "[\"one\", \"two\"]",
        "<ul><li>one</li></ul>", "```\nprint(1)\n```")]
laundered = []
for original, text, typed in answer_rows:
    if F.output_gate(original, text) in BLOCKING and F.output_gate(original, F.post_process(original, text, typed)) is None:
        laundered.append((original[:40], text[:50]))

print(f"echo: {len(inputs)} inputs, restorer changes {len(violations)}")
for v in violations[:10]:
    print("   ", v[0], repr(v[1][:70]))
print(f"idempotence: {len(outputs)} stored outputs, violations {len(non_idempotent)} {non_idempotent[:10]}")
blocked = sum(F.output_gate(o, t) in BLOCKING for o, t, _ in answer_rows)
print(f"blocked answers stay blocked: {blocked} gate-rejected outputs, laundered by the chain {len(laundered)}")
for v in laundered[:10]:
    print("   ", v)
sys.exit(1 if violations or non_idempotent or laundered else 0)
