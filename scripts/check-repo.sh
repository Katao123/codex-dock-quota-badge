#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
app_path=${CODEX_DOCK_BADGE_APP:-/Applications/ChatGPT.app}
node_path="$app_path/Contents/Resources/cua_node/bin/node"

for script in "$repo_dir"/scripts/*.sh "$repo_dir"/scripts/lib/*.sh; do
  /bin/zsh -n "$script"
done
/usr/bin/plutil -lint "$repo_dir/config/codex.entitlements"
if [[ -x "$node_path" ]]; then
  "$node_path" --check "$repo_dir/src/patch-app-asar.mjs"
elif command -v node >/dev/null; then
  node --check "$repo_dir/src/patch-app-asar.mjs"
else
  print -u2 'WARN: Node unavailable; skipped JavaScript syntax check'
fi
"$repo_dir/scripts/build.sh" >/dev/null

if /usr/bin/grep -R -n -E \
  --exclude-dir=.git \
  --exclude-dir=.build \
  --exclude=check-repo.sh \
  '(/Users/work|sk-[A-Za-z0-9_-]{12,})' \
  "$repo_dir"; then
  print -u2 'ERROR: repository contains a local path or likely secret'
  exit 1
fi

print 'repository_check=PASS'
