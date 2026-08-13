# 0003. DMG distribution after the stale-copy Gatekeeper incident

Date: 2026-08-13

## Status

Accepted

## Context

A fresh download of v0.0.7 was reported blocked by Gatekeeper ("Apple could
not verify bulletproof.app is free of malware") even though releases had been
Developer ID signed and notarized since v0.0.2. Investigation showed the
shipped artifact was clean: the released zip, downloaded fresh and stamped
with a quarantine flag, assessed as "accepted - Notarized Developer ID" and
passed `syspolicy_check distribution`.

Root cause: **a stale pre-notarization copy of the app on the target machine
was launched instead of the fresh download.** Early releases (v0.0.1-v0.0.5
era test copies) were development-signed and Gatekeeper-blocked by design;
copies of those builds remained on disk. Because zip distribution just
expands the app wherever the browser puts it, nothing prompts the user to
replace the old copy in /Applications - same name, same icon, and Launch
Services happily opens whichever copy it resolves. The failure looked like a
broken release but was a broken *install path*.

Two aggravating factors surfaced during diagnosis:

1. `release.sh` silently fell back to Apple Development signing when the
   Developer ID certificate was unavailable (e.g. locked keychain) and still
   exited 0 - a latent path to shipping a genuinely blocked artifact.
2. The reporter's own machine could never reproduce the issue because Sparkle
   updates are not quarantined; only fresh browser downloads on other
   machines exercise Gatekeeper at all.

## Decision

**Ship releases as a signed, notarized, stapled DMG instead of a zip.**
The drag-to-Applications flow makes replacing the old copy the default
gesture, structurally eliminating the stale-copy failure mode for anyone who
follows the install flow. Sparkle 2 mounts DMG enclosures natively, so the
appcast points at the same artifact - one file serves both first installs
and auto-updates.

**Make the pipeline unable to ship a blocked artifact:**
- `release.sh` hard-fails when no Developer ID certificate is present;
  development signing requires an explicit `ALLOW_DEV_SIGNING=1` that prints
  a do-not-publish warning.
- Both the app and the DMG are notarized and stapled (the app first, so it
  carries its own ticket after extraction; then the DMG wrapping it).
- `spctl --assess` runs against both as pipeline gates.

**Verification protocol for "it won't open" reports:** before assuming a bad
release, download the actual published artifact, apply a quarantine flag
(`xattr -w com.apple.quarantine`), and run `spctl --assess` - then check
which copy the reporter actually launched (Get Info > version). Sparkle's
lack of quarantine means local update testing proves nothing about the fresh
-download experience.

## Consequences

- New installs overwrite old copies by construction; the class of "ghost of
  a dev build" reports should disappear.
- Releases take one extra notarization round-trip (~1-2 min) for the DMG.
- The appcast enclosure changed from zip to DMG mid-stream; Sparkle handles
  both, and existing installs updated across the boundary without issue.
- A locked keychain now stops a release instead of degrading it - the right
  trade for an app whose failure mode is every future user being blocked.
- Machines that already hold a stale dev-signed copy still need one manual
  cleanup (trash old copies, install from DMG); the DMG only prevents new
  occurrences.
