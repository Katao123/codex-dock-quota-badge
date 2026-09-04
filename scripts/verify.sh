#!/bin/zsh
set -euo pipefail
setopt null_glob

script_dir=${0:A:h}
source "$script_dir/lib/common.sh"

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
state_path="$support_root/installed-state.plist"
app_path=$(badge_find_app) || badge_die '找不到正式 Codex App'
asar_path="$app_path/Contents/Resources/app.asar"
[[ -f "$state_path" ]] || badge_die '没有安装状态'
expected_hash=$(badge_state_value "$state_path" PatchedAsarSHA256)
[[ $(badge_sha256 "$asar_path") == "$expected_hash" ]] || badge_die '正式 App 补丁哈希不匹配'
/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/grep -a -F '/tmp/codex-quota.png' "$asar_path" >/dev/null || badge_die '缺少动态图标入口'
/usr/bin/grep -a -F 'setBadgeCount(0)' "$asar_path" >/dev/null || badge_die '红色未读角标抑制未生效'

user_domain="gui/$(/usr/bin/id -u)"
/bin/launchctl print "$user_domain/com.local.codex-dock-quota-feed" >/dev/null \
  || badge_die '额度后台未加载'
/bin/launchctl print "$user_domain/com.local.codex-dock-quota-update-check" >/dev/null \
  || badge_die '升级检测未加载'
[[ -s /tmp/codex-quota.png ]] || badge_die '额度图标尚未生成'
percent=$(/bin/cat /tmp/codex-quota-percent.txt | /usr/bin/tr -dc '0-9')
[[ "$percent" == <-> && "$percent" -ge 0 && "$percent" -le 100 ]] \
  || badge_die '真实余量尚未生成'
style=$(/bin/cat "$support_root/style" 2>/dev/null | /usr/bin/tr -d '[:space:]' || true)
case "$style" in
  numeric|ring) ;;
  *) badge_die '显示方式配置无效' ;;
esac

typeset -a matching_apps
local_app=''
for local_app in /Applications/*.app "$HOME"/Applications/*.app; do
  [[ -f "$local_app/Contents/Info.plist" ]] || continue
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$local_app/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$bundle_id" == com.openai.codex || "$bundle_id" == com.local.codex-dock-quota-installer ]]; then
    matching_apps+=("$local_app")
  fi
done
(( ${#matching_apps} == 1 )) || badge_die "检测到 ${#matching_apps} 个 Codex/安装副本: ${matching_apps[*]}"

badge_info 'verify=PASS_MACHINE_CHECKS'
badge_info "remaining_percent=$percent"
badge_info "style=$style"
badge_info "visible_codex_apps=${#matching_apps}"
badge_info "official_app=${matching_apps[1]}"
badge_info 'visual_check=请在真实 Dock 中确认角标位置与同步缩放'
