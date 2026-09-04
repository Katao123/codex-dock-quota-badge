#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source "$script_dir/lib/common.sh"

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
state_path="$support_root/installed-state.plist"
notice_path="$support_root/update-needs-repair.txt"
[[ -f "$state_path" ]] || exit 0
app_path=$(badge_state_value "$state_path" AppPath)
asar_path="$app_path/Contents/Resources/app.asar"
[[ -f "$asar_path" ]] || exit 0
current_hash=$(badge_sha256 "$asar_path")
patched_hash=$(badge_state_value "$state_path" PatchedAsarSHA256)
[[ "$current_hash" == "$patched_hash" ]] && exit 0

last_notified_hash=$(/bin/cat "$notice_path" 2>/dev/null || true)
if [[ "$last_notified_hash" != "$current_hash" ]]; then
  print -r -- "$current_hash" >| "$notice_path"
  /usr/bin/osascript -e \
    'display notification "把 GitHub 项目的提示词再次交给 Codex 即可。" with title "Codex 已升级，余量角标需要恢复"' \
    >/dev/null 2>&1 || true
fi
badge_info 'update=DETECTED_REINSTALL_REQUIRED'
