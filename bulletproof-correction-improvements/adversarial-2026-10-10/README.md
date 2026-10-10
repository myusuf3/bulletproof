# Adversarial input set (2026-10-10)

34 inputs outside every corpus: 1-3 words, emoji, mixed scripts, ALL CAPS, headings, markdown, mentions, URLs, emails, CRLF, tabs, bullets, numbered lists, numbers and money, double spaces, curly quotes, shrug emoticon. Clean inputs are 'unchanged' controls. Robustness checks only; never tune on it.

Later rounds appended: round 2 (structure, #78), round 3 (literals, #85), grapheme probes (#86), dense-script budget probes (#88), markup (#90). #92 corrected three labels (s5-z02, s1-z06, s1-z07 contain real typos, so they're `fix`, not `unchanged`); every other `unchanged` row's flagged words are deliberate literals or foreign text.
