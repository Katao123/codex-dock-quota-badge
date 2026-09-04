#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
source "$script_dir/lib/common.sh"

release_file="$repo_dir/compatibility/releases.tsv"
support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
backup_root="$support_root/backups"
state_path="$support_root/installed-state.plist"
app_path=$(badge_find_app) || badge_die '找不到正式 Codex App'
plist_path="$app_path/Contents/Info.plist"
asar_path="$app_path/Contents/Resources/app.asar"
executable_name=$(badge_app_executable "$app_path")
main_path="$app_path/Contents/MacOS/$executable_name"
signature_path="$app_path/Contents/_CodeSignature/CodeResources"
root_code_resources_path="$app_path/Contents/CodeResources"
node_path="$app_path/Contents/Resources/cua_node/bin/node"
patcher="$repo_dir/src/patch-app-asar.mjs"
entitlements="$repo_dir/config/codex.entitlements"
allow_running=${CODEX_DOCK_BADGE_ALLOW_RUNNING:-0}

[[ -f "$asar_path" && -x "$node_path" ]] || badge_die '正式 App 结构不符合预期'
if badge_app_is_running "$app_path" && [[ "$allow_running" != 1 ]]; then
  badge_die '正式 Codex 正在运行；仅可由安装编排器显式设置 CODEX_DOCK_BADGE_ALLOW_RUNNING=1'
fi

current_hash=$(badge_sha256 "$asar_path")
if [[ -f "$state_path" ]]; then
  installed_hash=$(badge_state_value "$state_path" PatchedAsarSHA256 || true)
  if [[ -n "$installed_hash" && "$installed_hash" == "$current_hash" ]]; then
    badge_info 'patch=ALREADY_INSTALLED'
    exit 0
  fi
fi

version=$(badge_app_version "$app_path")
expected_hash=$(badge_supported_hash "$release_file" "$version")
[[ -n "$expected_hash" ]] || badge_die "不支持 Codex $version"
[[ "$current_hash" == "$expected_hash" ]] || badge_die 'app.asar 哈希不在支持清单中'
badge_original_is_openai_signed "$app_path" || badge_die '修改前的 App 不是完整 OpenAI 签名版本'

/bin/mkdir -p "$backup_root"
backup_dir="$backup_root/$version-${current_hash[1,12]}"
if [[ ! -f "$backup_dir/backup-complete" ]]; then
  /bin/mkdir -p \
    "$backup_dir/Contents/Resources" \
    "$backup_dir/Contents/MacOS" \
    "$backup_dir/Contents/_CodeSignature"
  /usr/bin/ditto "$asar_path" "$backup_dir/Contents/Resources/app.asar"
  /usr/bin/ditto "$plist_path" "$backup_dir/Contents/Info.plist"
  /usr/bin/ditto "$main_path" "$backup_dir/Contents/MacOS/$executable_name"
  /usr/bin/ditto "$signature_path" "$backup_dir/Contents/_CodeSignature/CodeResources"
  /usr/bin/ditto "$root_code_resources_path" "$backup_dir/Contents/CodeResources"
  /usr/bin/codesign -dv --verbose=4 "$app_path" 2> "$backup_dir/original-codesign.txt"
  /usr/bin/plutil -create xml1 "$backup_dir/manifest.plist"
  /usr/bin/plutil -insert Version -string "$version" "$backup_dir/manifest.plist"
  /usr/bin/plutil -insert ExecutableName -string "$executable_name" "$backup_dir/manifest.plist"
  /usr/bin/plutil -insert OriginalAsarSHA256 -string "$current_hash" "$backup_dir/manifest.plist"
  /usr/bin/plutil -insert CreatedAt -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$backup_dir/manifest.plist"
  /usr/bin/touch "$backup_dir/backup-complete"
fi

[[ $(badge_sha256 "$backup_dir/Contents/Resources/app.asar") == "$current_hash" ]] \
  || badge_die '备份哈希校验失败'

stage_dir=$(/usr/bin/mktemp -d "$support_root/stage.XXXXXX")
patch_started=0
restore_after_failure() {
  local exit_code=$?
  if [[ "$patch_started" == 1 ]]; then
    print -u2 '补丁失败，正在恢复已校验的官方文件'
    /usr/bin/ditto "$backup_dir/Contents/Resources/app.asar" "$asar_path" || true
    /usr/bin/ditto "$backup_dir/Contents/Info.plist" "$plist_path" || true
    /usr/bin/ditto "$backup_dir/Contents/MacOS/$executable_name" "$main_path" || true
    /usr/bin/ditto "$backup_dir/Contents/_CodeSignature/CodeResources" "$signature_path" || true
    /usr/bin/ditto "$backup_dir/Contents/CodeResources" "$root_code_resources_path" || true
  fi
  /bin/rm -rf "$stage_dir"
  exit "$exit_code"
}
trap restore_after_failure EXIT

/bin/cp "$asar_path" "$stage_dir/app.asar"
/usr/bin/ditto "$plist_path" "$stage_dir/Info.plist"
patch_result=$("$node_path" "$patcher" "$stage_dir/app.asar")
header_hash=$("$node_path" -e 'const value=JSON.parse(process.argv[1]); process.stdout.write(value.headerHash)' "$patch_result")
/usr/libexec/PlistBuddy \
  -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $header_hash" \
  "$stage_dir/Info.plist"

patch_started=1
/usr/bin/ditto "$stage_dir/app.asar" "$asar_path"
/usr/bin/ditto "$stage_dir/Info.plist" "$plist_path"
/usr/bin/codesign \
  --force \
  --sign - \
  --options runtime \
  --entitlements "$entitlements" \
  "$app_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

patched_hash=$(badge_sha256 "$asar_path")
/usr/bin/plutil -create xml1 "$state_path"
/usr/bin/plutil -insert AppPath -string "$app_path" "$state_path"
/usr/bin/plutil -insert Version -string "$version" "$state_path"
/usr/bin/plutil -insert OriginalAsarSHA256 -string "$current_hash" "$state_path"
/usr/bin/plutil -insert PatchedAsarSHA256 -string "$patched_hash" "$state_path"
/usr/bin/plutil -insert BackupDirectory -string "$backup_dir" "$state_path"
/usr/bin/plutil -insert PatchedAt -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$state_path"

patch_started=0
/bin/rm -rf "$stage_dir"
trap - EXIT
badge_info 'patch=PASS'
badge_info "app=$app_path"
badge_info "version=$version"
badge_info "backup=$backup_dir"
badge_info "patched_asar_sha256=$patched_hash"
