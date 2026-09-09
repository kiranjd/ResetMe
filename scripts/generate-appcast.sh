#!/bin/zsh
set -euo pipefail

readonly project_dir="${0:A:h:h}"
readonly version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
readonly archives_dir="${1:-$project_dir/dist/appcast}"
readonly download_url_prefix="${2:-https://github.com/kiranjd/ResetMe/releases/download/v$version/}"
readonly generate_appcast="$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
readonly key_account="${SPARKLE_KEY_ACCOUNT:-resetme.sparkle}"
readonly private_key_file="${SPARKLE_PRIVATE_KEY_FILE:-}"

if [[ "$download_url_prefix" != https://* ]]; then
    print -u2 -r -- "download URL prefix must use HTTPS"
    exit 64
fi

if [[ ! -x "$generate_appcast" ]]; then
    print -u2 -r -- "Sparkle tools are unavailable; run swift package resolve and a release build first"
    exit 69
fi

if ! find "$archives_dir" -maxdepth 1 -type f \( -name '*.zip' -o -name '*.dmg' \) -print -quit | grep -q .; then
    print -u2 -r -- "archives directory contains no zip or dmg release"
    exit 66
fi

signing_args=(--account "$key_account")
if [[ -n "$private_key_file" ]]; then
    signing_args=(--ed-key-file "$private_key_file")
fi

"$generate_appcast" \
    "${signing_args[@]}" \
    --download-url-prefix "$download_url_prefix" \
    --link "https://github.com/kiranjd/ResetMe" \
    "$archives_dir"

print -r -- "$archives_dir/appcast.xml"
