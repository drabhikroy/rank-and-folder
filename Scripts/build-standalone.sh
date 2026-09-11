#!/bin/bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
artifact_directory="$repository_root/dist"
configuration_file="$repository_root/Config/Base.xcconfig"
notary_profile="${NOTARY_PROFILE:-rankandfolder}"

do_notarize=0
for arg in "${@:-}"; do
    case "$arg" in
        "")           ;;
        --notarize)   do_notarize=1 ;;
        *) echo "Usage: Scripts/build-standalone.sh [--notarize]"; exit 2 ;;
    esac
done

marketing_version="$(
    awk -F ' *= *' '$1 == "MARKETING_VERSION" { print $2 }' \
        "$configuration_file" | xargs
)"

build_number="$(
    awk -F ' *= *' '$1 == "CURRENT_PROJECT_VERSION" { print $2 }' \
        "$configuration_file" | xargs
)"

if [[ -z "$marketing_version" || -z "$build_number" ]]; then
    echo "Could not read the app version from Config/Base.xcconfig."
    exit 1
fi

# Xcode keeps the internal product name without spaces. The distributed app
# uses the name shown to people in Finder and on the disk image.

app_name="Rank & Folder.app"
xcode_app_name="RankAndFolder.app"
final_executable_name="RankAndFolder"
volume_name="Rank & Folder ${marketing_version}"

zip_path="$artifact_directory/RankAndFolder-${marketing_version}-macOS.zip"
dmg_path="$artifact_directory/RankAndFolder-${marketing_version}.dmg"

temporary_directory="$(
    mktemp -d "${TMPDIR:-/tmp}/rankandfolder-build.XXXXXX"
)"

device=""

# Remove temporary files and detach the disk image if the script exits early.

cleanup() {
    if [[ -n "$device" ]]; then
        hdiutil detach "$device" -quiet 2>/dev/null \
            || hdiutil detach "$device" -force -quiet 2>/dev/null \
            || true
    fi

    rm -rf "$temporary_directory"
}

trap cleanup EXIT

mkdir -p "$temporary_directory/module-cache"

app_bundle="$temporary_directory/$app_name"

if ! command -v xcrun >/dev/null 2>&1; then
    echo "Xcode command-line tools are required to build Rank & Folder."
    exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "librsvg is required to generate the app icon."
    echo "Install it with Homebrew: brew install librsvg"
    exit 1
fi

rm -f "$zip_path" "$dmg_path"

mkdir -p \
    "$app_bundle/Contents/MacOS" \
    "$app_bundle/Contents/Resources" \
    "$artifact_directory"

# ---------------------------------------------------------------------------
# Application build
# ---------------------------------------------------------------------------

xcodebuild -quiet \
    -project "$repository_root/RankAndFolder.xcodeproj" \
    -scheme RankAndFolder \
    -configuration Release \
    -derivedDataPath "$temporary_directory/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS= \
    build

# Xcode builds RankAndFolder.app. The packaging steps below create the
# public-facing Rank & Folder.app separately.

built_app="$temporary_directory/DerivedData/Build/Products/Release/$xcode_app_name"

if [[ ! -d "$built_app" ]]; then
    echo "Xcode did not produce the expected application bundle:"
    echo "  $built_app"
    echo
    echo "Build products:"

    find "$temporary_directory/DerivedData/Build/Products" \
        -maxdepth 3 \
        -print 2>/dev/null || true

    exit 1
fi

built_info_plist="$built_app/Contents/Info.plist"

if [[ ! -f "$built_info_plist" ]]; then
    echo "The Xcode-built application does not contain an Info.plist:"
    echo "  $built_info_plist"
    exit 1
fi

# Read the executable name from the bundle Xcode produced instead of assuming
# that its executable name matches the distributed application name.

built_executable_name="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleExecutable" \
        "$built_info_plist"
)"

if [[ -z "$built_executable_name" ]]; then
    echo "Could not determine the executable name from the Xcode build."
    exit 1
fi

built_executable="$built_app/Contents/MacOS/$built_executable_name"

if [[ ! -f "$built_executable" ]]; then
    echo "Xcode reported the executable as:"
    echo "  $built_executable_name"
    echo
    echo "but that file was not found at:"
    echo "  $built_executable"
    echo
    echo "Contents of the MacOS directory:"

    ls -la "$built_app/Contents/MacOS" 2>/dev/null || true

    exit 1
fi

cp "$built_executable" \
    "$app_bundle/Contents/MacOS/$final_executable_name"

# ---------------------------------------------------------------------------
# Info.plist
# ---------------------------------------------------------------------------

cp \
    "$repository_root/Config/Standalone-Info.plist" \
    "$app_bundle/Contents/Info.plist"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $marketing_version" \
    "$app_bundle/Contents/Info.plist"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $build_number" \
    "$app_bundle/Contents/Info.plist"

# The executable in the finished application is always RankAndFolder.

if /usr/libexec/PlistBuddy \
    -c "Print :CFBundleExecutable" \
    "$app_bundle/Contents/Info.plist" >/dev/null 2>&1; then

    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleExecutable $final_executable_name" \
        "$app_bundle/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy \
        -c "Add :CFBundleExecutable string $final_executable_name" \
        "$app_bundle/Contents/Info.plist"
fi

# ---------------------------------------------------------------------------
# Application icon
# ---------------------------------------------------------------------------

# Build a complete iconset. Small sizes use simplified artwork so the folder
# rows remain clear in Finder, the Dock, and menus.

iconset="$temporary_directory/AppIcon.iconset"
mkdir -p "$iconset"

render_icon() {
    local source_svg="$1"
    local pixels="$2"
    local output_name="$3"

    rsvg-convert \
        -w "$pixels" \
        -h "$pixels" \
        "$repository_root/Assets/$source_svg" \
        -o "$iconset/$output_name"
}

render_icon AppIcon-Small.svg 16   icon_16x16.png
render_icon AppIcon-Small.svg 32   icon_16x16@2x.png
render_icon AppIcon-Small.svg 32   icon_32x32.png
render_icon AppIcon-Small.svg 64   icon_32x32@2x.png
render_icon AppIcon.svg       128  icon_128x128.png
render_icon AppIcon.svg       256  icon_128x128@2x.png
render_icon AppIcon.svg       256  icon_256x256.png
render_icon AppIcon.svg       512  icon_256x256@2x.png
render_icon AppIcon.svg       512  icon_512x512.png
render_icon AppIcon.svg       1024 icon_512x512@2x.png

iconutil \
    --convert icns \
    --output "$app_bundle/Contents/Resources/AppIcon.icns" \
    "$iconset"

xattr -cr "$app_bundle"

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------

# Prefer a real Developer ID Application identity over ad hoc signing. grep
# returns exit code 1 when nothing matches, which would stop the script under
# set -e, so the || true keeps that from happening.

developer_id="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' \
    | head -1 \
    | awk -F'"' '{print $2}' || true)"

if [[ "$do_notarize" -eq 1 && -z "$developer_id" ]]; then
    echo "--notarize requires a Developer ID Application identity."
    exit 1
fi

if [[ -n "$developer_id" ]]; then
    echo "Signing identity: $developer_id"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$developer_id" \
        "$app_bundle"
else
    echo "No Developer ID Application certificate found; signing ad hoc."
    echo "This build records the state of the finished bundle on this machine"
    echo "only. It does not carry Developer ID distribution or notarization."
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --sign - \
        "$app_bundle"
fi

codesign \
    --verify \
    --strict \
    --verbose=2 \
    "$app_bundle"

# ---------------------------------------------------------------------------
# Disk image
# ---------------------------------------------------------------------------

staging_directory="$temporary_directory/dmg"

mkdir -p "$staging_directory"

cp -R "$app_bundle" "$staging_directory/"
ln -s /Applications "$staging_directory/Applications"

# Give the mounted volume the application icon.

cp \
    "$app_bundle/Contents/Resources/AppIcon.icns" \
    "$staging_directory/.VolumeIcon.icns"

# Leave free space for Finder to write its window metadata.

staged_kilobytes="$(du -sk "$staging_directory" | cut -f1)"
image_kilobytes=$((staged_kilobytes + 51200))

writable_image="$temporary_directory/writable.dmg"

rm -f "$writable_image"

hdiutil create \
    -srcfolder "$staging_directory" \
    -volname "$volume_name" \
    -fs HFS+ \
    -format UDRW \
    -size "${image_kilobytes}k" \
    -ov \
    -quiet \
    "$writable_image"

attach_output="$(
    hdiutil attach \
        "$writable_image" \
        -readwrite \
        -noverify \
        -noautoopen
)"

device="$(
    echo "$attach_output" |
        grep -Eo '^/dev/disk[0-9]+' |
        head -1
)"

mount_point="/Volumes/$volume_name"

if [[ -z "$device" || ! -d "$mount_point" ]]; then
    echo "The disk image did not mount as expected."
    exit 1
fi

# Mark the disk image as having a custom volume icon.

SetFile -a C "$mount_point" 2>/dev/null || true

# Apply the Finder window arrangement when a desktop session is available.

if osascript \
    -e 'tell application "System Events" to get name' \
    >/dev/null 2>&1; then

    osascript >/dev/null 2>&1 <<APPLESCRIPT || \
        echo "Finder styling was unavailable, continuing with a plain window."
tell application "Finder"
    tell disk "$volume_name"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 800, 560}

        set view_options to the icon view options of container window
        set arrangement of view_options to not arranged
        set icon size of view_options to 128

        set position of item "$app_name" of container window to {150, 190}
        set position of item "Applications" of container window to {450, 190}

        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
else
    echo "No desktop session, so the disk image window keeps its default layout."
fi

sync

# Detach by device because Finder may still hold a reference to the volume.

hdiutil detach "$device" -quiet \
    || hdiutil detach "$device" -force -quiet

device=""

rm -f "$dmg_path"

hdiutil convert \
    "$writable_image" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$dmg_path" \
    -quiet

if [[ -n "$developer_id" ]]; then
    codesign --force --sign "$developer_id" --timestamp "$dmg_path"
else
    codesign --force --sign - --timestamp=none "$dmg_path"
fi

codesign \
    --verify \
    --strict \
    "$dmg_path"

# ---------------------------------------------------------------------------
# Notarization
# ---------------------------------------------------------------------------

# Staple the ticket to both the DMG and the app bundle still on disk. A zip
# cannot itself carry a staple, so the app bundle needs its own copy of the
# ticket before it gets zipped below, or the zip would arrive unstapled even
# though the DMG next to it is fine.

if [[ "$do_notarize" -eq 1 ]]; then
    echo "Submitting to Apple's notary service (profile: $notary_profile)..."
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler staple "$app_bundle"
    echo "Notarized and stapled"
fi

# ---------------------------------------------------------------------------
# Zip
# ---------------------------------------------------------------------------

# Keep a zip beside the disk image for scripts and package managers that need
# an archive they can unpack without mounting a disk image. Built from the
# app bundle after stapling, so a notarized build's zip carries the ticket
# the same as the disk image does.

ditto \
    -c \
    -k \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    --keepParent \
    "$app_bundle" \
    "$zip_path"

# ---------------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------------

(
    cd "$artifact_directory"

    shasum -a 256 \
        "$(basename "$zip_path")" \
        "$(basename "$dmg_path")" \
        > SHA256SUMS.txt
)

echo
echo "Built:"
echo "  $dmg_path"
echo "  $zip_path"
echo "  $artifact_directory/SHA256SUMS.txt"
echo

cat "$artifact_directory/SHA256SUMS.txt"
