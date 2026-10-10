# How a correction flows through the app (current, after the 2026-10-09/10 autoresearch)

Replaces `context/pipeline.md` (which describes the baseline at commit 75e4a8a) as the reference for the
current code. Results are in `RESULTS.md`, and the experiment history is in `.auto/log.jsonl` and `.auto/prompt.md`.

```
hotkey / Services / Shortcuts                      dictation (HotkeyDispatcher → DictationController)
        │  instructions                                    │  dictationInstructions
        └──────────────┬───────────────────────────────────┘
                       ▼
AppState.makeEngine(recordsStats:, instructions:)                                 AppState.swift
  RecordingEngine                    history + practice drill (CorrectionStats, typing slips only)
    └─ ScoredGateEngine              verify-corrections gate (opt-in setting)     Engines/SpanScorer.swift
         └─ OutputGatedEngine        deterministic gates + personal vocabulary    Engines/OutputGate.swift
              └─ AppleIntelligenceEngine | LocalModelEngine (Qwen3-4B, MLX)
                     └─ ProofreadPrompt.cleanResponse  →  post-processing chain   Engines/ProofreadPrompt.swift
```

## 1. Prompts (`ProofreadPrompt.swift`)
- **`instructions`** (typed text): a fix list (agreement, tense, articles, comparatives, double negatives, missing
  apostrophes, their/there, your/you're, of/have, then/than), then a keep list ("Do not restyle or reword": casing,
  slang, abbreviations, emoji, punctuation style, line breaks, backticks; casual lowercase stays lowercase), then 8
  inline examples. The examples balance casual lowercase against capitalized formal text, and one is a multi-sentence
  paragraph with scattered typos. Writing every example in lowercase teaches the model to lowercase formal text (#8).
- **`dictationInstructions`**: transcripts need punctuation and capitals, soundalikes are chosen by context,
  contractions are kept, and no rewording. A single shared prompt can't serve both, because transcripts and casual
  typing look alike as text (#2-#5).

## 2. Engines
- **LocalModelEngine** (Qwen3-4B 2507, temperature 0): `PrefixCacheStore` builds the system prompt's KV cache once
  per (model, instructions) and copies it into each `ChatSession(container, cache:)`. It's only used when the
  template splits cleanly into prefix + user turn, token for token. The result is 0.57x the original app's median
  latency (#50).
- **AppleIntelligenceEngine**: `GenerationOptions(sampling: .greedy)` makes output deterministic (#62). The typed
  path uses `@Generable Correction` (its guide carries the keep-style policy plus the fix list), and dictation uses
  `DictationCorrection` (transcript guide), selected by `isDictation` (#29, #35, #64).

## 3. Post-processing (`cleanResponse`, in order); each step only changes text where it applies
1. Strip leaked `<text>` markers, restore edge whitespace.
2. `SlangRestorer`: chat abbreviations the model expanded come back (`bc of` → `because of` → `bc of`).
3. `ContractionRestorer`: a single typed contraction expanded by the model gets re-contracted (`wasnt` → `was not` → `wasn't`).
4. `LineBreakRestorer`: line breaks are made to match the input between aligned words (lost, shrunk or added).
5. `CodeSpanRestorer`: backticked code is never proofread. It's restored, re-quoted or re-wrapped.
6. `ApostropheFixer`: unambiguous missing apostrophes (`Im`, `dont`, `wasnt`; not `cant`/`wont`/`were`/`its`).
7. Typed path: `keepAllLowercase` (an input with no capitals gets none back). Dictation: `sentenceCase`.

Restorers 2-4 share `WordAlignment.steps` / `WordTokens` (`LineBreakRestorer.swift`).
Replay over 4,480-6,470 stored outputs: every step had 0 pass→fail flips.

## 4. OutputGate (always on), first failing rule wins
emptyOutput, replacementCharacter, introducedControlCharacters, overExpansion, lowOverlap,
**introducedStructure** (new line breaks, `{}[]`, code fences, list or heading markers: answers rewritten as
bullets or JSON, #27), **droppedContent** (a 4+ word sentence keeps < half its words, or a short line such as a
sign-off vanishes in multi-line text, #39), protectedWordRemoved, introducedMisspelling.
- `SpellCheckGate`: on English systems a word is misspelled only if both the US and British dictionaries flag it (#46).
- Personal vocabulary: a lowercase protected word corrected to a spell-checker guess is a learned typo, so the fix
  is accepted and the entry forgotten (#67). Capitalized names stay protected.

## 5. Verify-corrections gate (opt-in), `EditSpan.swift` + `SpanScorer.swift`
Cosmetic spans and spell-checked typo fixes skip scoring (`SpanTriage`). Otherwise the gate vetoes when
`originalVetoMargin` (4.5, per-token mean) or `totalVetoMargin` (1.0, summed log-prob, only when the two versions
are within 1 token of the same length) is exceeded. Qwen rejections on 400 cases went from 15 to 1 (`analysis/gate-retune.md`).

## 6. Telemetry
`proofreadStats` counts hotkey, Services, intent and **dictation** (`dictation:<engine>|<outcome>`, #69) outcomes.
`CorrectionStats` learns only typing slips: misspelled, apostrophe-only, soundalike, or a one-letter slip (#68).

## 7. Evaluating changes
- Fast loop: `./.auto/measure.sh` (Python mirror, Qwen, dev 295 + guard 14, about 20 s cached). Corpus override:
  `BULLETPROOF_EVAL_CORPUS=<dir>` (fresh-2026-10-10, long-2026-10-10).
- Live: `SWIFT_VERIFY=1 ./.auto/measure.sh` (both engines, all 400, about 11 min). Both engines are deterministic, so one run is an exact A/B.
- Latency: `BULLETPROOF_EVAL_LATENCY_AB=1 ./.auto/measure.sh` (paired, ABBA-interleaved).
- Gotcha: only run SWIFT_VERIFY while the `.auto/*.sh` scripts are committed and unedited (#32-#34).
