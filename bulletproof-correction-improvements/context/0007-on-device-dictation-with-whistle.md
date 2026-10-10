# 0007. On-device dictation with Apple Speech and Cactus Whistle

Date: 2026-10-04

## Status

Accepted

## Context

bulletproof fixes text people have already typed. Dictation - speak, and the
text appears at the cursor - is the natural next input, and it fits the
app's promise only if it stays on-device. Cactus released Whistle, an
Apache-2.0 speech-to-text model that ships as one 16.9 MB `.cact` file
(7 languages, 16 kHz mono, at most 30 s per pass) and runs on Cactus's own
C++ engine ("Needle"), distributed as prebuilt static libraries per platform
with a small C API (`needle_load`, `needle_transcribe`). macOS 26 also ships
SpeechAnalyzer, an on-device transcriber with no download inside our app.

## Decision

**Hold-to-talk, batch transcription.** A second global shortcut (default
⌥Space) records while held; release stops, transcribes the whole clip, and
pastes it at the cursor through the same clipboard-snapshot-and-restore
path the proofreader uses. Batch (not streaming) keeps both engines behind
one `SpeechToTextEngine.transcribe([Float])` seam and matches Whistle's
whole-clip API. A floating, non-activating pill shows a live waveform while
listening so the paste target keeps focus.

**Two engines, user's choice.** Apple Speech is the default (built in,
nothing to download); Whistle is a catalog download. Whistle joins
`ModelCatalog` as a `.speech` model with a file allowlist, because its repo
also holds a 220 MB training checkpoint. Proofreading consumers (engine
picker, verify gate, benchmark) filter to `.proofreading` models so a speech
model is never loaded as an MLX model.

**Vendor the engine as a local Swift package.** `Packages/Needle` wraps
`libneedle.a` + `needle.h` (macOS arm64, from Cactus-Compute/needle3) in a
static-library xcframework, pinned to a Hugging Face revision by
`Scripts/update-needle.sh`. The engine is process-global and not
thread-safe, so the Swift face is a singleton actor. Clips longer than 30 s
are split at the quietest 50 ms frame near each boundary. We link the
static library rather than shell out to the `needle` CLI: no second
executable to sign and notarize, and no subprocess per dictation.

**Microphone permission is asked in context.** The onboarding walkthrough
gains a microphone step with a live meter; Settings > Dictation repeats the
grant, the device picker, and a mic test. The onboarding version is not
bumped: existing users get the system prompt on their first dictation
press instead of a replayed walkthrough.

## Consequences

- A 1.4 MB prebuilt binary lives in the repo, and updating the engine is a
  manual, pinned step (rerun the script, rebuild, run the Needle tests with
  `WHISTLE_MODEL` set).
- The engine is arm64-only, matching the app's Apple-silicon requirement.
- The app now carries the `audio-input` hardened-runtime entitlement and a
  microphone usage string; the mic is live only while the shortcut is held
  or a meter is on screen.
- Whistle stays loaded (~17 MB) once used; the C API has no unload.
- Long dictations are bounded by memory only (16 kHz float, ~4 MB/minute).
