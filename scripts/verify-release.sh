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
readonly sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

plutil -lint "$plist" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")" == "ResetMe" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "local.jd.reset" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")" == "ResetMe.icns" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" == "14.0" ]]
test -x "$executable"
test -x "$sparkle"
test -f "$app/Contents/Resources/openai.ico"
test -f "$app/Contents/Resources/ResetMe.icns"
test -f "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
test -f "$app/Contents/Resources/Sparkle-LICENSE"
otool -L "$executable" | grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$executable" | grep -Fq '@loader_path/../Frameworks'

print -r -- "Verified archive structure, ResetMe metadata, and embedded Sparkle framework."
