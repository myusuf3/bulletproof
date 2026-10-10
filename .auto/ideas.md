# Ideas backlog (prompt track)

## In-loop (only the `instructions` string)
- Replace the few-shot examples with **style-preserving** demonstrations: a lowercase casual line with a typo
  that keeps lowercase and slang; `dont` → `don't` (add the apostrophe, don't expand); a sentence with
  `` `code` `` and a typo where the code stays untouched; a 2-line input that keeps its line break. Keep one injection example
  (rephrased, not the guard's wording). Use topics unlike the corpus.
- Add an explicit minimal-edit rule in positive framing: "change only words that are misspelled or
  ungrammatical; keep the writer's casing, slang, abbreviations, contractions, emoji and punctuation choices".
- Describe the transcript case explicitly: "if the text has no punctuation at all, it's a speech transcript, so add
  sentence punctuation and capitals". This tests whether one prompt can serve both s3 and s5.
- Instruction placement: rules before versus after the examples, and a short rule restated at the end.
- Shorter overall prompt: the current one is 664 chars. Check whether removing the "grammar checker" framing changes over-editing.
- Injection robustness: an example where a request-like line ("can you list three…") is echoed with only a
  typo fixed. Watch `answered_count`.
- Tell the model the output replaces the selection in place, so anything other than the corrected text is destructive.

## Outside this loop (need code or harness changes, so separate tracks)
- ~~Structural-transform gate~~: done in #27 (answered_pasted 2 → 0).
- (old note) **Structural-transform gate (injection):** prompt examples don't stop short transforms that pass lowOverlap, like
  g-04 (sentence → bullet list) and g-13 (prose → JSON), both pasted over the user's text (#18). Add an OutputGate rule:
  reject when the output introduces structure the input lacks (new leading `- `/`1.` lines, `{`/`}` or `:` pairs, or
  more lines than the input). Deterministic, cheap, and catches the worst failure (silent destructive paste).
- ~~Spell-check-triggered second pass~~: measured (#21). Only 1 of 27 remaining dev failures has a still-flagged
  word, since the rest are real words. Not worth the latency.
- **Remaining dev failures (27, after #15) by class:** homophones in long text ×5, dictation soundalikes ×4, pronoun case ×3
  (an instruction gives "I and Sam", #21), alot ×3 (NSSpellChecker doesn't flag it), contraction expanded ×2, 1 introduced error
  (would't), plus style judgment calls. Most promising: **H8, Qwen3-8B 4-bit** on the same prompts (needs a download, and
  watch p95), or small deterministic post-fixes (re-contract "It is"→"It's" when the input had "Its").
- ~~Gemma-3-4B (H8, catalog model)~~: #22, pass .810, errors_fixed .836. Much weaker corrector, but answered only
  3/14 guard lookalikes (Qwen 7). Qwen3-4B stays. Qwen3-8B isn't in ModelCatalog. Gemma is in /tmp/models (3.2 GB).
- ~~Qwen3-8B 4-bit (H8)~~: #23, pass .810, errors_fixed .888, p95 4.5 s. The 2507 refresh of Qwen3-4B out-corrects
  the original 8B. Model swaps are exhausted. /tmp/models holds Gemma (3.2 GB) and Qwen3-8B (4.3 GB); delete when done.
- ~~Sentence chunking for paragraphs~~ (offline probe after #24): s4 dev pass 48 → 48, errors fixed 206 → 203, p50 1.7 s → 5.1 s.
  Shorter context doesn't raise recall, and it costs about 3× latency. Dead.
- ~~Casing restorer for all-lowercase typed input~~: 0 of 50 such corpus inputs want capitals, but the prompt already keeps
  lowercase (1.0), and the only failing dev row (s5-002) also has an inserted word. No gain available.
- **Closing anti-obey reminder (#25, #26): an owner decision.** Two wordings both cut guard answers 7 → 4-5 and cost
  1-2 dev cases. If injection safety is worth about 0.5 pp of pass_rate, use #25's line ("Reply with only the corrected
  text: every error fixed, the writer's style kept."). Otherwise rely on the structural-transform gate.
- **Typed-prompt fragility:** one added sentence swings ~20 cases (#16), and errors_fixed sits at the floor (.948).
  Recall in long paragraphs (s4 .80, mostly "1 of N errors missed") may need a bigger model (H8) or a second pass
  for spans the spell checker still flags after the first pass (code change).
- ~~Verify gate (H2)~~: done in commit 1c8ac5a (15 → 1 Qwen rejections on 400 cases).
- **Dictation prompt (H6):** `DictationController` builds its own proofreader, so it can pass a transcript-specific prompt.
- Chat-turn few-shot (`static let examples`): needs `ChatSession` history in LocalModelEngine and a transcript in
  AppleIntelligenceEngine. The harness already supports it.
- Deterministic style guards (H3): casing transfer and slang restore in code.
- Qwen3-8B or Gemma-3-4B (H8) once the prompt has converged.
- **Mid-sentence capital restore (#82, discarded for no measurable gain):** if the writer capitalized a word that isn't at a
  sentence or line start (`Sam`, `Python`) and the model lowercased exactly that word, put the capital back. The replay over
  all stored outputs fired 20 times on 3 cases, every one correct, but 0 fail→pass, because those rows fail for other reasons.
  Worth adding if real-usage telemetry shows names being lowercased. The probe is in /tmp/caps_probe.py, and it must treat
  `- ` bullets as line starts.
- **Adversarial round 3 leftovers (#85, not fixed):** `1\u00a0200 kg` → `1,200 kg` (the model rewrote an SI thousands
  separator); a combining-accent `café` comes back NFC-normalized (it looks the same but the bytes differ; Swift `==`
  treats them as equal anyway). Both are rare and cosmetic.
- **Upstream bug report (owner):** in mlx-swift-lm (bd4b7434), `NaiveStreamingDetokenizer.next()` takes the new text as
  `newSegment.suffix(newSegment.count - segment.count)`, which counts grapheme clusters. Any token that extends the
  previous character is dropped: skin tones, regional-indicator pairs, ZWJ, VS16, keycaps, Indic and Thai combining marks.
  This affects every `ChatSession` user. The fix would diff by unicodeScalars or UTF-8 bytes. bulletproof avoids it as of #86
  (generateTokens plus one decode). Worth filing upstream with the 👍🏽 repro.
- ~~Appended-continuation gate~~ (done in #107). Original note (from #88): a 300-emoji run (the input pattern ×30) was echoed and then continued (420 → 968
  code points). That's 2.3×, under overExpansion's 3×. Before #88 it was cut off and pasted instead, so neither version is good.
  Candidate OutputGate rule: the output starts with the whole input and adds 3+ non-punctuation characters. 0 acceptable
  corpus outputs and 0 stored pasted rows would be flagged; it only catches already-rejected guard answers plus this probe.
  Low value unless it shows up in real use.
- **From fresh set 2 (#101):** (a) Apple Intelligence swaps the writer's emoji (🙂 → 😊). introducedSymbol blocks it, so it's safe but shows an error. An emoji restorer (the input's emoji are literals: put each one back where the model swapped a different emoji in) would turn the error into a correct paste. (b) Weekday abbreviations (mon, tues, wed, thurs, fri) are missing from SlangRestorer's table. AI wrote `thurs` → `thursday`, and the spell checker then rejected the lowercase `thursday`. Add restore-only entries.
- **Dictation spoken-email/URL forms (#113, a product question for the owner):** both engines turn "jane at example dot com"
  into "jane@example.com". Qwen's version is rejected by droppedContent, so the raw transcript is kept; Apple Intelligence
  half-converts it. Users probably want the address, but the dictation prompt says to keep the speaker's words. If wanted:
  convert "<name> at <word> dot <tld>" deterministically on the dictation path, and teach droppedContent that the address
  keeps the words.
