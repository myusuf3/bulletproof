# 0006. Onboarding: dark-glass hero, staggered motion, and a sound palette

Date: 2026-08-20

## Status

Accepted

## Context

The walkthrough was a utilitarian system-styled window - functional, but the
first launch is the one moment every user actually looks at the app, and the
bar for delight in this space is set by apps like Alcove (dark glass card,
glowing icon, feature triptych, one big call to action). Animation guidance
we follow (frequency rule) says surfaces seen hundreds of times must not
animate - which makes first-run onboarding exactly the surface where motion
and sound *are* justified.

## Decision

- **Forced dark-glass chrome**: the onboarding window pins
  `NSAppearance(.darkAqua)` regardless of system theme - the welcome card is
  a brand surface, not a document. Traffic lights are hidden; Esc and the
  flow's own buttons are the ways through.
- **Hero welcome**: large app icon over a breathing accent glow, gradient
  title, subtitle, a three-column feature card (shortcut / everywhere /
  private), privacy line, one centered Get Started.
- **Motion discipline** (Emil Kowalski's rules): one-shot staggered entrance
  - ease-out springs, scale from 0.96 (never 0), 80ms apart, a small masking
  blur; ambient loops kept subtle (glow breathes on ~4s, triptych symbols
  stir on offset periods so nothing pulses in lockstep). Reduce Motion
  renders everything instantly and disables all loops.
- **Single-hue color discipline**: the accent is the only chroma. The glow is
  the accent *darkened in HSB* rather than low-alpha accent over gray -
  alpha compositing drifts hue toward slate and reads as a second blue
  (verified by pixel-sampling screenshots: glow and button now share hue
  within 3°). Even the neutrals lean a few percent toward the accent. Green
  survives only as the small success checkmark, where a complementary pop at
  tiny area is signal, not competing chrome.
- **Sound palette** (`UISound`, quiet system sounds): forward steps pop, back
  is quieter, the accessibility grant purrs, the practice win rings Glass,
  finishing plays a small Hero. Onboarding sounds are unconditional (rare,
  first-run ceremony). The only recurring sound - a Tink when a correction
  lands - is user-configurable in Settings and defaults on.

Alternatives rejected: following the system theme (breaks the card's brand
register and halves the design surface to test); continuous/looping entrance
animation (violates the one-shot rule; loops are reserved for ambience);
bundled custom audio files (system sounds are zero-asset, familiar, and
already loudness-normalized).

## Consequences

- Forced dark is a standing constraint: every future onboarding step must be
  designed against the dark backdrop only.
- Snapshot tests capture layout but not motion, sound, or the true button
  tint (prominent buttons desaturate in non-key windows; the test host has a
  placeholder icon) - onboarding changes need a human pass via the dev
  target, which shows the walkthrough on every launch thanks to its own
  defaults domain.
- Hidden window buttons trade discoverability for polish; Esc-to-dismiss
  must keep working from every step.
- The sound palette is a commitment: new steps should draw from it rather
  than invent new sounds, and anything recurring outside onboarding must be
  configurable like the fix Tink.
