#!/bin/zsh

badge_die() {
  print -u2 -- "ERROR: $*"
  return 1
}

badge_info() {
  print -- "$*"
}

badge_find_app() {
  if [[ -n "${CODEX_DOCK_BADGE_APP:-}" ]]; then
    print -r -- "$CODEX_DOCK_BADGE_APP"
    return
  fi

  local candidate
  for candidate in '/Applications/ChatGPT.app' '/Applications/Codex.app'; do
    if [[ -d "$candidate" ]]; then
      print -r -- "$candidate"
      return
    fi
  done
  return 1
}

badge_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

badge_app_version() {
  badge_plist_value "$1" CFBundleShortVersionString
}

badge_app_executable() {
  badge_plist_value "$1" CFBundleExecutable
}

badge_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

badge_app_is_running() {
  local app_path=$1
  local executable
  executable=$(badge_app_executable "$app_path") || return 1
  local main_path="$app_path/Contents/MacOS/$executable"
  /bin/ps -axo command= | /usr/bin/awk -v target="$main_path" '
    $0 == target || index($0, target " ") == 1 { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

badge_supported_hash() {
  local release_file=$1
  local version=$2
  /usr/bin/awk -F '\t' -v wanted="$version" '$1 == wanted { print $2; exit }' "$release_file"
}

badge_original_is_openai_signed() {
  /usr/bin/codesign --verify --deep --strict "$1" >/dev/null 2>&1 \
    && /usr/bin/codesign -dv --verbose=4 "$1" 2>&1 \
      | /usr/bin/grep -F 'TeamIdentifier=2DC432GLL2' >/dev/null
}

badge_state_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}
