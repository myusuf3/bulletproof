# Non-English robustness set (2026-10-10)

14 short French/Spanish/German/Portuguese sentences with accent or spelling typos. Checks that the English-centric gates
(SpellCheckGate, introducedMisspelling, typo triage) don't reject correct non-English fixes. s1-m11..m14 are clean controls added after finding ApostropheFixer rewrote German "im" / French "dont" (#73). Never tune on it.
