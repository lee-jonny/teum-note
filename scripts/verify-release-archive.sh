#!/bin/bash
set -euo pipefail

archive=${1:?Pass the path to the published ZIP}
version=${2:?Pass the expected bundle version}
directory=$(mktemp -d "${TMPDIR:-/tmp}/teum-app.XXXXXX")
trap 'rm -rf "$directory"' EXIT

ditto -x -k "$archive" "$directory"
app="$directory/Teum.app"
plist="$app/Contents/Info.plist"
plutil -lint "$plist"

check() {
    if [[ "$1" != "$2" ]]; then
        printf '%s: expected %s, got %s\n' "$3" "$2" "$1" >&2
        return 1
    fi
}

check "$(plutil -extract CFBundleIdentifier raw "$plist")" "com.teum.notes" "Bundle identifier"
check "$(plutil -extract CFBundleShortVersionString raw "$plist")" "$version" "Bundle version"
check "$(plutil -extract CFBundleExecutable raw "$plist")" "Teum" "Bundle executable"
check "$(lipo -archs "$app/Contents/MacOS/Teum")" "arm64" "Architecture"
codesign --verify --deep --strict "$app"
