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
import os
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
# BULLETPROOF_EVAL_CORPUS swaps the evaluated corpus (e.g. fresh-2026-10-10); with it set, the
# dev/holdout split is ignored and every case in that corpus runs. Default: the 400-case corpus.
CORPUS = Path(os.environ["BULLETPROOF_EVAL_CORPUS"]) if os.environ.get("BULLETPROOF_EVAL_CORPUS") \
    else ROOT / "baseline-2026-10-09/corpus"
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


def keep_all_lowercase(original, corrected):
    """ProofreadPrompt.keepAllLowercase (typed path only)."""
    if any(c.isupper() for c in original) or not any(c.isalpha() for c in original):
        return corrected
    return corrected.lower()


_APOS_FORMS = ["don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "haven't",
               "hasn't", "hadn't", "wouldn't", "shouldn't", "couldn't", "mustn't", "needn't",
               "I'm", "I've", "you're", "you've", "you'll", "they're", "they've", "they'll",
               "that's", "there's", "what's", "who's", "we've", "would've", "should've", "could've",
               "a lot", "a bit", "a little", "at least", "in fact", "as well", "each other",
               "no one", "in case", "of course", "in spite"]
_APOS = {"".join(c for c in f.lower() if c.isalpha()): f for f in _APOS_FORMS}


_MISPLACED = {}
for _f in ["don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't",
           "wouldn't", "shouldn't", "couldn't", "mustn't", "needn't", "can't", "won't", "shan't", "ain't"]:
    _MISPLACED[_f[:-3] + "'nt"] = _f
    if len(_f) - 3 > 2:
        _MISPLACED[_f[:-3] + "'t"] = _f


def fix_apostrophes(text):
    """ApostropheFixer.fix, applied only when the text isn't confidently non-English (cleanResponse)."""
    if (any(w.lower() in _APOS for w in re.findall(r"[A-Za-z]+", text))
            or any(w.lower().replace("\u2019", "'") in _MISPLACED for w in re.findall(r"[A-Za-z'\u2019]+", text))) \
            and text_dictionaries([text])[0]:
        return text
    code = code_spans(text)
    out, i, n = [], 0, len(text)
    while i < n:
        if not text[i].isalpha():
            out.append(text[i])
            i += 1
            continue
        st = i
        while i < n and (text[i].isalpha() or text[i] in "'\u2019"):
            i += 1
        word = text[st:i]
        after = i < n and (text[i].isdigit() or text[i] == "_")
        before = st > 0 and (text[st - 1].isdigit() or text[st - 1] in "_@#")
        inside = any(a <= st < b for a, b in code) or any(m.start() <= st < m.end() for m in _LINK.finditer(text))
        fixed = _APOS.get(word.lower())
        curly = False
        if not (fixed and "'" not in word and "\u2019" not in word):
            fixed = _MISPLACED.get(word.lower().replace("\u2019", "'"))
            curly = "\u2019" in word
        if fixed and not after and not before and not inside:
            if len(word) > 1 and all((not c.isalpha()) or c.isupper() for c in word):
                fixed = fixed.upper()
            elif word[0].isupper():
                fixed = fixed[0].upper() + fixed[1:]
            out.append(fixed.replace("'", "\u2019") if curly else fixed)
        else:
            out.append(word)
    return "".join(out)


_SLANG = {
    "idk": ["i don't know", "i do not know", "i dont know"], "tbh": ["to be honest"],
    "ngl": ["not gonna lie", "not going to lie"], "imo": ["in my opinion"], "imho": ["in my humble opinion"],
    "btw": ["by the way"], "fyi": ["for your information"], "brb": ["be right back"], "omw": ["on my way"],
    "tmrw": ["tomorrow"], "tmr": ["tomorrow"], "thx": ["thanks", "thank you"], "thnx": ["thanks", "thank you"],
    "ty": ["thank you", "thanks"], "pls": ["please"], "plz": ["please"], "bc": ["because"], "rn": ["right now"],
    "u": ["you"], "ur": ["your", "you're", "you are"], "lmk": ["let me know"], "nvm": ["never mind"],
    "bday": ["birthday"], "msg": ["message"], "ok": ["okay"], "srsly": ["seriously"],
    "gonna": ["going to"], "wanna": ["want to"], "gotta": ["got to", "have to"], "kinda": ["kind of"],
    "sorta": ["sort of"], "lowkey": ["low-key", "low key"], "mins": ["minutes"], "secs": ["seconds"],
    "min": ["minute", "minutes"], "hr": ["hour", "hours"], "hrs": ["hours"], "approx": ["approximately"], "info": ["information"], "pic": ["picture", "photo"], "pics": ["pictures", "photos"], "convo": ["conversation"], "abt": ["about"], "cuz": ["because"], "ppl": ["people"], "prob": ["probably"], "tho": ["though", "although"], "thru": ["through"], "wk": ["week"], "wks": ["weeks"], "yr": ["year"], "yrs": ["years"], "esp": ["especially"], "appt": ["appointment"], "mtg": ["meeting"], "sec": ["second", "seconds"], "np": ["no problem"], "jk": ["just kidding"], "omg": ["oh my god", "oh my gosh"], "ttyl": ["talk to you later"], "hbu": ["how about you"], "wyd": ["what are you doing"], "rly": ["really"], "sry": ["sorry"], "msgs": ["messages"], "kk": ["okay"], "mon": ["monday"], "tue": ["tuesday"], "tues": ["tuesday"], "wed": ["wednesday"], "thu": ["thursday"], "thur": ["thursday"], "thurs": ["thursday"], "fri": ["friday"], "sat": ["saturday"], "sun": ["sunday"], "jan": ["january"], "feb": ["february"], "aug": ["august"], "sep": ["september"], "sept": ["september"], "oct": ["october"], "nov": ["november"], "dec": ["december"],
}


def _slang_piece(typed_word, piece_words):
    """The typed abbreviation's restored form for this output piece, or None (SlangRestorer.restoredPiece)."""
    a0, b0 = 0, len(typed_word)
    while a0 < b0 and not typed_word[a0].isalpha():
        a0 += 1
    while b0 > a0 and not typed_word[b0 - 1].isalpha():
        b0 -= 1
    typed_core = typed_word[a0:b0]
    core = typed_core.lower()
    if not core or not core.isalpha() or core not in _SLANG or not 1 <= len(piece_words) <= 4:
        return None
    phrase = " ".join(piece_words)
    k = 0
    while k < len(phrase) and not phrase[k].isalpha():
        k += 1
    e = len(phrase)
    while e > k and not phrase[e - 1].isalpha() and phrase[e - 1] != "'":
        e -= 1
    if phrase[k:e].lower().replace("\u2019", "'") not in _SLANG[core]:
        return None
    return phrase[:k] + typed_core + phrase[e:]


def _slang_split(typed_words, out_words):
    """Split out_words into one piece per typed word: abbreviations onto an expansion, other words onto one word."""
    if not typed_words:
        return [] if not out_words else None
    first, rest = typed_words[0], typed_words[1:]
    for size in range(1, min(4, len(out_words) - len(rest)) + 1):
        piece = out_words[:size]
        restored = _slang_piece(first, piece)
        if restored is None and size != 1:
            continue
        tail = _slang_split(rest, out_words[size:])
        if tail is not None:
            return [(size, restored)] + tail
    return None


def restore_slang(original, corrected):
    """SlangRestorer.restore."""
    _, typed = _word_tokens(original)
    lead, out = _word_tokens(corrected)
    if not typed or not out:
        return corrected
    key = lambda w: "".join(c for c in w.lower() if c.isalnum())
    a, b = [key(w) for w, _ in typed], [key(w) for w, _ in out]
    n, m = len(a), len(b)
    lcs = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            lcs[i][j] = lcs[i + 1][j + 1] + 1 if a[i] == b[j] else max(lcs[i + 1][j], lcs[i][j + 1])
    words = [w for w, _ in out]
    trailing = [t for _, t in out]
    removed = set()
    i = j = 0
    while i < n or j < m:
        if i < n and j < m and a[i] == b[j]:
            i += 1
            j += 1
            continue
        i0, j0 = i, j
        while i < n or j < m:
            if i < n and j < m and a[i] == b[j]:
                break
            if j == m or (i < n and lcs[i + 1][j] >= lcs[i][j + 1]):
                i += 1
            else:
                j += 1
        if not 1 <= i - i0 <= 6 or j == j0:
            continue
        split = _slang_split([w for w, _ in typed[i0:i]], words[j0:j])
        if split is None or all(r is None for _, r in split):
            continue
        q = j0
        for size, restored in split:
            if restored is not None:
                words[q] = restored
                trailing[q] = trailing[q + size - 1]
                removed.update(range(q + 1, q + size))
            q += size
    return lead + "".join(words[x] + trailing[x] for x in range(len(words)) if x not in removed)


def sentence_case(text):
    """ProofreadPrompt.sentenceCase (dictation path)."""
    out, start, prev = [], True, " "
    n = len(text)
    for i, ch in enumerate(text):
        nxt = text[i + 1] if i + 1 < n else " "
        if ch.isalpha():
            j = i
            while j < n and text[j].isalpha():
                j += 1
            inner_cap = any(c.isupper() for c in text[i + 1:j])
            pron = ch == "i" and not (prev.isalpha() or prev.isdigit()) and (nxt in "'\u2019" or not nxt.isalnum())
            out.append(ch.upper() if (start and not inner_cap) or pron else ch)
            start = False
        else:
            out.append(ch)
            if ch in ".!?":
                if nxt.isspace():
                    start = True
            elif ch in "\n\r":
                start = True
            elif not ch.isspace() and ch not in "\"'(\u201c\u2018":
                start = False
        prev = ch
    return "".join(out)


_LINK = re.compile("|".join([
    r"""https?://[^\s<>()"'`]+""", r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+",
    r"(?<![\w/:.])(?:~|\.{1,2})?/[\w.{}~-]+(?:/[\w.{}~-]*)+", r"""\b[A-Za-z]:\\[^\s"'`]+""",
    r"(?<![\w&#])#[A-Za-z][\w-]*", r"""[^\s"'`]*\\[^\s"'`]+""",
    r"<[@#!][^<>\s]+>", r"(?<![\w@#/.-])(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9][A-Za-z0-9_-]{5,}(?![\w-])"]))


def links(text):
    out = []
    for m in _LINK.finditer(text):
        link = m.group(0)
        while link and link[-1] in ".,;:!?)":
            link = link[:-1]
        out.append(link)
    return out


def restore_links(original, corrected):
    """LinkRestorer.restore."""
    typed = links(original)
    if not typed:
        return corrected
    text = corrected
    for link in typed:
        if link in text:
            continue
        cands = [c for c in links(text) if c not in typed]
        if not cands and "\\" in link:
            typed_tokens = set(original.split())
            cands = [t for t in text.split() if t not in typed_tokens]
        if not cands:
            continue
        best = max(cands, key=lambda c: similarity(link.lower(), c.lower()))
        if (similarity(link.lower(), best.lower()) >= 0.8 or _close_spelling(link.lower(), best.lower())) and best in text:
            text = text.replace(best, link, 1)
    return text


def _inword(text, mark):
    return sum(1 for k, c in enumerate(text) if c == mark and 0 < k < len(text) - 1
               and text[k - 1].isalpha() and text[k + 1].isalpha())


def match_apostrophe_style(original, text):
    """ApostropheFixer.matchApostropheStyle."""
    if not (_inword(original, "\u2019") > 0 and _inword(original, "'") == 0 and _inword(text, "'") > 0):
        return text
    prot = code_spans(text) + fences(text) + [(m.start(), m.end()) for m in _LINK.finditer(text)]
    out = list(text)
    for k, c in enumerate(text):
        if c == "'" and 0 < k < len(text) - 1 and text[k - 1].isalpha() and text[k + 1].isalpha() \
                and not any(a <= k < b for a, b in prot):
            out[k] = "\u2019"
    return "".join(out)


_CLOCK = re.compile(r"(?<![\w:])(\d{1,2}(?::\d{2})?)\s?([AaPp])\.?\s?[Mm]\.?(?!\w)")


def restore_times(original, text):
    """TypographyRestorer.restoreTimes."""
    typed = [(m.group(0), m.group(1) + m.group(2).lower()) for m in _CLOCK.finditer(original)]
    if not typed:
        return text
    tokens = {t for t, _ in typed}
    for token, key in typed:
        if token in text:
            continue
        for m in _CLOCK.finditer(text):
            if m.group(1) + m.group(2).lower() == key and m.group(0) not in tokens:
                text = text[:m.start()] + token + text[m.end():]
                break
    return text


def restore_typography(original, text):
    """TypographyRestorer.restore."""
    text = restore_times(original, text)
    def prot(t):
        return code_spans(t) + fences(t) + [(m.start(), m.end()) for m in _LINK.finditer(t)]
    for typo, ascii_ in (("\u2014", "---"), ("\u2014", "--"), ("\u2026", "...")):
        if typo in original and ascii_ not in original and ascii_ in text:
            p, out, k = prot(text), [], 0
            while k < len(text):
                if text.startswith(ascii_, k) and not any(a <= k < b for a, b in p):
                    out.append(typo)
                    k += len(ascii_)
                else:
                    out.append(text[k])
                    k += 1
            text = "".join(out)
    if ("\u201c" in original or "\u201d" in original) and '"' not in original and '"' in text:
        p, out, prev = prot(text), [], None
        for k, ch in enumerate(text):
            if ch == '"' and not any(a <= k < b for a, b in p):
                opens = prev is None or prev.isspace() or prev in "([{\u2014"
                out.append("\u201c" if opens else "\u201d")
            else:
                out.append(ch)
            prev = ch
        text = "".join(out)
    return text


def post_process(original, cleaned, typed):
    """The restorer chain after edge-whitespace restore, as in cleanResponse."""
    x = restore_typography(original, match_apostrophe_style(original, fix_apostrophes(restore_links(original, restore_code_spans(original, restore_line_breaks(original, restore_contractions(original, restore_slang(original, cleaned))))))))
    return keep_all_lowercase(original, x) if typed else sentence_case(x)


def clean_response(response, original, typed=False):
    out = response.strip()
    typed_text = original.strip()
    # A marker is a leak unless the writer's own text starts or ends with it; then only a doubled one is.
    if out.startswith("<text>") and (not typed_text.startswith("<text>") or out[len("<text>"):].strip().startswith("<text>")):
        out = out[len("<text>"):]
    if out.endswith("</text>") and (not typed_text.endswith("</text>") or out[: -len("</text>")].strip().endswith("</text>")):
        out = out[: -len("</text>")]
    lead = re.match(r"\s*", original).group(0)
    trail = re.search(r"\s*$", original).group(0) if original.strip() else ""
    return post_process(original, lead + out.strip() + trail, typed)


# --- CodeSpanRestorer.swift ---

def code_spans(text):
    """(start, end) of content between single-line backtick pairs."""
    res, i = [], 0
    while True:
        o = text.find("`", i)
        if o < 0:
            break
        st = o + 1
        k = st
        while k < len(text) and text[k] != "`" and text[k] not in _NEWLINES:
            k += 1
        if k >= len(text):
            break
        if text[k] == "`" and k > st:
            res.append((st, k))
            i = k + 1
        else:
            i = k + 1 if text[k] == "`" else k
    return res


def _bare_occurrence(content, text):
    code = code_spans(text)
    word = lambda c: c.isalnum() or c in "_`"
    start = 0
    while True:
        i = text.find(content, start)
        if i < 0:
            return None
        e = i + len(content)
        before = text[i - 1] if i > 0 else " "
        after = text[e] if e < len(text) else " "
        inside = any(a < e and i < b for a, b in code)
        if not word(before) and not word(after) and not inside:
            return i, e
        start = i + 1


def fences(text):
    """CodeSpanRestorer.fences: (start, end) of whole ``` blocks, fences included."""
    res, i = [], 0
    while True:
        a = text.find("```", i)
        if a < 0:
            break
        b = text.find("```", a + 3)
        if b < 0:
            break
        res.append((a, b + 3))
        i = b + 3
    return res


def restore_fences(original, corrected):
    src, out = fences(original), fences(corrected)
    if not src or len(src) != len(out):
        return corrected
    text = corrected
    for (a, b), (c, d) in reversed(list(zip(out, src))):
        if text[a:b] != original[c:d]:
            text = text[:a] + original[c:d] + text[b:]
    return text


def restore_code_spans(original, corrected):
    corrected = restore_fences(original, corrected)
    source = [original[a:b] for a, b in code_spans(original)]
    if not source:
        return corrected
    text = corrected
    out = code_spans(text)
    if len(out) == len(source):
        for (a, b), content in reversed(list(zip(out, source))):
            if text[a:b] != content:
                text = text[:a] + content + text[b:]
        return text
    for content in source:
        if "`" + content + "`" in text:
            continue
        quoted = next((q0 + content + q1 for q0, q1 in (('"', '"'), ("'", "'"), ("\u201c", "\u201d"), ("\u2018", "\u2019"))
                       if q0 + content + q1 in text), None)
        if quoted:
            i = text.find(quoted)
            text = text[:i] + "`" + content + "`" + text[i + len(quoted):]
        else:
            r = _bare_occurrence(content, text)
            if r:
                text = text[:r[0]] + "`" + content + "`" + text[r[1]:]
    return text


# --- LineBreakRestorer.swift ---

def _word_tokens(text):
    m = re.match(r"\s*", text)
    return m.group(0), re.findall(r"(\S+)(\s*)", text[m.end():])


def _nl_count(t):
    return sum(c in "\n\r\u000b\u000c\u0085\u2028\u2029" for c in t.strip())


def _has_nl(t):
    return any(c in "\n\r\u000b\u000c\u0085\u2028\u2029" for c in t)


def restore_line_breaks(original, corrected):
    _, src = _word_tokens(original)
    lead, out = _word_tokens(corrected)
    if len(src) < 2 or not out:
        return corrected
    key = lambda w: "".join(c for c in w.lower() if c.isalnum())
    a, b = [key(w) for w, _ in src], [key(w) for w, _ in out]
    n, m = len(a), len(b)
    lcs = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            lcs[i][j] = lcs[i + 1][j + 1] + 1 if a[i] == b[j] else max(lcs[i + 1][j], lcs[i][j + 1])
    match, i, j = {}, 0, 0
    while i < n and j < m:
        if a[i] == b[j]:
            match[i] = j
            i += 1
            j += 1
        elif lcs[i + 1][j] >= lcs[i][j + 1]:
            i += 1
        else:
            j += 1
    nl = lambda t: sum(c in "\n\r\u000b\u000c\u0085\u2028\u2029" for c in t)
    trailing = [ws for _, ws in out]
    for i in range(n - 1):
        ws = src[i][1]
        wanted = nl(ws)
        j = match.get(i)
        if j is not None and match.get(i + 1) == j + 1:
            if nl(trailing[j]) != wanted or (wanted > 0 and trailing[j] != ws):
                trailing[j] = ws
        elif wanted > 0:
            differs = lambda gap: nl(gap) < wanted or (nl(gap) == wanted and gap != ws)
            jn = match.get(i + 1)
            if jn is not None and jn > 0:
                if differs(trailing[jn - 1]):
                    trailing[jn - 1] = ws
            elif j is not None and j < m - 1 and differs(trailing[j]):
                trailing[j] = ws
    rebuilt = lead + "".join(w + t for (w, _), t in zip(out, trailing))
    o = _nl_count(original)
    return rebuilt if abs(_nl_count(rebuilt) - o) <= abs(_nl_count(corrected) - o) else corrected


# --- ContractionRestorer.swift ---

_CONTRACTIONS = [
    ("don't", ["do not"]), ("doesn't", ["does not"]), ("didn't", ["did not"]),
    ("can't", ["cannot", "can not"]), ("won't", ["will not"]), ("isn't", ["is not"]),
    ("aren't", ["are not"]), ("wasn't", ["was not"]), ("weren't", ["were not"]),
    ("haven't", ["have not"]), ("hasn't", ["has not"]), ("hadn't", ["had not"]),
    ("wouldn't", ["would not"]), ("shouldn't", ["should not"]), ("couldn't", ["could not"]),
    ("mustn't", ["must not"]), ("needn't", ["need not"]),
    ("it's", ["it is", "it has"]), ("that's", ["that is", "that has"]),
    ("there's", ["there is", "there has"]), ("what's", ["what is", "what has"]),
    ("here's", ["here is"]), ("who's", ["who is", "who has"]),
    ("he's", ["he is", "he has"]), ("she's", ["she is", "she has"]),
    ("let's", ["let us"]),
    ("I'm", ["i am"]), ("I've", ["i have"]), ("I'll", ["i will"]), ("I'd", ["i would", "i had"]),
    ("you're", ["you are"]), ("you've", ["you have"]), ("you'll", ["you will"]), ("you'd", ["you would", "you had"]),
    ("we're", ["we are"]), ("we've", ["we have"]), ("we'll", ["we will"]),
    ("they're", ["they are"]), ("they've", ["they have"]), ("they'll", ["they will"]), ("they'd", ["they would", "they had"]),
]
_CKEY = lambda w: "".join(c for c in w.lower() if c.isalpha())
_CTABLE = {_CKEY(c): (c, e) for c, e in _CONTRACTIONS}


def _contraction(typed, expansion):
    if not 1 <= len(expansion) <= 2 or _CKEY(typed) not in _CTABLE:
        return None
    contracted, expansions = _CTABLE[_CKEY(typed)]
    last, first = expansion[-1], expansion[0]
    k = len(last)
    while k > 0 and not last[k - 1].isalpha():
        k -= 1
    trailing = last[k:]
    i = 0
    while i < len(first) and not first[i].isalpha():
        i += 1
    leading = first[:i]
    phrase = " ".join(expansion)
    bare = phrase[len(leading): len(phrase) - len(trailing)]
    if not bare or bare.lower() not in expansions or not all(c.isalpha() or c == " " for c in bare):
        return None
    text = contracted
    if bare[0].isupper() and text[0].islower():
        text = text[0].upper() + text[1:]
    return leading + text + trailing


def restore_contractions(original, corrected):
    typed = original.split()
    m = re.match(r"\s*", corrected)
    lead, rest = m.group(0), corrected[m.end():]
    toks = re.findall(r"(\S+)(\s*)", rest)
    if not typed or not toks:
        return corrected
    key = lambda w: "".join(c for c in w.lower() if c.isalnum())
    a, b = [key(w) for w in typed], [key(w) for w, _ in toks]
    n, mm = len(a), len(b)
    lcs = [[0] * (mm + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(mm - 1, -1, -1):
            lcs[i][j] = lcs[i + 1][j + 1] + 1 if a[i] == b[j] else max(lcs[i + 1][j], lcs[i][j + 1])
    reps, i, j = [], 0, 0
    while i < n or j < mm:
        if i < n and j < mm and a[i] == b[j]:
            i += 1
            j += 1
            continue
        oi, oj = i, j
        while i < n or j < mm:
            if i < n and j < mm and a[i] == b[j]:
                break
            if j == mm or (i < n and lcs[i + 1][j] >= lcs[i][j + 1]):
                i += 1
            else:
                j += 1
        if i - oi == 1:
            t = _contraction(typed[oi], [w for w, _ in toks[oj:j]])
            if t is not None:
                reps.append((oj, j, t))
    if not reps:
        return corrected
    out, idx = lead, 0
    for s_, e_, t in reps:
        out += "".join(w + ws for w, ws in toks[idx:s_]) + t + toks[e_ - 1][1]
        idx = e_
    return out + "".join(w + ws for w, ws in toks[idx:])


# --- OutputGate ---

def _fold(text):
    return "".join(c for c in unicodedata.normalize("NFKD", text.lower()) if not unicodedata.combining(c))


def gate_words(text):
    return set(w for w in re.findall(r"[^\W_]+", _fold(text)))


def _close_spelling(a, b):
    """OutputGate.isCloseSpelling: Damerau-Levenshtein <= 1 (<= 4 letters) or <= 2, 3+ letters."""
    if len(a) < 3 or len(b) < 3:
        return False
    lim = 1 if min(len(a), len(b)) <= 4 else 2
    if abs(len(a) - len(b)) > lim:
        return False
    d = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a) + 1):
        d[i][0] = i
    for j in range(len(b) + 1):
        d[0][j] = j
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] != b[j - 1]))
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
    return d[len(a)][len(b)] <= lim


def surviving(input_keys, output_keys):
    """OutputGate.surviving: kept verbatim, or matched one-to-one to a new close-spelled output word."""
    inset, outset = set(input_keys), set(output_keys)
    new = []
    for w in output_keys:
        if w not in inset and w not in new:
            new.append(w)
    surv, used, seen = set(outset), set(), set()
    for w in input_keys:
        if w in outset or w in seen:
            continue
        seen.add(w)
        m = next((n for n in new if n not in used and _close_spelling(w, n)), None)
        if m is not None:
            used.add(m)
            surv.add(w)
    return surv


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
    if any(unicodedata.category(c) in ("Sc", "So") and c not in orig for c in output):
        return "introducedSymbol"
    if len(original) >= 20 and len(output) > len(original) * 3:
        return "overExpansion"
    ow = gate_words(original)
    if len(ow) >= 8 and len(ow & surviving(list(ow), list(gate_words(output)))) * 2 < len(ow):
        return "lowOverlap"
    if introduces_structure(original, output):
        return "introducedStructure"
    if drops_content(original, output):
        return "droppedContent"
    if drops_markup(original, output):
        return "droppedMarkup"
    if appends_content(original, output):
        return "appendedContent"
    return None


def appends_content(original, output):
    """OutputGate.appendsContent."""
    i, o = original.strip(), output.strip()
    if not i or len(o) <= len(i) or not o.startswith(i):
        return False
    extra = o[len(i):]
    word = lambda c: unicodedata.category(c)[0] in "LNM"  # letters, numbers, marks (Thai/Indic vowel signs)
    if word(i[-1]) and word(extra[0]):
        return False
    return sum(1 for c in extra if not (c.isspace() or unicodedata.category(c).startswith("P"))) >= 3


_TAG = re.compile(r"""</?[A-Za-z][A-Za-z0-9:-]*(?:\s+[A-Za-z_:][\w:.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*/?>""")


def drops_markup(original, output):
    """OutputGate.dropsMarkup: the output is missing a tag the input had."""
    need = {}
    for m in _TAG.finditer(original):
        need[m.group(0)] = need.get(m.group(0), 0) + 1
    if not need:
        return False
    have = {}
    for m in _TAG.finditer(output):
        have[m.group(0)] = have.get(m.group(0), 0) + 1
    return any(have.get(t, 0) < n for t, n in need.items())


def _sentences(line):
    res, cur, prev = [], "", None
    for ch in line.strip(" \t"):
        if ch.isspace() and prev is not None and prev in ".!?":
            res.append(cur)
            cur = ""
        elif not (ch.isspace() and cur == ""):
            cur += ch
        prev = ch
    if cur:
        res.append(cur)
    return res


def drops_content(original, output):
    """OutputGate.dropsContent."""
    ck = lambda w: "".join(c for c in _fold(w) if c.isalnum())
    kept = surviving([k for k in (ck(w) for w in original.split()) if k], [k for k in (ck(w) for w in output.split()) if k])
    lines = [l for l in re.split("[" + _NEWLINES + "]", original) if l != ""]
    for line in lines:
        sents = _sentences(line)
        for sent in sents:
            words = [k for k in (ck(w) for w in sent.split()) if k]
            if not words:
                continue
            surv = sum(w in kept for w in words)
            if len(words) < 4:
                if len(lines) > 1 and len(sents) == 1 and surv == 0:
                    return True
            elif surv * 2 < len(words):
                return True
    return False


_NEWLINES = "\n\r\u000b\u000c\u0085\u2028\u2029"


def introduces_structure(original, output):
    """OutputGate.introducesStructure: added line breaks, braces/brackets/fences, list or heading markers."""
    breaks = lambda t: sum(c in _NEWLINES for c in t.strip())
    if breaks(output) > breaks(original):
        return True
    if any(m in output and m not in original for m in ("{", "}", "[", "]", "```")):
        return True

    def starts(t):
        res = set()
        for line in re.split("[" + _NEWLINES + "]", t):
            line = line.lstrip()
            if not line:
                continue
            if line[0] in "-*•#":
                res.add(line[0])
            else:
                m = re.match(r"\d+", line)
                if m and line[m.end():].startswith(". "):
                    res.add("1.")
        return res
    return bool(starts(output) - starts(original))


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


def text_dictionaries(texts):
    """SpellCheckGate.dictionary(forText:) per text: '' = English rule, else a dictionary code."""
    if not texts:
        return []
    p = subprocess.run([str(HERE / "bin/langdet")], input="\n".join(json.dumps(t) for t in texts),
                       capture_output=True, text=True, check=True)
    out = p.stdout.split("\n")
    return [out[i] if i < len(out) else "" for i in range(len(texts))]


def misspelled(words, language=None):
    if not words:
        return set()
    if language:
        p = subprocess.run([str(SPELLCHECK), language], input="\n".join(words), capture_output=True, text=True, check=True)
        return set(p.stdout.split())
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
        max_tokens = max(min(MAX_KV, max(16, len(text) // 3) * 2 + 128), len(self.tok.encode(text)) * 2 + 128)  # LocalModelEngine.tokenBudget
        return generate(self.model, self.tok, prompt, max_tokens=max_tokens, sampler=self.sampler,
                        max_kv_size=MAX_KV)

    def generate_cached(self, instructions, text):
        """generate() with the system-prompt KV computed once per instructions and copied per call
        (mirrors LocalModelEngine's prefix cache). Falls back to generate() if the chat template
        doesn't split cleanly into system prefix + user turn."""
        import copy
        from mlx_lm import generate
        from mlx_lm.models.cache import make_prompt_cache
        user = [{"role": "user", "content": f"<text>\n{text}\n</text>"}]
        full = self.tok.encode(self.tok.apply_chat_template(
            [{"role": "system", "content": instructions}] + user, add_generation_prompt=True, tokenize=False))
        rest = self.tok.encode(self.tok.apply_chat_template(user, add_generation_prompt=True, tokenize=False))
        prefix = full[: len(full) - len(rest)]
        if full[len(prefix):] != rest:
            return self.generate(instructions, [], text)
        cache_store = self.__dict__.setdefault("_prefix_caches", {})
        if instructions not in cache_store:
            cache = make_prompt_cache(self.model, max_kv_size=MAX_KV)
            self.model(self.mx.array(prefix)[None], cache=cache)
            self.mx.eval([c.state for c in cache])
            cache_store[instructions] = (prefix, cache)
        stored_prefix, cache = cache_store[instructions]
        if stored_prefix != prefix:
            return self.generate(instructions, [], text)
        max_tokens = max(min(MAX_KV, max(16, len(text) // 3) * 2 + 128), len(self.tok.encode(text)) * 2 + 128)  # LocalModelEngine.tokenBudget
        return generate(self.model, self.tok, rest, max_tokens=max_tokens, sampler=self.sampler,
                        prompt_cache=copy.deepcopy(cache))

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
    elif split != "all" and not os.environ.get("BULLETPROOF_EVAL_CORPUS"):
        keep = set((ROOT / "splits" / f"{split}.txt").read_text().split())
    else:
        keep = None
    return [c for c in cases if keep is None or c["id"] in keep]


def main():
    if os.environ.get("BULLETPROOF_EVAL_LATENCY_AB") == "1" and "--split" in sys.argv:
        # Opt-in latency A/B (harness/latency_ab.py), printed as METRIC lines on the dev
        # pass of measure.sh; the normal dev run still follows so report.py has its input.
        import latency_ab
        for k, v in latency_ab.run().items():
            print(f"METRIC {k}={v}")
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
        # "prefix-cache": generations come from the cached-system-prompt path (as
        # LocalModelEngine does since #50), which can flip near-tie tokens.
        keys[name] = hashlib.sha256(json.dumps([instr, ex, "prefix-cache"]).encode()).hexdigest()[:16]
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
            # Cached rows hold cleaned output; cleaning is idempotent, so re-apply
            # the post-processing in case it changed since the row was cached.
            raws.append((post_process(c["input"], hit["raw"], name == "instructions"), hit["ms"]))
            continue
        s = time.time()
        out = qwen.generate_cached(instructions, c["input"]) if not examples else qwen.generate(instructions, examples, c["input"])
        raw = clean_response(out, c["input"], typed=name == "instructions")
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
    # Non-English outputs check introduced words against their own dictionary (#72).
    dicts = text_dictionaries([raw for raw, _ in raws])
    for k, d in enumerate(dicts):
        if d and intro[k]:
            intro[k] = [w for w in intro[k] if w in misspelled(intro[k], d)]
    for c, (raw, ms), p, ws, spans, d in zip(cases, raws, pre, intro, all_spans, dicts):
        flagged = (lambda w: True) if d else (lambda w: w in bad)
        reason = p or ("introducedMisspelling" if any(flagged(w) for w in ws) else None)
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
