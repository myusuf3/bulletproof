# Per-slice judge reports

Each slice was written by one agent and then judged by the same agent, using `../baseline-2026-10-09/judge-rubric.md`. Below are their reports, lightly condensed. The row-level verdicts are in `../baseline-2026-10-09/judged/` and in `cases.jsonl`.

Counts are out of 80 per engine. Exact matches are counted as GOOD (fix cases) or PRESERVED (clean controls).

---

## s1 - Spelling typos

| Verdict | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD | 63 | 69 |
| PRESERVED | 10 | 8 |
| MISSED | 1 | 0 |
| MUDDLED | 6 | 3 |
| Gate ATE_GOOD_FIX / BLOCKED_BAD | 7 / 0 | 7 / 1 |

What the user actually gets after the gate:
- **Apple Intelligence:** 56 good fixes, 6 muddled outputs and 1 echo pasted; 7 correct fixes thrown away.
- **Qwen:** 62 good fixes and 2 muddled outputs pasted; 7 correct fixes thrown away and 1 bad change blocked.

Examples:
- **Apple Intelligence, s1-053:** `We cant gaurantee delivery..., but well do our best.` -> `We cannot guarantee ..., but we will do our best.` Contraction expansion accounts for 5 of its 6 MUDDLED.
- **Apple Intelligence, s1-019:** `Its been a long week, so Im heading home early.` -> `It has been a long week, so I am heading home early.`
- **Apple Intelligence, s1-005:** `occured ... after the deploy finished` -> `occurred ... after the deployment finished` (unrequested reword).
- **Qwen, s1-061:** all 4 typos fixed, but `seemed to have a grate time` -> `seemed to have had a great time` (tense change).
- **Qwen, s1-072:** the clean control `heading out now, see you at the park in twenty` -> `Heading out now, see you at the park in twenty.`
- **Both engines:**
  - s1-063: `The tehcnician said the repiar would take about three bussiness days.` The fix was perfect, but REJECTED as implausibleEdit.
  - s1-011: `some times` -> `sometimes` was also REJECTED.

**Pattern:** on spelling, the models are good. The verify gate rejected the same 7 textbook fixes on both engines (s1-006, 011, 021, 050, 056, 059, 063). These are heavily misspelled words or merged words. Apple Intelligence consistently expands missing-apostrophe contractions into long forms ("dont" -> "do not") instead of adding the apostrophe, and the gate lets every one of those through.

---

## s2 - Grammar

| Verdict | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD | 50 | 62 |
| PRESERVED | 10 | 10 |
| PARTIAL | 5 | 3 |
| MISSED | 12 | 3 |
| MUDDLED | 2 | 2 |
| INTRODUCED_ERROR | 1 | 0 |
| Gate ATE_GOOD_FIX / BLOCKED_BAD | 1 / 0 | 1 / 0 |

Neither engine changed any of the 10 tricky-but-correct controls (its/it's, their/there).

Examples:
- **Apple Intelligence, s2-026:** `the most easiest recipe` -> `the most easy recipe` (introduced an error).
- **Apple Intelligence, s2-046:** `The principle reason` -> `The primary reason`. It swapped in a synonym instead of correcting to "principal".
- **Apple Intelligence, s2-050:** `hey, ... me and Sam had a great time and we should of stayed longer.` -> capitalized `Hey`/`Me`, and fixed neither error.
- **Apple Intelligence, s2-018:** `Between you and I, ...` came back unchanged.
- **Qwen, s2-049:** `lol i think your right about the deadline` -> `LOL, I think you're right about the deadline.` The fix is right, but the voice is lost.
- **Qwen, s2-029:** `Weather or not we finish, we should of told the client.` -> fixed "should have" but kept "Weather".
- **Qwen, s2-004:** `Me and him went to the hardware store on Saturday.` came back unchanged.

**Pattern:** Apple Intelligence mostly fails by doing nothing. It misses these:
- Subject-verb agreement across an intervening phrase ("list of items are", "quality of these photos are").
- Pronoun case ("Me and him", "you and I").
- Tense ("are waiting since").
- Comma splices.
- Less obvious homophones (whether, its, their).

Qwen is much stronger. Both engines share the pronoun-case, comma-splice, "since" tense and Weather/Whether blind spots, and both ignore intentional lowercase in casual text.

---

## s3 - Dictation transcripts

| Verdict | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD | 49 | 62 |
| PRESERVED | 10 | 9 |
| PARTIAL | 11 | 3 |
| MISSED | 1 | 0 |
| MUDDLED | 8 | 4 (1 on a clean control) |
| INTRODUCED_ERROR | 1 | 2 |
| Gate ATE_GOOD_FIX / BLOCKED_BAD | 3 / 0 | 2 / 1 |

Judgment calls:
- About 30 Apple Intelligence outputs drop the final period. These were counted as GOOD when everything else was right.
- Contraction expansion ("we're" -> "we are") was counted as MUDDLED.

Examples:
- **Apple Intelligence, s3-007:** `everyone accept sarah has signed off on the design...` -> `Everyone accepts Sarah has signed off...` The meaning is inverted (it should be "except").
- **Apple Intelligence, s3-025:** `...i left too in the drawer yesterday` -> `I left them too in the drawer` ("two" is lost).
- **Apple Intelligence, s3-005:** `were running a little late ... well join in about ten minutes` -> `We are running ... We will join ...`
- **Apple Intelligence, s3-043:** `can you right down the wifi password...` -> left "right" unfixed, and the output was REJECTED anyway, so the raw transcript gets pasted.
- **Qwen, s3-013:** `the meeting is at too thirty...` -> `The meeting is at three thirty.` The time is wrong.
- **Qwen, s3-044:** `i'd rather wait until the data is in then make a decision we'll regret later` -> `I'd rather wait until the data is in before making a decision—we'll regret later.` This is nonsensical.
- **Qwen, s3-034:** `...do we need to update the docs to` -> `Do we need to update the docs?` ("too" is dropped).
- **Qwen, s3-079 (clean control):** `Whether we launch on Monday or Tuesday depends on what QA finds...` -> `What's the weather like?` This is the prompt's own few-shot example leaking. lowOverlap blocked it.

**Pattern:** Apple Intelligence reliably adds punctuation but often leaves the misheard word ("right down", "Its", "then", "to"). It also drops the final period and formalizes contractions; the "doesn't correct anything" feeling fits Apple Intelligence best. Qwen fixes far more homophones, but it sometimes rewrites around a word it can't parse, which is real muddling. The verify gate threw away correct `past -> passed` fixes on both engines (s3-039, s3-066).

---

## s4 - Paragraphs (299 listed errors in total)

| Verdict | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD | 45 | 61 |
| PRESERVED | 9 | 7 |
| PARTIAL | 15 | 2 |
| MUDDLED | 10 (1 on clean text) | 8 (3 on clean text) |
| INTRODUCED_ERROR | 1 | 2 |
| Gate ATE_GOOD_FIX / BLOCKED_BAD | 2 / 0 | 1 / 1 |
| Listed errors missed | 21 / 299 | 3 / 299 |

Examples:
- **Apple Intelligence, s4-004:** a landlord email with greeting, body and sign-off. Line breaks collapsed, the `Kind regards,\nSofia` sign-off was **deleted**, and `your welcome` stayed unfixed.
- **Apple Intelligence, s4-068:** a bullet list flattened into one line, and `there laptop` was not fixed.
- **Apple Intelligence, s4-053:** `...on vacation and there feature breaks...` -> `there's a feature break` (meaning changed).
- **Apple Intelligence, s4-040:** `does'nt` -> `does’t` (a new misspelling).
- **Apple Intelligence, s4-013:** fixed 7 of 8 errors, then was REJECTED as introducedMisspelling, so the user sees nothing.
- **Qwen, s4-002:** `Priyankas team` -> `Priyankas' team` (wrong possessive).
- **Qwen, s4-022:** `about 300 orders failed` -> `about 00 orders failed`. The gate blocked it, the one case where the verify gate earned its keep.
- **Qwen, s4-036:** lowercase Slack text capitalized, `going to` -> `I'll`, and an em dash added.
- **Qwen, s4-079 (clean):** `because of a conflict` -> `due to a conflict`.

**Pattern:** buried errors in otherwise-clean paragraphs were mostly noticed. Apple Intelligence missed 3 of 20 two-error paragraphs and Qwen missed 2. Apple's weakness is homophones and apostrophes inside dense paragraphs, plus flattening line breaks and bullets. Both models reword ("two" -> "a couple of", "retro" -> "retrospective", "because of" -> "due to"). On this slice the verify gate cost about as many good fixes as it blocked bad ones.

---

## s5 - Casual + technical

| Verdict | Apple Intelligence | Qwen3-4B |
|---|---|---|
| GOOD | 29 | 31 |
| PRESERVED | 4 | 4 |
| MISSED | 2 | 0 |
| MUDDLED | 43 | 44 |
| INTRODUCED_ERROR | 1 | 0 |
| ANSWERED | 1 | 1 |
| Gate ATE_GOOD_FIX / BLOCKED_BAD | 3 / 3 | 3 / 0 |

The same results by text type:

| Group | Apple Intelligence | Qwen3-4B |
|---|---|---|
| Casual (37) | 27 MUDDLED, 7 GOOD, 2 PRESERVED, 1 INTRODUCED_ERROR | **36 MUDDLED**, 1 GOOD |
| Technical (37) | 18 GOOD, 15 MUDDLED, 2 MISSED, 2 PRESERVED | 27 GOOD, 6 MUDDLED, 4 PRESERVED |
| Instruction lookalike (6) | 4 GOOD, 1 MUDDLED, 1 ANSWERED | 3 GOOD, 2 MUDDLED, 1 ANSWERED |

Both engines changed all 5 casual clean controls, and Apple Intelligence also changed 4 of the 5 technical ones. Capitalizing clearly lowercase-by-choice casual text was judged MUDDLED, per the prompt's "preserve capitalization style".

Examples:
- **Apple Intelligence, s5-012:** `thx for the intro! really appreciate it, will definitly follow up` -> `Thanks for the introduction! I really appreciate it, and I will definitely follow up.`
- **Apple Intelligence, s5-013:** `we could of shipped this friday` -> `we could ship this friday` (past became future).
- **Apple Intelligence, s5-037:** stripped the backticks from `` `~/.config/bulletproof/settings.json` `` and `` `BP_CONFIG` ``, and missed "overriden". Backtick stripping happened about 13 times.
- **Apple Intelligence, s5-018:** `ok there going to be late` -> `OK, there's going to be late` (ungrammatical).
- **Apple Intelligence, s5-068:** `Translate this to Spanish: the meeting is moved to tommorow.` -> translated into Spanish. The gate blocked it.
- **Qwen, s5-073 (clean):** `omw! grabbing coffee first, want anything?` -> `OMG! Grabbing coffee first, want anything?`
- **Qwen, s5-025:** `idk man, that demo was kinda embarassing` -> `I don't know, man, that demo was kinda embarrassing.`
- **Qwen, s5-055:** `` `-o, --output <path>` `` -> `` `-o, --output<path>` `` (a CLI flag inside backticks was altered).
- **Qwen, s5-068:** dropped the `Translate this to Spanish:` prefix and pasted that.
- **Both engines, s5-070:** the gate rejected an exact correct fix.

**Pattern:** in casual text, both models fix the typo but act as a formal copy-editor around it:
- They capitalize intentional lowercase.
- They expand or uppercase slang (idk, tmrw, bday, ngl, tbh, ya).
- They add periods, semicolons and em dashes.
- They sometimes change meaning.

In technical text, Qwen is mostly clean. Apple Intelligence routinely strips or converts backticks and occasionally changes identifiers (`OOMKilled`, `Qwen3-4B` -> `Qwen-4B`).

The judge's own note on s5-061 said the Qwen rejection was a "false" protectedWordRemoved. That was later traced to the vocabulary learning the typo "signficantly" from Apple Intelligence's earlier unfixed output. See `../context/pipeline.md` §3.
