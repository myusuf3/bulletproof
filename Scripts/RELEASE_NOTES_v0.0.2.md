## What's new in 0.0.2

**Now notarized.** bulletproof is signed with a Developer ID certificate and
notarized by Apple - it opens first try on any Mac, no Security & Privacy
approval needed.

### Fixes since 0.0.1

- Proofreading no longer pastes into the wrong app if you switch windows
  while the model is thinking - the correction waits on your clipboard
  instead, with a notification.
- Slack and other Electron apps: slow copies no longer produce a false
  "Nothing to proofread".
- Your clipboard is never wiped when restoring after a proofread, even if
  the pasteboard read fails.
- The onboarding practice screen can no longer trigger the real proofread
  flow mid-tutorial.
- Proofreading errors are surfaced properly when notifications were denied
  (Settings now shows how to re-enable them).
- Shortcut conflicts with other apps are now detected truthfully, and
  re-recording your existing shortcut works.
- Grammar fixes no longer strip literal `<text>` markers you're writing about.
- Model download reliability: atomic installs, cancel always cancels.

### Note for 0.0.1 users

This update changes the app's code-signing identity (development certificate
to Developer ID). macOS will ask you to re-grant Accessibility access once
after updating: System Settings > Privacy & Security > Accessibility.

### Requirements

- macOS 26 (Tahoe) or later, Apple silicon
- Apple Intelligence enabled for on-device proofreading
