#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source "$script_dir/lib/common.sh"

style=${1:-}
case "$style" in
  numeric|ring) ;;
  *) badge_die '用法: scripts/set-style.sh numeric|ring' ;;
esac

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
style_path="$support_root/style"
user_domain="gui/$(/usr/bin/id -u)"
agent_label=''

for candidate in com.local.codex-dock-quota-feed com.local.codex-native-quota-feed; do
  if /bin/launchctl print "$user_domain/$candidate" >/dev/null 2>&1; then
    agent_label="$candidate"
    break
  fi
done
[[ -n "$agent_label" ]] || badge_die '尚未安装 Codex Dock Quota Badge'
/bin/mkdir -p "$support_root"
temporary_path="$support_root/.style.tmp.$$"
print -r -- "$style" >| "$temporary_path"
/bin/chmod 600 "$temporary_path"
/bin/mv -f "$temporary_path" "$style_path"

/bin/launchctl kickstart -k "$user_domain/$agent_label"
badge_info "style=$style"
badge_info "agent=$agent_label"
badge_info 'switch=PASS'
