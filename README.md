# bulletproof

Fix your writing anywhere on your Mac. One hotkey, on-device AI, zero cloud.

bulletproof is a macOS menu bar app that proofreads selected text in any app:

- **Global hotkey** (default ⌘⇧P): select text anywhere, press the shortcut, and the corrected text replaces your selection in place, with a green flash showing exactly what changed.
- **Right-click**: select text, then Services > Proofread. Works in every app, no permissions needed.
- **On-device**: powered by Apple Intelligence (Foundation Models). Your text never leaves your Mac.
- **Dictation** (default hold ⌥Space): hold the shortcut anywhere and speak; release and your words are typed at the cursor, with a live voice wave while you talk. Transcribes on-device with Apple Speech or [Cactus Whistle](https://huggingface.co/Cactus-Compute/whistle), a 17 MB offline model you can download in Settings.
- **Backup engines**: download open 4B models (Qwen3, Gemma 3) from Hugging Face and run them fully on-device via MLX - useful on Macs without Apple Intelligence.

## Requirements

- macOS 26 (Tahoe) or later
- Apple silicon with Apple Intelligence enabled
- Accessibility permission (for the hotkey; the app walks you through it on first launch)
- Microphone permission (only for dictation; also part of the first-launch walkthrough)

## Building

Open `bulletproof.xcodeproj` in Xcode 26+ and run. The first launch shows an onboarding walkthrough where you set your shortcut, grant permissions, and practice on typo-ridden text.
