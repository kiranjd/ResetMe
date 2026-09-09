#!/bin/zsh
set -euo pipefail

readonly project_dir="${0:A:h:h}"
readonly output_dir="$project_dir/dist"
readonly version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
readonly archive="$output_dir/ResetMe-$version-macos.zip"
readonly checksum="$archive.sha256"

"$project_dir/build-app.sh" >/dev/null
rm -f "$archive" "$checksum"

ditto -c -k --sequesterRsrc --keepParent "$output_dir/ResetMe.app" "$archive"
(
    cd "$output_dir"
    shasum -a 256 "${archive:t}" > "${checksum:t}"
)

"$project_dir/scripts/verify-release.sh" "$archive"

print -r -- "$archive"
print -r -- "$checksum"
print -r -- "No Developer ID signature and not notarized: this is a source-build artifact, not a public release candidate."
