# Support and development builds

This is private development software. Use the private repository’s [issue tracker](https://github.com/genisis-lab/crest/issues) for reports; repository access is required. No public support email has been assigned.

Before reporting: note the app version in Settings, whether the problem survives a relaunch, the steps to reproduce it, and the result you expected. Settings → Support can export a small, content-free diagnostics file for you to inspect and attach manually. Do not attach clipboard archives, provider configuration, authentication files, calendar exports or personal screenshots.

Useful report fields:

- Crest version/build and macOS version
- Mac architecture and notch/external-display setup
- Steps to reproduce, expected behavior, actual behavior
- Enabled integration involved; whether permission was denied or revoked
- Whether the issue occurs after sleep, reconnect, or an update
- Optional reviewed diagnostics export

Privacy information and uninstall instructions ship inside the app and are available from Support. Development builds use ad-hoc signing. They are intended for local testing, not notarized public distribution.

For a manual update, quit Crest, retain the existing app as a rollback copy, then open the newer locally built app. Do not remove Application Support data or Keychain entries. Schema-versioned history can reject an older app after a future incompatible migration; keep a backup before testing such a migration.

Apple Developer Program enrollment, Developer ID signing, notarization and public release hosting were deferred by the owner to avoid the annual membership fee. Sparkle remains integrated and tested locally; no live update service is enabled.
