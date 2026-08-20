## What's new in 0.0.16

- New Apps settings: turn bulletproof off for specific apps, or allow it in
  terminals it normally avoids (proofread that commit message in kitty).
  Password and code fields stay protected everywhere, always.
- bulletproof now learns words you use on purpose - names, jargon, brands -
  and refuses any correction that would rewrite them away. Learned words
  live only on this Mac, as single words, never sentences.
- New experimental "Verify corrections" option (Settings > Engine):
  double-checks each correction with the local model and blocks edits that
  don't hold up. Off by default while it earns trust.
- Quality is now measured, not guessed: a built-in benchmark scores every
  engine. Spoiler in Settings > Engine - the downloadable Qwen3 4B scored
  1.00 to Apple Intelligence's 0.84. Apple Intelligence remains the default
  (no download, no extra memory); switching is one download away.
- When bulletproof declines to proofread somewhere, it now says why -
  including when you turned it off for that app yourself.
