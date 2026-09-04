# Architecture

```text
Codex account usage
        |
        v
local `codex app-server`
        |
        v
background quota feed -- percentage/style changed --> atomic PNG replacement
                                                   |
                                                   v
patched Codex main process -- setIcon --> native macOS Dock tile
```

The background process polls every 30 seconds and also accepts App Server update notifications. It can render either the numeric badge or the glass perimeter track into the same PNG output. Switching style restarts only this background renderer; it does not patch the app again.

The Codex patch makes four narrowly checked substitutions in the Electron main bundle:

1. permit the custom icon path for the default app channel;
2. point the Dock icon to `/tmp/codex-quota.png`;
3. refresh that path every five seconds;
4. force the unrelated red unread-count badge to zero.

The patcher edits a staged ASAR copy, recomputes the embedded bundle integrity values, and refuses anything other than exactly one match for every expected expression.

Because the percentage is part of the image owned by the Codex process, macOS magnifies the icon and percentage together. An external overlay cannot obtain that same Dock-tile ownership.
