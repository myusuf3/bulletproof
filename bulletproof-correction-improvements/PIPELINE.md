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
  per (model, instructions) and copies it into each request. Generation uses `generateTokens` and decodes the
  token IDs once at the end, not `ChatSession`: mlx-swift-lm's streaming detokenizer diffs chunks by grapheme
  count and silently dropped tokens that extend the previous character (skin tones, flags, ZWJ emoji, ❤️, 1️⃣,
  Devanagari vowel signs; #86). The output budget is max(the 3-chars-per-token estimate, input tokens × 2 + 128)
  and the whole exchange must fit the 4,096-token KV cache, else `inputTooLong` (#88). The character estimate alone
  truncated Hindi, Tamil, Bengali, Burmese and emoji runs (1.3-3 tokens per character), and pasted the cut text. It's only used when the
  template splits cleanly into prefix + user turn, token for token. The result is 0.57x the original app's median
  latency (#50).
- **AppleIntelligenceEngine**: `GenerationOptions(sampling: .greedy)` makes output deterministic (#62). The typed
  path uses `@Generable Correction` (its guide carries the keep-style policy plus the fix list), and dictation uses
  `DictationCorrection` (transcript guide), selected by `isDictation` (#29, #35, #64).

## 3. Post-processing (`cleanResponse`, in order); each step only changes text where it applies
1. Strip leaked `<text>` markers (only when the writer's own text doesn't start/end with that tag, else only a
   doubled one, #90), restore edge whitespace.
2. `SlangRestorer`: chat abbreviations the model expanded come back (`bc of` → `because of` → `bc of`), including
   ones carrying punctuation (`bday!!`, #54), adjacent ones that change together (`u tmrw` → `you tomorrow`, #94),
   and common chat/unit/weekday/month abbreviations (`min`, `ttyl`, `thurs`, `sept`, #98, #102). Restore-only: an
   abbreviation comes back only where the model wrote one of its listed expansions. A lowercase abbreviation the
   model only recased mid-sentence (`thurs` → `Thurs`, `tbh` → `TBH`) gets the writer's casing back (#121).
2b. `SpellingVariantRestorer`: a listed British spelling the model Americanized comes back (`colour` → `color` →
   `colour`, `organised`, `travelled`, `centre`, `licence`, …, #128). A curated table of ~600 forms, not suffix rules,
   so real fixes (`four` → `for`, `filled` → `filed`, `expence` → `expense`) are never undone. Dropped-g forms with the writer's
   apostrophe come back too (`fixin'` → `fixing` → `fixin'`, #130). So do expressive forms (#133): deliberate capitals the
   model only recased (`sUrE`, `WHY`, `NASA`; an ALL-CAPS word keeps caps when corrected, `TEH` → `THE`) and an
   elongation shortened to one letter (`looong` → `long` → `looong`; a tripled letter written twice is a typo,
   `offfice` → `office`, and stays fixed).
3. `ContractionRestorer`: a single typed contraction expanded by the model gets re-contracted (`wasnt` → `was not` → `wasn't`).
4. `LineBreakRestorer`: line breaks are made to match the input between aligned words (lost, shrunk or added), and
   the whitespace around each break is copied exactly, which removes the markdown hard-break spaces Qwen adds
   (`milk  \n`, 41% of its multi-line outputs, #77).
5. `CodeSpanRestorer`: code is never proofread. Fenced ``` blocks come back verbatim (#78), then backticked spans
   are restored, re-quoted or re-wrapped.
6. `LinkRestorer`: URLs (with or without a scheme: `www.…`, common TLDs, `domain.tld/path`, #112), emails, file paths (`/usr/…`, `C:\…`, API routes with 2+ segments), hashtags and any token
   with a backslash (escapes, LaTeX, `¯\_(ツ)_/¯`, #100), chat mentions (`<@U02ABC123>`) and identifiers that mix
   letters and digits (commit hashes, UUIDs, #108) are never
   proofread. An input literal missing from the output goes back over the closest-spelled new one
   (`exmaple.com`, `Documnets`, `#teh` stay as typed, #76, #85).
7. `ApostropheFixer` (skipped when the text is confidently non-English, so German `im` and French `dont` stay, #73):
   missing apostrophes (`Im`, `dont`, `wasnt`; not `cant`/`wont`/`were`/`its`), misplaced ones and the model's
   half-fixes (`would'nt`, `would't` → `wouldn't`, #80), and run-together phrases that are never words (`alot`,
   `atleast`, `eachother`, `noone` → `a lot`…, #81). It never touches code, links, hashtags or mentions.
7b. Writer's typography: if the original's in-word apostrophes are all curly, the output's become curly (#95);
   if it uses only “ ” / — / … (no straight `"`, `--`, `...`), the model's ASCII stand-ins are put back
   (`TypographyRestorer`, #97; Apple Intelligence flattened 5/12 smart-punctuation probes); the writer's clock-time
   spelling comes back when the output respells the same time (`6pm` → `6 pm` → `6pm`, #109), and so does a typed
   number + unit symbol the model spelled out or respaced (`5kg` → `5 kilograms` / `5 kg` → `5kg`, #111, #124), and emoticons the model split
   (`:P` → `: P` → `:P`, #112). A bracket or quote the model added at the very edge to "close" a partial selection
   (`(see the attached file` → `…file)`) is removed; not `[]`/`{}`, which introducedStructure needs (#116). Never in code or links.
8. Typed path: `keepAllLowercase` (an input with no capitals gets none back). Dictation: `sentenceCase` (#60).

Restorers 2-4 share `WordAlignment.steps` / `WordTokens` (`LineBreakRestorer.swift`). Alignment keys are letters and
numbers per Unicode scalar, so combining marks don't count, the same as the harness's `isalnum` (#103).
Replay over up to 10,962 stored outputs: every step had 0 pass→fail flips. `harness/invariants.py` checks that no
restorer changes a model echo (539 inputs) and that the chain is idempotent.

## 4. OutputGate (always on), first failing rule wins
emptyOutput, replacementCharacter, introducedControlCharacters, **introducedSymbol** (a currency sign or
symbol/emoji the writer didn't type: AI's "$€1,299.99", #100), overExpansion, lowOverlap,
**introducedStructure** (new line breaks, `{}[]`, code fences, list or heading markers: answers rewritten as
bullets or JSON, #27), **droppedContent** (a 4+ word sentence keeps < half its words, or a short line such as a
sign-off vanishes in multi-line text, #39, or 2+ of the writer's words are deleted outright: aligned to nothing,
not elsewhere in the output and not a close spelling, #119, or a typed link/email/path/mention/hashtag/identifier
is still missing after LinkRestorer, i.e. deleted or rewritten, #123), **droppedMarkup** (an HTML/XML tag of the input is missing; Apple
Intelligence strips markup, #93), **appendedContent** (the writer's whole text and then 3+ more non-punctuation
characters after a word boundary: the model kept generating, #107), protectedWordRemoved, introducedMisspelling.
- `SpellCheckGate`: on English systems a word is misspelled only if both the US and British dictionaries flag it (#46).
  When the corrected text is confidently non-English (`NLLanguageRecognizer` ≥ 0.8), its own language's
  dictionary is used, so correct fixes like `très` or `Mittwoch` aren't rejected (#72).
- `lowOverlap` and `droppedContent` count a word as surviving if it's kept verbatim or matched one-to-one to a
  close spelling (Damerau ≤ 1 for ≤ 4 letters, else ≤ 2, accent-folded). Typo-dense input like `Teh qiuck borwn
  fxo` is no longer rejected when it's corrected (#75).
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
  `BULLETPROOF_EVAL_CORPUS=<dir>` (fresh-2026-10-10, fresh2-2026-10-10, long-2026-10-10). Robustness sets, never tuned on:
  `adversarial-2026-10-10/` (46 unusual inputs: emoji, mixed scripts, URLs, fences, tables, CRLF, tabs…) and
  `multilingual-2026-10-10/` (14), run with `harness/fast_eval.py --cases <slice>.jsonl`.
- Live: `SWIFT_VERIFY=1 ./.auto/measure.sh` (both engines, all 400, about 11 min). Both engines are deterministic, so one run is an exact A/B.
- Latency: `BULLETPROOF_EVAL_LATENCY_AB=1 ./.auto/measure.sh` (paired, ABBA-interleaved).
- Swift/Python chain parity: `harness/swift_chain_parity.py` (#87; see its docstring). Rerun after restorer or gate changes.
- Restorer invariants: `python3 harness/invariants.py`: echo no-op, idempotence over every stored output, and
  "blocked answers stay blocked" (every stored or synthetic guard answer the gates reject is still rejected after
  the full chain, #117). `.auto/checks.sh` also requires `answered_pasted == 0`.
- Gotcha: only run SWIFT_VERIFY while the `.auto/*.sh` scripts are committed and unedited (#32-#34).
