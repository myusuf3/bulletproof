#!/bin/bash
# Verification: full Swift runner, both engines, 400 cases. Emits METRIC lines.
# Body in a function: bash parses it all before running, so editing this file
# mid-run can't make bash resume mid-line (#33 "tination: command not found").
main() {
set -euo pipefail
cd /Users/myusuf3/workspace/bulletproof
D=bulletproof-correction-improvements/baseline-2026-10-09
OUT=/tmp/eval-both && rm -rf $OUT && mkdir -p $OUT
cat $D/corpus/slice*.jsonl > $OUT/all.jsonl
# Never share the build DB with a still-running xcodebuild (#32 crashed on that).
while pgrep -x xcodebuild >/dev/null; do sleep 5; done
cp $D/runner/ZZScratchCorrectionEval.swift bulletproofTests/
trap 'rm -f bulletproofTests/ZZScratchCorrectionEval.swift' EXIT
TEST_RUNNER_BULLETPROOF_EVAL_CORPUS=$OUT/all.jsonl TEST_RUNNER_BULLETPROOF_EVAL_OUT=$OUT/outputs.jsonl \
  xcodebuild test -project bulletproof.xcodeproj -scheme bulletproof -destination 'platform=macOS' \
  -derivedDataPath /tmp/dd-main -only-testing:bulletproofTests/ZZScratchCorrectionEval > $OUT/xcode.log 2>&1
grep -q "TEST SUCCEEDED" $OUT/xcode.log
cd bulletproof-correction-improvements
python3 - <<'PY'
import json, sys
sys.path.insert(0, "analysis"); import metrics as M
corpus = M.load_corpus(M.DEFAULT_CORPUS)
rows = [json.loads(l) for l in open("/tmp/eval-both/outputs.jsonl")]
for split in ("dev", "holdout"):
    ids = set(open(f"splits/{split}.txt").read().split())
    for layer in ("gated", "user_sees"):
        res = M.summarize(rows, corpus, layer, ids)
        for eng, r in res.items():
            e = "qwen" if eng == "qwen3-4b" else "ai"
            tag = f"{e}_{split}" + ("" if layer == "gated" else "_seen")
            if e == "qwen" and split == "dev" and layer == "gated":
                print(f"METRIC pass_rate={r['pass_rate']}")
            for k in ("pass_rate", "errors_fixed_rate", "lowercase_kept_rate", "slang_kept_rate", "code_kept_rate",
                      "linebreaks_kept_rate", "contraction_expanded_rate ↓", "clean_preserved_rate", "rejected_rate ↓", "p95_ms ↓"):
                if r.get(k) is not None:
                    print(f"METRIC {tag}_{k.split(' ')[0]}={r[k]}")
PY
}
main "$@"
exit $?
