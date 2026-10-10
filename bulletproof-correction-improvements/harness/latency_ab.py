"""Latency A/B: baseline prompt (commit 75e4a8a) vs the current typed prompt, same process, alternated.

Same model, same inputs, interleaved ABBA order so load drifts hit both arms equally. Times one full
generate per input (prefill + decode), and counts prompt and output tokens. Prints METRIC lines.

  harness/.venv/bin/python harness/latency_ab.py [N]

Opt-in from measure.sh via fast_eval: BULLETPROOF_EVAL_LATENCY_AB=1 (see fast_eval.main).
"""
import json
import random
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fast_eval as F  # noqa: E402


def baseline_instructions():
    src = subprocess.run(["git", "-C", str(F.REPO), "show", "75e4a8a:bulletproof/Engines/ProofreadPrompt.swift"],
                         capture_output=True, text=True, check=True).stdout
    return F.swift_multiline(src, "instructions")


def run(n=60, seed=7):
    current, _ = F.load_prompt()
    base = baseline_instructions()
    cases = [c for c in F.load_cases("dev", None) if not c["id"].startswith("s3-")]
    random.Random(seed).shuffle(cases)
    cases = cases[:n]
    q = F.Qwen()
    q.generate(current, [], "warm up teh cache")  # load + Metal warm-up, not timed
    q.generate_cached(current, "warm up teh cache")  # builds the prefix cache once, not timed
    arms = {"baseline": base, "current": current, "current_cached": current}
    ms = {k: [] for k in arms}
    out_tokens = {k: [] for k in arms}
    for i, c in enumerate(cases):
        order = ["baseline", "current", "current_cached"]
        order = order if i % 2 == 0 else order[::-1]
        for arm in order:
            t = time.perf_counter()
            text = (q.generate_cached(arms[arm], c["input"]) if arm == "current_cached"
                    else q.generate(arms[arm], [], c["input"]))
            ms[arm].append((time.perf_counter() - t) * 1000)
            out_tokens[arm].append(len(q.tok.encode(text)))
    prompt_tokens = {k: len(q.tok.encode(v)) for k, v in arms.items()}
    pct = lambda v, p: sorted(v)[min(len(v) - 1, int(len(v) * p))]
    res = {}
    for k in arms:
        res[f"{k}_p50_ms"] = round(statistics.median(ms[k]), 1)
        res[f"{k}_p95_ms"] = round(pct(ms[k], 0.95), 1)
        res[f"{k}_mean_out_tokens"] = round(statistics.mean(out_tokens[k]), 1)
        res[f"{k}_prompt_tokens"] = prompt_tokens[k]
    # Primary: what ships (current prompt, prefix-cached) vs the original app (baseline prompt, uncached).
    paired = [c / b for b, c in zip(ms["baseline"], ms["current_cached"])]
    res["latency_ratio_p50"] = round(statistics.median(paired), 4)
    res["latency_ratio_mean"] = round(sum(ms["current_cached"]) / sum(ms["baseline"]), 4)
    res["uncached_ratio_p50"] = round(statistics.median([c / b for b, c in zip(ms["baseline"], ms["current"])]), 4)
    res["n"] = len(cases)
    return res


if __name__ == "__main__":
    r = run(int(sys.argv[1]) if len(sys.argv) > 1 else 60)
    for k, v in r.items():
        print(f"METRIC {k}={v}")
