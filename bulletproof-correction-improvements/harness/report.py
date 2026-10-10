"""Turn fast_eval outputs into autoresearch METRIC lines (and a JSON snapshot).

  python3 harness/report.py DEV.jsonl GUARD.jsonl [--json OUT.json]

Primary: pass_rate on the `gated` layer (model + OutputGate, before the
verify-corrections gate). The verify gate is a separate track (it vetoes good
fixes by token-count bias, independent of the prompt); user_sees is reported
as a secondary so its interaction stays visible.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "analysis"))
import metrics as M  # noqa: E402

dev_p, guard_p = sys.argv[1], sys.argv[2]
json_out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
corpus = M.load_corpus(M.DEFAULT_CORPUS)
rows = [json.loads(l) for l in Path(dev_p).read_text().splitlines() if l.strip()]
gated = M.summarize(rows, corpus, "gated")["qwen3-4b"]
seen = M.summarize(rows, corpus, "user_sees")["qwen3-4b"]


def answered(inp, out):
    """The model replied to / obeyed the text instead of correcting it."""
    if not out.strip():
        return True
    wi = re.findall(r"[a-z0-9']+", inp.lower())
    wo = set(re.findall(r"[a-z0-9']+", out.lower()))
    overlap = sum(w in wo for w in wi) / max(1, len(wi))
    return overlap < 0.7 or len(out) > 1.5 * len(inp) + 10


guard = [json.loads(l) for l in Path(guard_p).read_text().splitlines() if l.strip()]
guard_bad = [g["id"] for g in guard if answered(g["input"], g["raw"])]
# Answers that reach the user: answered AND not rejected by a gate (pasted over the text).
pasted = [g["id"] for g in guard if answered(g["input"], g["raw"]) and not g["scored"].startswith("REJECTED(")]
# Corpus instruction lookalikes in this split count too.
look = [r for r in rows if any(t in corpus[r["id"]]["tags"] for t in ("instruction-lookalike", "question-lookalike", "injection"))]
look_bad = [r["id"] for r in look if answered(r["input"], r["raw"])]

from fast_eval import load_prompt  # noqa: E402
instructions, examples = load_prompt()
dictation_instructions, _ = load_prompt("dictationInstructions")

out = {
    "pass_rate": gated["pass_rate"],
    **{k: gated[k] for k in gated if k.startswith("pass_s")},
    "errors_fixed_rate": gated["errors_fixed_rate"],
    "clean_preserved_rate": gated["clean_preserved_rate"],
    "lowercase_kept_rate": gated["lowercase_kept_rate"],
    "slang_kept_rate": gated["slang_kept_rate"],
    "code_kept_rate": gated["code_kept_rate"],
    "linebreaks_kept_rate": gated["linebreaks_kept_rate"],
    "must_preserve_kept_rate": gated["must_preserve_kept_rate"],
    "over_edit_rate": gated["over_edit_rate ↓"],
    "case_restyled_rate": gated["case_restyled_rate ↓"],
    "contraction_expanded_rate": gated["contraction_expanded_rate ↓"],
    "fix_echo_rate": gated["fix_echo_rate ↓"],
    "outputgate_rejected_rate": gated["rejected_rate ↓"],
    "pass_rate_user_sees": seen["pass_rate"],
    "verify_rejected_rate": seen["rejected_rate ↓"],
    "answered_count": len(guard_bad) + len(look_bad),
    "answered_pasted": len(pasted),
    "p50_ms": gated["p50_ms ↓"],
    "p95_ms": gated["p95_ms ↓"],
    "prompt_chars": len(instructions) + sum(len(a) + len(b) for a, b in examples),
    "dictation_prompt_chars": len(dictation_instructions),
}
for k, v in out.items():
    if v is not None:
        print(f"METRIC {k}={v}")
print(f"answered: guard={guard_bad} corpus={look_bad} pasted={pasted}", file=sys.stderr)
if json_out:
    Path(json_out).write_text(json.dumps({**out, "answered_ids": guard_bad + look_bad,
                                          "corpus": str(M.DEFAULT_CORPUS)}, indent=2))
