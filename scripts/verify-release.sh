#!/bin/zsh
set -euo pipefail

readonly archive="${1:-}"

if [[ -z "$archive" || ! -f "$archive" ]]; then
    print -u2 -r -- "usage: scripts/verify-release.sh path/to/ResetMe-<version>-macos.zip"
    exit 64
fi

readonly verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/resetme-release.XXXXXX")"
cleanup() {
    rm -rf "$verification_dir"
}
trap cleanup EXIT

ditto -x -k "$archive" "$verification_dir"
readonly app="$verification_dir/ResetMe.app"
readonly plist="$app/Contents/Info.plist"
readonly executable="$app/Contents/MacOS/reset"

plutil -lint "$plist" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")" == "ResetMe" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "local.jd.reset" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")" == "ResetMe.icns" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" == "14.0" ]]
test -x "$executable"
test -f "$app/Contents/Resources/openai.ico"
test -f "$app/Contents/Resources/ResetMe.icns"

print -r -- "Verified archive structure and ResetMe bundle metadata."
