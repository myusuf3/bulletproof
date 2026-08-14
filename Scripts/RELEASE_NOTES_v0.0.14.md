## What's new in 0.0.14

Safety and reliability release.

- Proofreading is much safer: bulletproof now refuses to paste empty,
  garbled, or rewritten-instead-of-corrected model output, never touches
  password or verification-code fields, and leaves terminals alone.
- A correction that would introduce a misspelling is rejected outright -
  a proofread can never make your spelling worse.
- Selections are read directly through accessibility APIs when possible,
  so proofreading is faster and no longer times out in apps that are slow
  to answer a synthetic copy. Copy/paste now use the app's own Edit menu
  items, which fixes corrections landing wrong while keys were still held.
- Proofreading heated or informal text with Apple Intelligence no longer
  fails with an opaque error, and error messages now say what actually
  went wrong - including when a selection is too long.
- The local model starts loading the moment you press the shortcut,
  shaving seconds off the first proofread. Model downloads are verified
  for completeness so a bad connection can't install a corrupt model.
- Pressing Cmd+C right after a correction no longer loses what you copied.
- Onboarding resumes where you left off if it's interrupted, and if
  Accessibility access ever goes missing, bulletproof now tells you at
  launch instead of silently doing nothing.
- If another app owns your shortcut, bulletproof now says so instead of
  silently never firing.
