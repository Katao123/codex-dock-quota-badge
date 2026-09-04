#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source "$script_dir/lib/common.sh"

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
state_path="$support_root/installed-state.plist"
user_domain="gui/$(/usr/bin/id -u)"
launch_agents="$HOME/Library/LaunchAgents"
feed_agent="$launch_agents/com.local.codex-dock-quota-feed.plist"
update_agent="$launch_agents/com.local.codex-dock-quota-update-check.plist"

if [[ -f "$state_path" ]]; then
  "$script_dir/restore.sh"
fi
/bin/launchctl bootout "$user_domain" "$feed_agent" 2>/dev/null || true
/bin/launchctl bootout "$user_domain" "$update_agent" 2>/dev/null || true
/bin/rm -f "$feed_agent" "$update_agent" /tmp/codex-quota.png /tmp/codex-quota-percent.txt
/bin/rm -rf "$support_root/runtime"
badge_info 'uninstall=PASS'
badge_info "backups_preserved=$support_root/backups"
