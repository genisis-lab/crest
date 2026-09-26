# Sparkle release procedure

The development app has no `SUFeedURL` or `SUPublicEDKey`; it never checks another product's feed. `UpdateService` enables Sparkle only when the bundle includes an HTTPS feed URL and a valid 32-byte public key.

The owner has chosen development-only builds to avoid paid enrollment for now. No live feed, signing key or notarized release is being created. The procedure below is retained for a future distribution decision.

## Prerequisites

1. A Developer ID Application identity. Apple Development certificates alone are not a substitute for outside-the-App-Store distribution.
2. An existing `notarytool` Keychain profile for notarization.
3. A Sparkle Ed25519 key generated with Sparkle's `generate_keys` tool. Keep the private key in Keychain/offline backup; only its public half goes in the app.
4. An HTTPS appcast and anonymously downloadable release archives, or a designed authenticated delivery mechanism. The source repo can stay private. **Do not embed a GitHub token.**

No repository, feed or release is made public by the scripts. `release.sh` only prepares local artifacts and submits them to Apple's notarization service when explicitly run with configured credentials.

Create a local, git-ignored `release-config.json`:

```json
{
  "feed_url": "https://YOUR-UPDATE-HOST/appcast.xml",
  "sparkle_public_key": "YOUR-BASE64-PUBLIC-KEY",
  "version": "0.3.0",
  "build": 3
}
```

The placeholders are rejected by the validator. Increment `build` for every shipped update. Avoid changing the bundle identifier or signing identities between releases without planning a migration.

```sh
export CREST_SIGN_IDENTITY='Developer ID Application: YOUR IDENTITY'
export CREST_NOTARY_PROFILE='YOUR-EXISTING-PROFILE'
export CREST_RELEASE_CONFIG="$PWD/release-config.json"
export CREST_DOWNLOAD_PREFIX='https://YOUR-UPDATE-HOST/releases/'
export CREST_SPARKLE_ACCOUNT='YOUR-EXISTING-SPARKLE-KEYCHAIN-ACCOUNT'
export CREST_RELEASE_CHANNEL='stable' # or beta
bash scripts/release.sh
```

The script compares the configured public key with the chosen Keychain key before notarizing, requires a signed feed, verifies the generated feed and validates channel/archive metadata. Review generated release notes/appcast before uploading. Confirm archive URLs match their actual destinations and every enclosure has a Sparkle signature. Use `sparkle:channel` = `beta` for beta feed entries. Stable clients request no extra channels; beta clients also accept beta entries.

## Required release checks

- Install an older signed/notarized build; update to the next signed build through the real feed.
- Verify user data and settings survive, and the helper matches the shipped version.
- Confirm modified or unsigned archives are rejected before extraction.
- Test offline, interrupted download, invalid feed, unavailable feed, cancellation, and relaunch.
- Verify stable clients do not receive beta-only updates.
- Exercise Keychain continuity across signed upgrades; do not regenerate the clipboard key when an existing archive cannot be decrypted.

The current environment has development signing identities but no verified Developer ID Application identity. No public release or live update was published in this implementation session.

Source: [Sparkle documentation](https://sparkle-project.org/documentation/).

## Local verification without enrollment

`scripts/test-sparkle.py` uses disposable private seeds in a temporary directory, never the user Keychain. It signs/verifies an archive and feed with Sparkle 2.10 and verifies rejection of changed archives, a wrong key and changed feeds. `test-release.py` checks invalid configuration leaves the target bundle unchanged and validates stable/beta appcast metadata. These tests do not replace an actual update installation, offline/cancellation tests or Developer ID continuity checks.
