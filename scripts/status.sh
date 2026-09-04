#!/bin/zsh
set -euo pipefail
setopt null_glob

script_dir=${0:A:h}
source "$script_dir/lib/common.sh"

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
state_path="$support_root/installed-state.plist"
style_path="$support_root/style"
app_path=$(badge_find_app) || badge_die '找不到正式 Codex App'
asar_path="$app_path/Contents/Resources/app.asar"
current_hash=$(badge_sha256 "$asar_path")

badge_info "app=$app_path"
badge_info "version=$(badge_app_version "$app_path")"
badge_info "asar_sha256=$current_hash"
if badge_app_is_running "$app_path"; then
  badge_info 'app_running=yes'
else
  badge_info 'app_running=no'
fi

if [[ -f "$state_path" ]]; then
  patched_hash=$(badge_state_value "$state_path" PatchedAsarSHA256 || true)
  if [[ "$current_hash" == "$patched_hash" ]]; then
    badge_info 'badge_patch=installed'
  else
    badge_info 'badge_patch=missing_or_updated'
  fi
  badge_info "backup=$(badge_state_value "$state_path" BackupDirectory || true)"
else
  badge_info 'badge_patch=not_installed'
fi

if [[ -s /tmp/codex-quota-percent.txt ]]; then
  badge_info "remaining_percent=$(/bin/cat /tmp/codex-quota-percent.txt | /usr/bin/tr -dc '0-9')"
else
  badge_info 'remaining_percent=unavailable'
fi

style=$(/bin/cat "$style_path" 2>/dev/null | /usr/bin/tr -d '[:space:]' || true)
case "$style" in
  numeric|ring) badge_info "style=$style" ;;
  *) badge_info 'style=numeric (default)' ;;
esac

user_domain="gui/$(/usr/bin/id -u)"
for label in com.local.codex-dock-quota-feed com.local.codex-dock-quota-update-check; do
  if /bin/launchctl print "$user_domain/$label" >/dev/null 2>&1; then
    badge_info "$label=loaded"
  else
    badge_info "$label=not_loaded"
  fi
done
