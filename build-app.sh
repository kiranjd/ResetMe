#!/bin/zsh
set -euo pipefail

readonly project_dir="${0:A:h}"
readonly raw_destination="${1:-$project_dir/dist/ResetMe.app}"
readonly destination="${raw_destination:a}"
readonly destination_parent="${destination:h}"
readonly destination_name="${destination:t}"
readonly backup="$destination_parent/.$destination_name.previous.$$"

if [[ "$destination_name" != *.app ]]; then
    print -u2 -r -- "destination must be a .app bundle"
    exit 64
fi

mkdir -p "$destination_parent"
readonly staging="$(mktemp -d "$destination_parent/.ResetMe.app.staging.XXXXXX")"
had_existing=false
installed=false

cleanup() {
    if [[ "$installed" != true && "$had_existing" == true && ! -e "$destination" && -e "$backup" ]]; then
        mv "$backup" "$destination"
    fi
    rm -rf "$staging"
}
trap cleanup EXIT

cd "$project_dir"
swift build -c release --product reset
readonly binary_dir="$(swift build -c release --show-bin-path)"

readonly sparkle_framework="$binary_dir/Sparkle.framework"
test -d "$sparkle_framework"

mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources" "$staging/Contents/Frameworks"
install -m 755 "$binary_dir/reset" "$staging/Contents/MacOS/reset"
ditto "$sparkle_framework" "$staging/Contents/Frameworks/Sparkle.framework"
install -m 644 "$project_dir/Assets/openai.ico" "$staging/Contents/Resources/openai.ico"
for provider in codex claude; do
    install -m 644 "$project_dir/Assets/ProviderIcon-$provider.png" "$staging/Contents/Resources/ProviderIcon-$provider.png"
done
for image in LeafTemplate.png LeafTemplate@2x.png; do
    install -m 644 "$project_dir/Assets/Brand/$image" "$staging/Contents/Resources/$image"
done
install -m 644 "$project_dir/Assets/ResetMe.icns" "$staging/Contents/Resources/ResetMe.icns"
install -m 644 "$project_dir/THIRD_PARTY_NOTICES.md" "$staging/Contents/Resources/THIRD_PARTY_NOTICES.md"
install -m 644 "$project_dir/Licenses/Sparkle-LICENSE" "$staging/Contents/Resources/Sparkle-LICENSE"
install -m 644 "$project_dir/Info.plist" "$staging/Contents/Info.plist"

plutil -lint "$staging/Contents/Info.plist" >/dev/null
test -x "$staging/Contents/MacOS/reset"
test -x "$staging/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
otool -L "$staging/Contents/MacOS/reset" | grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$staging/Contents/MacOS/reset" | grep -Fq '@loader_path/../Frameworks'

# Keep local preview identity stable across rebuilds.
# Release packaging retains its existing signing/notarization sequence.
preview_identity="${RESETME_PREVIEW_SIGN_IDENTITY:-}"
if [[ -z "$preview_identity" && "$destination" == "$project_dir/work/"* ]]; then
    preview_identity="Developer ID Application: Kiran Murthy Jd (MN4M99XHF7)"
fi
if [[ -n "$preview_identity" ]]; then
    preview_framework="$staging/Contents/Frameworks/Sparkle.framework"
    preview_version="$preview_framework/Versions/B"
    codesign --force --timestamp --options runtime --sign "$preview_identity" "$preview_version/XPCServices/Installer.xpc"
    codesign --force --timestamp --options runtime --preserve-metadata=entitlements --sign "$preview_identity" "$preview_version/XPCServices/Downloader.xpc"
    codesign --force --timestamp --options runtime --sign "$preview_identity" "$preview_version/Autoupdate"
    codesign --force --timestamp --options runtime --sign "$preview_identity" "$preview_version/Updater.app"
    codesign --force --timestamp --options runtime --sign "$preview_identity" "$preview_framework"
    codesign --force --timestamp --options runtime --sign "$preview_identity" "$staging"
    codesign --verify --deep --strict --verbose=2 "$staging"
fi

if [[ -e "$destination" || -L "$destination" ]]; then
    mv "$destination" "$backup"
    had_existing=true
fi
mv "$staging" "$destination"
installed=true

if [[ "$had_existing" == true ]]; then
    if [[ -x /usr/bin/trash ]]; then
        /usr/bin/trash "$backup"
    else
        print -u2 -r -- "Previous bundle retained at $backup"
    fi
fi

print -r -- "$destination"
