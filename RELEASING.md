# Releasing bulletproof

Updates ship via [Sparkle 2](https://sparkle-project.org/). The app reads
`appcast.xml` from the `main` branch of this repo
(`https://raw.githubusercontent.com/myusuf3/bulletproof/main/appcast.xml`),
and the zip itself is attached to a GitHub release.

## Prerequisites

- Xcode with this repo's toolchain; `gh` CLI authenticated.
- The Sparkle EdDSA **private key** in the login Keychain (see below).
- A codesigning identity. `Scripts/release.sh` prefers
  "Developer ID Application" and falls back to "Apple Development".

## Release steps

1. Bump the version in `bulletproof.xcodeproj/project.pbxproj`, in **both**
   app-target configs (Debug + Release):
   - `MARKETING_VERSION` = the new `X.Y.Z`
   - `CURRENT_PROJECT_VERSION` = previous value + 1 (Sparkle compares this
     build number, so it must strictly increase every release)
2. Verify build and tests are green:
   ```sh
   xcodebuild -project bulletproof.xcodeproj -scheme bulletproof -configuration Debug build
   xcodebuild test -project bulletproof.xcodeproj -scheme bulletproof \
       -only-testing:bulletproofTests -destination 'platform=macOS'
   ```
   Then push the release commit and **wait for CI to pass before publishing**
   (`gh run watch`). Local green is not sufficient - CI has caught
   environment-specific failures local runs missed, and a published release
   cannot be un-shipped.
3. Package. This builds Release, verifies the signature, zips, signs the zip
   with the Sparkle key, and rewrites `appcast.xml` at the repo root:
   ```sh
   Scripts/release.sh
   ```
4. Create the GitHub release (the appcast enclosure URL points at this exact
   tag and asset name, so do not rename either):
   ```sh
   gh release create vX.Y.Z dist/bulletproof-X.Y.Z.dmg \
       --title "bulletproof vX.Y.Z" \
       --notes-file Scripts/RELEASE_NOTES_vX.Y.Z.md
   ```
   Write the notes file first (see `Scripts/RELEASE_NOTES_v0.0.1.md` for the
   shape; include the Gatekeeper caveat below while builds are unnotarized).
5. Commit the updated `appcast.xml` (plus the version bump) and push to
   `main`. Existing installs only see the update once `appcast.xml` lands on
   `main`, so publish the GitHub release first, then push the appcast.

Note: the script writes a single-item appcast (latest version only). Sparkle
only needs the newest version to offer updates, and old zips stay
downloadable from their GitHub releases.

## Sparkle EdDSA key

- The private key lives in the **login Keychain** on Mahdi's Mac as a generic
  password item with service `https://sparkle-project.org` and account
  `ed25519`. It was created by Sparkle's `generate_keys` tool.
- It must **never** be committed to the repo or exported into CI logs.
- **Back it up** (`generate_keys -x sparkle_private_key.pem` exports it; store
  the file in a password manager, then delete it from disk). **Losing this key
  breaks the update chain**: released apps only accept updates signed by it,
  so every existing install would have to be re-downloaded manually.
- The matching public key is `SUPublicEDKey` in `bulletproof/Info.plist`.
- The Sparkle CLI tools (`generate_keys`, `sign_update`, `generate_appcast`)
  ship in the SPM artifact at
  `DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/` after a package
  resolve; `release.sh` locates `sign_update` there automatically.

## TODO when Apple Developer portal access is restored

Releases are currently signed with an "Apple Development" certificate, which
Gatekeeper does not trust for downloaded apps. Once a Developer ID is
available:

1. Create a "Developer ID Application" certificate in the portal (accept the
   latest Program License Agreement first if prompted) and install it in the
   login Keychain. `release.sh` will pick it up automatically.
2. Notarize after packaging, then re-run the appcast signing (the stapled
   zip differs from the unstapled one):
   ```sh
   xcrun notarytool submit dist/bulletproof-X.Y.Z.dmg \
       --keychain-profile "notary" --wait
   # staple the ticket to the app, then re-zip and re-sign:
   ditto -x -k dist/bulletproof-X.Y.Z.dmg /tmp/staple
   xcrun stapler staple /tmp/staple/bulletproof.app
   ditto -c -k --keepParent /tmp/staple/bulletproof.app dist/bulletproof-X.Y.Z.dmg
   ```
   (Set up the keychain profile once with `xcrun notarytool store-credentials`.)
   Easiest path: fold these steps into `release.sh` at that point so the
   appcast is generated from the final stapled zip.
3. Drop the Gatekeeper caveat below from the release notes.

## Gatekeeper caveat (include in release notes until notarized)

> **Note:** this build is not yet notarized, so macOS will refuse to open it
> with a normal double-click. After unzipping, either right-click
> `bulletproof.app` and choose **Open** (then **Open** again in the dialog),
> or clear the quarantine flag in Terminal:
> `xattr -d com.apple.quarantine /path/to/bulletproof.app`
> You only need to do this once, after the first download. Sparkle's
> in-app updates are unaffected.
