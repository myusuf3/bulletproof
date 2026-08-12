## What's new in 0.0.6

**Local models are live.** Downloaded models (Qwen3 4B Instruct, Gemma 3 4B)
now actually proofread - fully on-device via Apple's MLX runtime. Pick one in
Settings > Engine and everything (hotkey, right-click, Shortcuts) uses it.

- The first proofread after switching loads the model (a few seconds - watch
  the menu bar seal pulse); after that it stays fast.
- The model unloads after 5 idle minutes to give the memory back (~3 GB while
  active).
- Refreshed model catalog: 4B-class models so every Apple silicon Mac can run
  them. Older downloaded models show under "No longer offered" for cleanup.
- New "Delete All Models" button in Settings > Models.

### Requirements

- macOS 26 (Tahoe) or later, Apple silicon
- Apple Intelligence for the default engine, or a downloaded local model
