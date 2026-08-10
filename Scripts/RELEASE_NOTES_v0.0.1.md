First downloadable release of bulletproof, a menu-bar proofreader for macOS.

## Features

- System-wide proofreading of the current selection with a global hotkey
  (Cmd-Shift-P by default, configurable in Settings)
- Right-click Services integration: "Proofread" (replace in place) and
  "Proofread to Clipboard" in any app's Services menu
- On-device proofreading via Apple Intelligence - nothing leaves your Mac
- Interactive onboarding walkthrough with a practice area
- Groundwork for downloadable local models as an alternative engine
- Automatic updates via Sparkle (this release onward)

## Requirements

- macOS 26 or later
- Apple silicon
- Apple Intelligence enabled (System Settings > Apple Intelligence & Siri)

## Install

1. Download `bulletproof-0.0.1.zip` below and unzip it.
2. Move `bulletproof.app` to `/Applications`.
3. **First launch:** this build is not yet notarized, so macOS will refuse a
   normal double-click. Right-click `bulletproof.app` and choose **Open**,
   then **Open** again in the dialog - or clear the quarantine flag in
   Terminal: `xattr -d com.apple.quarantine /Applications/bulletproof.app`.
   You only need to do this once.
4. Grant Accessibility access when prompted (needed to read your selection)
   and follow the onboarding walkthrough.
