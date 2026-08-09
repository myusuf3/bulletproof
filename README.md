# bulletproof

Fix your writing anywhere on your Mac. One hotkey, on-device AI, zero cloud.

bulletproof is a macOS menu bar app that proofreads selected text in any app:

- **Global hotkey** (default ⌘⇧P): select text anywhere, press the shortcut, and the corrected text replaces your selection in place, with a green flash showing exactly what changed.
- **Right-click**: select text, then Services > Proofread. Works in every app, no permissions needed.
- **On-device**: powered by Apple Intelligence (Foundation Models). Your text never leaves your Mac.
- **Backup engines**: download ~8B open models (Gemma, Qwen) from Hugging Face for local inference (coming soon).

## Requirements

- macOS 26 (Tahoe) or later
- Apple silicon with Apple Intelligence enabled
- Accessibility permission (for the hotkey; the app walks you through it on first launch)

## Building

Open `bulletproof.xcodeproj` in Xcode 26+ and run. The first launch shows an onboarding walkthrough where you set your shortcut, grant permissions, and practice on typo-ridden text.
