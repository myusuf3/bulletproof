# 0004. CI-gated releases and local snapshot review

Date: 2026-08-13

## Status

Accepted

## Context

Two related incidents on the same day exposed gaps in how changes get
verified before users see them.

First, UI changes shipped blind. The settings redesign went through three
release cycles (v0.0.9-v0.0.11) driven by user screenshots of misaligned
layout, because nothing in the workflow rendered the UI before publishing -
each "fix" was a guess verified only after release. A layout bug that takes
seconds to spot visually (a shortcut pill stretched across its row) cost a
full release round-trip.

Second, releases published before CI finished. v0.0.11 was announced while
its CI run was still in progress; that run then failed. The failure was
test-infrastructure, not product code (the new snapshot tests hog the main
actor and starved parallel main-actor timing tests on slow CI runners), but
the ordering flaw was real and had already occurred once before (v0.0.7's
flake surfaced post-publication). The release pipeline (local build,
notarize, publish) never depended on CI at all - local green was treated as
sufficient.

## Decision

**Snapshot review before UI ships.** A local-only test suite
(`SettingsSnapshotTests`) renders settings panes to PNGs via ImageRenderer
and offscreen NSWindow capture. UI changes are reviewed from these renders -
first by the agent making the change, then by the user (files opened in
Preview or sent inline) - before any release is cut. This replaces the
ship-screenshot-fix loop with an iterate-on-renders loop that takes minutes.

**Snapshot tests never run on CI.** They are gated on the absence of the
`CI` environment variable. Rendering hogs the main actor, which starves
parallel main-actor tests on slow runners (the direct cause of the v0.0.11
CI failure), and a PNG nobody looks at verifies nothing.

**CI green is a release precondition.** Codified in RELEASING.md: push the
release commit, wait for CI to pass (`gh run watch`), then run
`Scripts/release.sh` and publish. Local test results are necessary but not
sufficient - CI runs on a machine that differs from the development Mac in
exactly the ways that have caught real issues (scheduler pressure, cold
caches, no installed models), and a published release cannot be un-shipped.

## Consequences

- Releases gain one CI round-trip (~5-8 minutes with MLX compilation). The
  cost bought correctness twice on day one; it is cheap insurance.
- Visual defects are caught pre-release by renders instead of post-release
  by users. Known limits: ImageRenderer cannot rasterize some AppKit-backed
  controls (switch toggles render as placeholders) and NavigationSplitView
  chrome does not render offscreen - those still need a human eye on the
  running app.
- Timing-sensitive tests and renderer-heavy tests must not share the main
  actor on CI; any future suite that spins the run loop or renders images
  should be CI-gated or serialized from the start.
- The renders double as lightweight design documentation of what each pane
  looked like at any commit.
