# Codex installation contract

This repository is operated by Codex on behalf of a Mac user. Keep one deliverable: install and verify the native Dock quota badge, or leave the machine unchanged.

## Non-negotiable rules

1. Start with `./scripts/preflight.sh`. It is the only allowed first command.
2. Do not patch a version or `app.asar` hash absent from `compatibility/releases.tsv`.
3. Do not rewrite the implementation on the user's machine. Use the reviewed scripts and source in this repository.
4. Before changing the official app, verify the OpenAI signature and create the hash-checked backup used by `scripts/patch-app.sh`.
5. Never request an OpenAI API key. The feed may only call the local `codex app-server` rate-limit method.
6. Do not upload credentials, quota payloads, logs, or files from the user's Codex profile.
7. Never bypass macOS privacy controls. If App Management blocks the patch, tell the user exactly which visible Codex item to enable, then retry the same script.
8. A self-install into a running official Codex is allowed only after preflight passes and only through `scripts/install.sh`; `install-numeric.sh` and `install-ring.sh` are fixed-style entry points that delegate to it. Pass `--allow-running` and tell the user that Codex must be fully restarted afterward.
9. Run `./scripts/verify.sh` after restart. Machine checks are not a substitute for looking at the real Dock.
10. Completion requires exactly one visible Codex app. Remove any installer/test copy created during the task; never remove the official app or the verified backup.
11. If any write, signature, hash, or backup check fails, stop and restore. Do not improvise around the failure.
12. Codex updates are detected and reported; never silently re-patch an updated unsupported build.

## Expected sequence

`preflight -> explain signature/permission impact -> choose numeric or ring installer -> restart official Codex -> verify -> inspect Dock -> clean temporary copy`

The final response must fit on one screen and report: result, remaining percentage, verification status, backup location, and restore command.
