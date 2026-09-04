#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
source "$script_dir/lib/common.sh"

allow_running=0
if [[ "${1:-}" == '--allow-running' ]]; then
  allow_running=1
fi

"$script_dir/preflight.sh"
feed_binary=$("$script_dir/build.sh" | /usr/bin/tail -1)

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
runtime_dir="$support_root/runtime"
launch_agents="$HOME/Library/LaunchAgents"
logs_dir="$HOME/Library/Logs"
feed_agent="$launch_agents/com.local.codex-dock-quota-feed.plist"
update_agent="$launch_agents/com.local.codex-dock-quota-update-check.plist"
user_domain="gui/$(/usr/bin/id -u)"
app_path=$(badge_find_app)
output_path='/tmp/codex-quota.png'
status_path='/tmp/codex-quota-percent.txt'

if badge_app_is_running "$app_path" && [[ "$allow_running" != 1 ]]; then
  badge_die '正式 Codex 正在运行。由 Codex 自助安装时需显式执行 scripts/install.sh --allow-running'
fi

/bin/mkdir -p \
  "$runtime_dir/scripts/lib" \
  "$runtime_dir/src" \
  "$runtime_dir/config" \
  "$runtime_dir/compatibility" \
  "$launch_agents" \
  "$logs_dir"
/usr/bin/ditto "$feed_binary" "$runtime_dir/CodexDockQuotaFeed"
/usr/bin/ditto "$repo_dir/src/patch-app-asar.mjs" "$runtime_dir/src/patch-app-asar.mjs"
/usr/bin/ditto "$repo_dir/config/codex.entitlements" "$runtime_dir/config/codex.entitlements"
/usr/bin/ditto "$repo_dir/compatibility/releases.tsv" "$runtime_dir/compatibility/releases.tsv"
for runtime_script in patch-app.sh restore.sh status.sh verify.sh uninstall.sh notify-on-update.sh; do
  /usr/bin/ditto "$script_dir/$runtime_script" "$runtime_dir/scripts/$runtime_script"
done
/usr/bin/ditto "$script_dir/lib/common.sh" "$runtime_dir/scripts/lib/common.sh"
/bin/chmod 755 "$runtime_dir/CodexDockQuotaFeed" "$runtime_dir/scripts"/*.sh

CODEX_DOCK_BADGE_ALLOW_RUNNING=$allow_running \
CODEX_DOCK_BADGE_APP="$app_path" \
CODEX_DOCK_BADGE_SUPPORT_ROOT="$support_root" \
  "$runtime_dir/scripts/patch-app.sh"

/usr/bin/launchctl bootout "$user_domain" "$feed_agent" 2>/dev/null || true
/usr/bin/launchctl bootout "$user_domain" "$update_agent" 2>/dev/null || true

/usr/bin/plutil -create xml1 "$feed_agent"
/usr/libexec/PlistBuddy -c 'Add :Label string com.local.codex-dock-quota-feed' "$feed_agent"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$feed_agent"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $runtime_dir/CodexDockQuotaFeed" "$feed_agent"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$feed_agent"
/usr/libexec/PlistBuddy -c 'Add :KeepAlive bool true' "$feed_agent"
/usr/libexec/PlistBuddy -c 'Add :ProcessType string Background' "$feed_agent"
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$feed_agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CODEX_DOCK_BADGE_APP string $app_path" "$feed_agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CODEX_DOCK_BADGE_OUTPUT string $output_path" "$feed_agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CODEX_DOCK_BADGE_STATUS string $status_path" "$feed_agent"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $logs_dir/CodexDockQuotaFeed.log" "$feed_agent"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $logs_dir/CodexDockQuotaFeed.error.log" "$feed_agent"

/usr/bin/plutil -create xml1 "$update_agent"
/usr/libexec/PlistBuddy -c 'Add :Label string com.local.codex-dock-quota-update-check' "$update_agent"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$update_agent"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $runtime_dir/scripts/notify-on-update.sh" "$update_agent"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$update_agent"
/usr/libexec/PlistBuddy -c 'Add :StartInterval integer 300' "$update_agent"
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$update_agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CODEX_DOCK_BADGE_APP string $app_path" "$update_agent"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:CODEX_DOCK_BADGE_SUPPORT_ROOT string $support_root" "$update_agent"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $logs_dir/CodexDockQuotaUpdateCheck.log" "$update_agent"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $logs_dir/CodexDockQuotaUpdateCheck.error.log" "$update_agent"

/usr/bin/launchctl bootstrap "$user_domain" "$feed_agent"
/usr/bin/launchctl bootstrap "$user_domain" "$update_agent"
/usr/bin/launchctl kickstart -k "$user_domain/com.local.codex-dock-quota-feed"

for _ in {1..20}; do
  [[ -s "$status_path" && -s "$output_path" ]] && break
  /bin/sleep 0.5
done

badge_info 'install=PASS_RESTART_REQUIRED'
badge_info "official_app=$app_path"
badge_info 'visible_codex_apps_expected=1'
badge_info 'next=完全退出并重新打开正式 Codex，然后运行 scripts/verify.sh'
