#!/bin/zsh
set -euo pipefail

readonly project_dir="${0:A:h:h}"
readonly dist_dir="$project_dir/dist"
readonly app="$dist_dir/ResetMe.app"
readonly dmg="$dist_dir/ResetMe.dmg"
readonly sparkle_zip="$dist_dir/ResetMe-macos.zip"
readonly appcast="$dist_dir/appcast.xml"
readonly version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
readonly sign_identity="${RESETME_SIGN_IDENTITY:-Developer ID Application: Kiran Murthy Jd (MN4M99XHF7)}"
readonly notary_profile="${RESETME_NOTARY_PROFILE:-resetme-notary}"
readonly work_dir="$(mktemp -d "${TMPDIR:-/tmp}/resetme-release.XXXXXX")"
readonly framework="$app/Contents/Frameworks/Sparkle.framework"
readonly sparkle_version="$framework/Versions/B"
readonly generate_keys="$project_dir/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

replace_output() {
    local source="$1"
    local destination="$2"
    if [[ -e "$destination" || -L "$destination" ]]; then
        /usr/bin/trash "$destination"
    fi
    mv "$source" "$destination"
}

create_dmg() {
    local source_app="$1"
    local destination="$2"
    local root="$work_dir/dmg-root"

    rm -rf "$root"
    mkdir -p "$root"
    ditto "$source_app" "$root/ResetMe.app"
    ln -s /Applications "$root/Applications"
    hdiutil create \
        -volname ResetMe \
        -srcfolder "$root" \
        -format UDZO \
        -imagekey zlib-level=9 \
        "$destination" >/dev/null
    codesign --force --timestamp --sign "$sign_identity" "$destination"
}

if ! security find-identity -v -p codesigning | grep -Fq "\"$sign_identity\""; then
    print -u2 -r -- "Developer ID identity is unavailable: $sign_identity"
    exit 69
fi

if ! xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null 2>&1; then
    print -u2 -r -- "Notarytool profile is unavailable: $notary_profile"
    exit 69
fi

"$project_dir/build-app.sh" >/dev/null

codesign --force --timestamp --options runtime --sign "$sign_identity" \
    "$sparkle_version/XPCServices/Installer.xpc"
codesign --force --timestamp --options runtime --preserve-metadata=entitlements --sign "$sign_identity" \
    "$sparkle_version/XPCServices/Downloader.xpc"
codesign --force --timestamp --options runtime --sign "$sign_identity" \
    "$sparkle_version/Autoupdate"
codesign --force --timestamp --options runtime --sign "$sign_identity" \
    "$sparkle_version/Updater.app"
codesign --force --timestamp --options runtime --sign "$sign_identity" "$framework"
codesign --force --timestamp --options runtime --sign "$sign_identity" "$app"

codesign --verify --deep --strict --verbose=2 "$app"

readonly provisional_dmg="$work_dir/ResetMe-provisional.dmg"
create_dmg "$app" "$provisional_dmg"
xcrun notarytool submit "$provisional_dmg" --wait --keychain-profile "$notary_profile"

xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"

readonly pending_zip="$work_dir/ResetMe-macos.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$pending_zip"

readonly pending_dmg="$work_dir/ResetMe.dmg"
create_dmg "$app" "$pending_dmg"
xcrun notarytool submit "$pending_dmg" --wait --keychain-profile "$notary_profile"
xcrun stapler staple "$pending_dmg"
xcrun stapler validate "$pending_dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$pending_dmg"

replace_output "$pending_zip" "$sparkle_zip"
replace_output "$pending_dmg" "$dmg"

readonly appcast_dir="$dist_dir/appcast"
mkdir -p "$appcast_dir"
ditto "$sparkle_zip" "$appcast_dir/ResetMe-macos.zip"
readonly private_key="$work_dir/resetme-sparkle-private-key"
umask 077
"$generate_keys" --account resetme.sparkle -x "$private_key" >/dev/null
SPARKLE_PRIVATE_KEY_FILE="$private_key" "$project_dir/scripts/generate-appcast.sh" "$appcast_dir" \
    "https://github.com/kiranjd/ResetMe/releases/download/v$version/" >/dev/null
ditto "$appcast_dir/appcast.xml" "$work_dir/appcast.xml"
replace_output "$work_dir/appcast.xml" "$appcast"

(
    cd "$dist_dir"
    shasum -a 256 ResetMe.dmg ResetMe-macos.zip appcast.xml > SHA256SUMS
)
chmod 644 "$dmg" "$sparkle_zip" "$appcast" "$dist_dir/SHA256SUMS"

print -r -- "$dmg"
print -r -- "$sparkle_zip"
print -r -- "$appcast"
