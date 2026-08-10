# 0001. Sparkle release and auto-update pipeline

Date: 2026-08-10

## Status

Accepted

## Context

bulletproof is distributed outside the Mac App Store by necessity: the global
hotkey feature simulates keystrokes via CGEvents and requires Accessibility
access, both forbidden under the App Sandbox. Direct distribution means we own
the whole update problem - users need a way to discover, download, and verify
new versions, and we need a repeatable way to cut releases. We also currently
lack a Developer ID certificate (Apple Developer portal access is blocked
pending Program License Agreement acceptance), so notarized distribution is
not yet possible.

## Decision

**Update framework: Sparkle 2.x via Swift Package Manager.** The de facto
standard for direct-distribution macOS apps, actively maintained, and its 2.x
line works without app-level XPC configuration. A `Check for Updates...` item
lives in the menu bar extra; automatic checks are enabled at launch through a
single `UpdaterController` singleton.

**Artifact hosting: GitHub Releases; feed hosting: appcast.xml on the main
branch** (served via raw.githubusercontent.com). Both ride on infrastructure
we already use - no separate web host, CDN, or S3 bucket to maintain. The
feed URL is baked into Info.plist (`SUFeedURL`); each release updates
appcast.xml with the new version, release-asset URL, and signature.

**Update integrity: Sparkle EdDSA (ed25519) signatures.** Every release zip
is signed with a private key; the public key ships in Info.plist
(`SUPublicEDKey`). Installed apps refuse any update whose signature does not
verify, which protects users even if the GitHub account or feed were
compromised. Key custody:
- The private key lives in the login Keychain (service
  `https://sparkle-project.org`), written there by Sparkle's `generate_keys`.
- A backup export lives in iCloud Drive under `Keychain Export/bulletproof/`,
  verified by re-signing the v0.0.1 artifact and matching the published
  signature (EdDSA is deterministic). Losing this key permanently breaks the
  update chain for every installed copy - there is no rotation mechanism.

**Code signing: Apple Development identity for now, Developer ID +
notarization when available.** `Scripts/release.sh` automatically prefers a
"Developer ID Application" certificate when one exists in the keychain.
Until then, releases carry a Gatekeeper caveat in their notes (right-click >
Open on first launch). We never ship unsigned builds: Sparkle requires the
update's signing identity to be consistent with the installed app.

**Release mechanics: one idempotent script (`Scripts/release.sh`).** Build
Release, verify codesign, zip with `ditto`, sign with `sign_update`, template
appcast.xml. The appcast is templated rather than generated with
`generate_appcast` because the latter mis-URLs older archives as dist/
accumulates. Runbook in RELEASING.md; version lives in `MARKETING_VERSION`.

## Consequences

- Users get verified in-app updates from v0.0.1 onward; we can ship fixes
  without asking anyone to re-download manually.
- We are committed to the EdDSA key forever: it must survive machine
  migrations (hence the verified iCloud backup) and must never enter the
  repo or CI logs.
- The appcast-on-main choice couples the update feed to the repo: a force
  push or repo rename breaks the feed URL baked into shipped apps. Acceptable
  at this stage; a custom domain can front the feed later without changing
  the architecture (it would require a new app release to change SUFeedURL).
- Publish order matters: the GitHub release (asset URL) must exist before the
  updated appcast lands on main, or updaters briefly see a dead enclosure.
- Until the PLA is accepted and a Developer ID certificate exists, every new
  user pays the right-click-to-open Gatekeeper tax, and Sparkle updates are
  only as trustworthy as the EdDSA signature (which is the stronger check
  anyway, but Gatekeeper provenance is what users see).
- First `sign_update` run on a new machine triggers a Keychain authorization
  prompt; unattended/CI signing needs `SPARKLE_ED_KEY_FILE` pointed at a key
  export.
