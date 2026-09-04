#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
source "$script_dir/lib/common.sh"

release_file="$repo_dir/compatibility/releases.tsv"
support_root=${CODEX_DOCK_BADGE_SUPPORT_ROOT:-"$HOME/Library/Application Support/Codex Dock Quota Badge"}
state_path="$support_root/installed-state.plist"
app_path=$(badge_find_app) || badge_die '找不到 /Applications/ChatGPT.app 或 /Applications/Codex.app'
asar_path="$app_path/Contents/Resources/app.asar"
node_path="$app_path/Contents/Resources/cua_node/bin/node"
icon_path="$app_path/Contents/Resources/icon-codex-light.png"

[[ $(/usr/bin/uname -s) == Darwin ]] || badge_die '仅支持 macOS'
[[ -f "$asar_path" ]] || badge_die "找不到 app.asar: $asar_path"
[[ -x "$node_path" ]] || badge_die "找不到 Codex 内置 Node: $node_path"
[[ -f "$icon_path" ]] || badge_die "找不到经过验证的 Codex 图标资源: $icon_path"
/usr/bin/xcrun --find swiftc >/dev/null || badge_die '缺少 Apple Command Line Tools (swiftc)'

version=$(badge_app_version "$app_path")
current_hash=$(badge_sha256 "$asar_path")
expected_original_hash=$(badge_supported_hash "$release_file" "$version")
[[ -n "$expected_original_hash" ]] || badge_die "Codex $version 尚未列入支持清单"

if [[ -f "$state_path" ]]; then
  installed_hash=$(badge_state_value "$state_path" PatchedAsarSHA256 || true)
  if [[ -n "$installed_hash" && "$installed_hash" == "$current_hash" ]]; then
    badge_info 'preflight=PASS_ALREADY_INSTALLED'
    badge_info "app=$app_path"
    badge_info "version=$version"
    badge_info "asar_sha256=$current_hash"
    exit 0
  fi
fi

[[ "$current_hash" == "$expected_original_hash" ]] \
  || badge_die "版本号匹配，但 app.asar 哈希不匹配；拒绝修改"
badge_original_is_openai_signed "$app_path" \
  || badge_die '当前 App 不是完整的 OpenAI 签名版本；拒绝修改'

temp_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/codex-badge-preflight.XXXXXX")
cleanup() {
  /bin/rm -rf "$temp_dir"
}
trap cleanup EXIT
/bin/cp "$asar_path" "$temp_dir/app.asar"
"$node_path" "$repo_dir/src/patch-app-asar.mjs" "$temp_dir/app.asar" >/dev/null

badge_info 'preflight=PASS'
badge_info "app=$app_path"
badge_info "version=$version"
badge_info "original_asar_sha256=$current_hash"
if badge_app_is_running "$app_path"; then
  badge_info 'app_running=yes'
else
  badge_info 'app_running=no'
fi
