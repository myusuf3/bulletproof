"""Fast correction eval: the app's Qwen chain ported to mlx-lm, no xcodebuild.

    prompt (parsed from bulletproof/Engines/ProofreadPrompt.swift)
      -> Qwen3-4B, temperature 0 (LocalModelEngine)
      -> ProofreadPrompt.cleanResponse
      -> OutputGate.rejection + introducedMisspelling (NSSpellChecker via bin/spellcheck)
      -> ScoredGateEngine (EditDiff spans, MLXSpanScorer mean log-probs, ScoringThresholds)

Writes rows in the Swift runner's format (id, engine, input, raw, gated, scored,
ms, spans), so analysis/metrics.py works unchanged. Parity with the Swift
runner is checked by `--parity` against qwen-rerun-with-span-scores/.

Not ported: protectedWordRemoved (the user's vocabulary has no promoted words,
so it can't fire in this eval), the Apple Intelligence engine.

Usage (needs the GPU-enabled venv, see harness/README.md), from bulletproof-correction-improvements/:
  harness/.venv/bin/python harness/fast_eval.py --out OUT.jsonl [--split dev|holdout|all] [--ids FILE]
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent                      # bulletproof-correction-improvements/
REPO = ROOT.parent
PROMPT_SWIFT = REPO / "bulletproof/Engines/ProofreadPrompt.swift"
EDITSPAN_SWIFT = REPO / "bulletproof/Engines/EditSpan.swift"
CORPUS = ROOT / "baseline-2026-10-09/corpus"
MODEL_DIR = Path.home() / "Library/Application Support/bulletproof/Models/mlx-community/Qwen3-4B-Instruct-2507-4bit"
CACHE = HERE / "cache"
SPELLCHECK = HERE / "bin/spellcheck"
MAX_KV = 4096
MAX_SPANS_TO_SCORE = 4


# --- Swift source parsing (the Swift files stay the single source of truth) ---

def swift_multiline(src, name):
    """Value of `static let <name> = \"\"\" ... \"\"\"` with Swift's semantics:
    closing-delimiter indentation stripped, backslash-newline joins lines."""
    m = re.search(r"static let " + name + r'\s*=\s*"""\n(.*?)\n([ \t]*)"""', src, re.S)
    if not m:
        return None
    body, indent = m.group(1), m.group(2)
    lines = [l[len(indent):] if l.startswith(indent) else l.lstrip() for l in body.split("\n")]
    text = "\n".join(lines)
    text = re.sub(r"\\\n", "", text)
    return text.replace('\\"', '"').replace("\\\\", "\\")


def load_prompt(name="instructions"):
    """`instructions` (typed text: hotkey/Services) or `dictationInstructions`
    (the dictation path, AppState.makeEngine(instructions:))."""
    src = PROMPT_SWIFT.read_text()
    instructions = swift_multiline(src, name)
    if instructions is None and name == "dictationInstructions":
        return load_prompt("instructions")  # older code: one prompt for every path
    if instructions is None:
        sys.exit(f"could not parse ProofreadPrompt.{name} in {PROMPT_SWIFT}")
    # Optional few-shot chat turns: `static let examples: [(String, String)] = [("in", "out"), ...]`
    examples = []
    m = re.search(r"static let examples\s*:[^=]*=\s*\[(.*?)\n\s*\]", src, re.S)
    if m:
        lit = r'"((?:[^"\\]|\\.)*)"'
        for a, b in re.findall(r"\(\s*" + lit + r"\s*,\s*" + lit + r"\s*\)", m.group(1)):
            unesc = lambda s: s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
            examples.append((unesc(a), unesc(b)))
    return instructions, examples


def load_thresholds():
    src = EDITSPAN_SWIFT.read_text()
    get = lambda k: float(re.search(k + r"\s*=\s*(-?[\d.]+)", src).group(1))
    return {"margin": get("originalVetoMargin"), "total_margin": get("totalVetoMargin"),
            "max_count_diff": int(get("maxTokenCountDifferenceForTotals")),
            "typo_similarity": get("minimumTypoSimilarity")}


# --- ProofreadPrompt.cleanResponse ---

def swift_ws(c):
    return c.isspace()


def clean_response(response, original):
    out = response.strip()
    if out.startswith("<text>"):
        out = out[len("<text>"):]
    if out.endswith("</text>"):
        out = out[: -len("</text>")]
    lead = re.match(r"\s*", original).group(0)
    trail = re.search(r"\s*$", original).group(0) if original.strip() else ""
    return lead + out.strip() + trail


# --- OutputGate ---

def gate_words(text):
    return set(w for w in re.findall(r"[^\W_]+", text.lower()))


def word_tokens(text):
    toks = re.split(r"[^\w']|_", text)
    return [t.strip("'") for t in toks if t.strip("'")]


def output_gate(original, output):
    if not output.strip():
        return "emptyOutput"
    if "\ufffd" in output:
        return "replacementCharacter"
    orig = set(original)
    if any(unicodedata.category(c) == "Cc" and c not in "\n\t\r" and c not in orig for c in output):
        return "introducedControlCharacters"
    if len(original) >= 20 and len(output) > len(original) * 3:
        return "overExpansion"
    ow = gate_words(original)
    if len(ow) >= 8 and len(ow & gate_words(output)) * 2 < len(ow):
        return "lowOverlap"
    return None


def introduced_words(original, output):
    orig = {w.lower() for w in word_tokens(original)}
    seen, res = set(), []
    for w in word_tokens(output):
        bare = w.replace("'", "")
        k = w.lower()
        if len(bare) >= 3 and bare.isalpha() and k not in orig and k not in seen:
            seen.add(k)
            res.append(w)
    return res


def misspelled(words):
    if not words:
        return set()
    if not SPELLCHECK.exists():
        sys.exit(f"build the spell-check helper first: swiftc -O {HERE}/spellcheck.swift -o {SPELLCHECK}")
    p = subprocess.run([str(SPELLCHECK)], input="\n".join(words), capture_output=True, text=True, check=True)
    return set(p.stdout.split())


# --- EditDiff.spans ---

def edit_spans(original, corrected):
    a, b = original.split(), corrected.split()
    n, m = len(a), len(b)
    lcs = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            lcs[i][j] = lcs[i + 1][j + 1] + 1 if a[i] == b[j] else max(lcs[i + 1][j], lcs[i][j + 1])
    spans, i, j = [], 0, 0
    while i < n or j < m:
        if i < n and j < m and a[i] == b[j]:
            i += 1
            j += 1
            continue
        start, orun, rrun = j, [], []
        while i < n or j < m:
            if i < n and j < m and a[i] == b[j]:
                break
            if j == m or (i < n and lcs[i + 1][j] >= lcs[i][j + 1]):
                orun.append(a[i])
                i += 1
            else:
                rrun.append(b[j])
                j += 1
        spans.append({"anchor": " ".join(b[:start]), "original": " ".join(orun),
                      "replacement": " ".join(rrun), "suffix": " ".join(b[j:])})
    return spans


# --- Model ---

class Qwen:
    def __init__(self):
        import mlx.core as mx
        from mlx_lm import load
        from mlx_lm.sample_utils import make_sampler
        if not mx.metal.is_available():
            sys.exit("MLX has no Metal here - use the harness venv (see harness/README.md)")
        self.mx = mx
        self.model, self.tok = load(str(MODEL_DIR))
        self.sampler = make_sampler(temp=0.0)

    def generate(self, instructions, examples, text):
        from mlx_lm import generate
        msgs = [{"role": "system", "content": instructions}]
        for a, b in examples:
            msgs += [{"role": "user", "content": f"<text>\n{a}\n</text>"}, {"role": "assistant", "content": b}]
        msgs.append({"role": "user", "content": f"<text>\n{text}\n</text>"})
        prompt = self.tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)
        max_tokens = min(MAX_KV, max(16, len(text) // 3) * 2 + 128)
        return generate(self.model, self.tok, prompt, max_tokens=max_tokens, sampler=self.sampler,
                        max_kv_size=MAX_KV)

    def _score(self, anchor, middle, suffix):
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

        def total(s, e):
            idx = mx.array(full[s:e])
            return float(mx.sum(logp[s - 1: e - 1][mx.arange(e - s), idx]).item())
        mid = total(ms, me)
        nsuf = len(full) - me
        suf = total(me, len(full)) if nsuf else None
        return {"mean": mid / (me - ms), "suffix_mean": suf / nsuf if nsuf else None,
                "total": mid + (suf or 0.0), "count": me - ms + nsuf}

    def span_scores(self, span):
        """MLXSpanScorer.scores: (replacement pass, original pass), each None if unscorable."""
        if not span["replacement"].strip():
            return None, None
        r = self._score(span["anchor"], span["replacement"], span["suffix"])
        o = self._score(span["anchor"], span["original"], span["suffix"]) if span["original"].strip() else None
        return r, o


# --- SpanTriage + ScoredVerdict (EditSpan.swift) ---

def letters(s):
    return "".join(c for c in s.lower() if c.isalnum())


def similarity(a, b):
    if not a and not b:
        return 1.0
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return 2 * prev[-1] / (len(a) + len(b))


def triaged(span, bad_words, t):
    o = letters(span["original"])
    if o and o == letters(span["replacement"]):
        return True
    if not any(w in bad_words for w in word_tokens(span["original"])):
        return False
    if any(w in bad_words for w in word_tokens(span["replacement"])):
        return False
    return similarity(o, letters(span["replacement"])) >= t["typo_similarity"]


def verdict(r, o, t):
    if r is None:
        return "unscored"
    if o is not None and o["mean"] > r["mean"] + t["margin"]:
        return "originalMoreLikely"
    if o is not None and abs(r["count"] - o["count"]) <= t["max_count_diff"] and o["total"] > r["total"] + t["total_margin"]:
        return "totalOriginalMoreLikely"
    return "accepted"


# --- Driver ---

def load_cases(split, ids_file, cases_file=None):
    files = [Path(cases_file)] if cases_file else sorted(CORPUS.glob("slice*.jsonl"))
    cases = [json.loads(l) for f in files for l in f.read_text().splitlines() if l.strip()]
    if cases_file:
        return cases
    if ids_file:
        keep = set(Path(ids_file).read_text().split())
    elif split != "all":
        keep = set((ROOT / "splits" / f"{split}.txt").read_text().split())
    else:
        keep = None
    return [c for c in cases if keep is None or c["id"] in keep]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--split", default="dev", choices=["dev", "holdout", "all"])
    ap.add_argument("--ids")
    ap.add_argument("--cases", help="jsonl of {id, input} to run instead of the corpus (e.g. splits/guard.jsonl)")
    ap.add_argument("--no-cache", action="store_true")
    a = ap.parse_args()

    # The s3 slice is dictation transcripts: in the app those go through the
    # dictation path's prompt. Everything else is typed text.
    prompts = {name: load_prompt(name) for name in ("instructions", "dictationInstructions")}
    path_of = lambda c: "dictationInstructions" if c["id"].startswith("s3-") else "instructions"
    thresholds = load_thresholds()
    cases = load_cases(a.split, a.ids, a.cases)
    CACHE.mkdir(exist_ok=True)
    caches, keys = {}, {}
    for name, (instr, ex) in prompts.items():
        keys[name] = hashlib.sha256(json.dumps([instr, ex]).encode()).hexdigest()[:16]
        path = CACHE / f"gen-{keys[name]}.jsonl"
        caches[name] = {json.loads(l)["input"]: json.loads(l) for l in path.read_text().splitlines()} \
            if path.exists() and not a.no_cache else {}
    qwen = Qwen()
    t0 = time.time()
    raws = []
    for c in cases:
        name = path_of(c)
        instructions, examples = prompts[name]
        hit = caches[name].get(c["input"])
        if hit:
            raws.append((hit["raw"], hit["ms"]))
            continue
        s = time.time()
        raw = clean_response(qwen.generate(instructions, examples, c["input"]), c["input"])
        ms = (time.time() - s) * 1000
        raws.append((raw, ms))
        with (CACHE / f"gen-{keys[name]}.jsonl").open("a") as cf:
            cf.write(json.dumps({"input": c["input"], "raw": raw, "ms": ms}, ensure_ascii=False) + "\n")
    gen_s = time.time() - t0

    # OutputGate and span triage, with one batched spell-check call.
    pre = [output_gate(c["input"], raw) for c, (raw, _) in zip(cases, raws)]
    intro = [introduced_words(c["input"], raw) if p is None else [] for c, (raw, _), p in zip(cases, raws, pre)]
    all_spans = [edit_spans(c["input"], raw) for c, (raw, _) in zip(cases, raws)]
    span_words = {w for spans in all_spans if 1 <= len(spans) <= MAX_SPANS_TO_SCORE
                  for sp in spans for w in word_tokens(sp["original"]) + word_tokens(sp["replacement"])}
    bad = misspelled(sorted({w for ws in intro for w in ws} | span_words))
    rows = []
    for c, (raw, ms), p, ws, spans in zip(cases, raws, pre, intro, all_spans):
        reason = p or ("introducedMisspelling" if any(w in bad for w in ws) else None)
        gated = f"REJECTED(GATE_REJECT({reason}))" if reason else raw
        span_rows = []
        if 1 <= len(spans) <= MAX_SPANS_TO_SCORE:
            for sp in spans:
                if not sp["replacement"].strip(" "):
                    continue
                row = {"original": sp["original"], "replacement": sp["replacement"]}
                if triaged(sp, bad, thresholds):
                    row["verdict"] = "triaged"
                    span_rows.append(row)
                    continue
                r, o = qwen.span_scores(sp)
                row["verdict"] = verdict(r, o, thresholds)
                for k, d in (("replacement", r), ("original", o)):
                    if d is not None:
                        row[f"{k}Score"], row[f"{k}Total"], row[f"{k}TokenCount"] = d["mean"], d["total"], d["count"]
                if r is not None and r["suffix_mean"] is not None:
                    row["suffixScore"] = r["suffix_mean"]
                span_rows.append(row)
        vetoed = any(s["verdict"] not in ("accepted", "unscored", "triaged") for s in span_rows)
        scored = gated if reason else ("REJECTED(GATE_REJECT(implausibleEdit))" if vetoed else raw)
        rows.append({"id": c["id"], "engine": "qwen3-4b", "input": c["input"], "raw": raw, "ms": ms,
                     "gated": gated, "scored": scored, "spans": span_rows})
    Path(a.out).write_text("".join(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n" for r in rows))
    print(f"cases={len(cases)} prompts={keys} gen_s={gen_s:.1f} "
          f"total_s={time.time() - t0:.1f}", file=sys.stderr)


if __name__ == "__main__":
    main()
