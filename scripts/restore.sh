#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source "$script_dir/lib/common.sh"

support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
state_path="$support_root/installed-state.plist"
[[ -f "$state_path" ]] || badge_die '没有找到已安装状态；无需恢复或备份记录已丢失'
app_path=$(badge_state_value "$state_path" AppPath)
backup_dir=$(badge_state_value "$state_path" BackupDirectory)
original_hash=$(badge_state_value "$state_path" OriginalAsarSHA256)
executable_name=$(badge_state_value "$backup_dir/manifest.plist" ExecutableName)

if badge_app_is_running "$app_path"; then
  badge_die '请先完全退出正式 Codex，再执行恢复'
fi

for relative_path in \
  'Contents/Resources/app.asar' \
  'Contents/Info.plist' \
  "Contents/MacOS/$executable_name" \
  'Contents/_CodeSignature/CodeResources' \
  'Contents/CodeResources'; do
  [[ -f "$backup_dir/$relative_path" ]] || badge_die "备份不完整: $relative_path"
done
[[ $(badge_sha256 "$backup_dir/Contents/Resources/app.asar") == "$original_hash" ]] \
  || badge_die '备份哈希不匹配，拒绝恢复'

/usr/bin/ditto "$backup_dir/Contents/Resources/app.asar" "$app_path/Contents/Resources/app.asar"
/usr/bin/ditto "$backup_dir/Contents/Info.plist" "$app_path/Contents/Info.plist"
/usr/bin/ditto "$backup_dir/Contents/MacOS/$executable_name" "$app_path/Contents/MacOS/$executable_name"
/usr/bin/ditto "$backup_dir/Contents/_CodeSignature/CodeResources" "$app_path/Contents/_CodeSignature/CodeResources"
/usr/bin/ditto "$backup_dir/Contents/CodeResources" "$app_path/Contents/CodeResources"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
[[ $(badge_sha256 "$app_path/Contents/Resources/app.asar") == "$original_hash" ]] \
  || badge_die '恢复后的哈希不匹配'
badge_original_is_openai_signed "$app_path" || badge_die '恢复后未通过 OpenAI 签名检查'
/bin/rm -f "$state_path"
badge_info 'restore=PASS'
badge_info "official_app=$app_path"
badge_info "backup_preserved=$backup_dir"
