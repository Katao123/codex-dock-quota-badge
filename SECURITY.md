# Security and recovery

This project intentionally changes the local Codex desktop app. Read this before installation.

## Trust boundaries

- The quota feed reads the local Codex App Server only.
- No API key, login credential, profile database, or quota payload is uploaded.
- The patcher accepts only versions and original ASAR hashes in `compatibility/releases.tsv`.
- Every official file changed by the patch is backed up and hash checked first.
- A failed patch attempts immediate restoration and never falls through to an unsupported implementation.

## Code-signing impact

Patching changes the official bundle and therefore invalidates the OpenAI signature. The installer re-signs the bundle locally with the minimum entitlements required by the Electron app. macOS may ask again for access to the Codex Safe Storage keychain item.

`scripts/restore.sh` restores the original ASAR, Info.plist, executable, and signature resources, then verifies the original SHA-256 and OpenAI Team ID `2DC432GLL2`.

## Updates

An official Codex update can replace the patch. The update checker compares the installed hash and sends one local notification. It does not automatically patch a new or unsupported release.

## Reporting

Do not attach Codex profile files, keychain exports, tokens, or raw App Server messages to an issue. Include only macOS version, Codex version, script step, and redacted error text.
