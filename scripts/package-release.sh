#!/usr/bin/env bash

# Publish local download artifacts only after Apple accepts and staples both
# the application and its DMG. Credentials stay in the caller's Keychain.
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
version="${VERSION:-1.0.0}"
ref="${RELEASE_REF:-v$version}"
output_dir="${OUTPUT_DIR:-$(dirname "$project_dir")}"
signing_identity="Developer ID Application: Utility Belt Software LLC (YC7DSJ848Y)"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a saved notarytool Keychain profile name.}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain three numeric components, such as 1.0.0." >&2
    exit 1
fi
revision="$(git -C "$project_dir" rev-parse --verify "$ref^{commit}")"
source_url="https://github.com/utilitybeltsoft/Disk-Hog/archive/$revision.tar.gz"

# Fail before building or creating download artifacts if credentials do not work.
echo "Checking notarization credentials for profile: $NOTARY_PROFILE"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/disk-hog-release.XXXXXX")"
mount_path=""
stage="preparing source"
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$mount_path" ]]; then
        hdiutil detach "$mount_path" >/dev/null || true
    fi
    if [[ "$status" -ne 0 ]]; then
        echo "Packaging failed during $stage. No unverified DMG was published." >&2
        echo "Build products and diagnostics: $work_dir" >&2
    fi
    exit "$status"
}
trap cleanup EXIT

source_name="Disk-Hog-$version-source.tar.gz"
dmg_name="Disk-Hog-$version.dmg"
checksum_name="Disk-Hog-$version.sha256"
src="$work_dir/Disk-Hog-$version"
staging="$work_dir/staging"
app="$staging/Disk Hog.app"
dmg="$work_dir/$dmg_name"
echo "Packaging $version from $revision"
git -C "$project_dir" archive --format=tar.gz --prefix="Disk-Hog-$version/" \
    --output="$work_dir/$source_name" "$revision"
tar -xzf "$work_dir/$source_name" -C "$work_dir"

stage="building the signed universal Release app"
xcodebuild build -project "$src/disk_hog.xcodeproj" -scheme disk_hog \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work_dir/build" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
    DISKHOG_SOURCE_URL="$source_url" > "$work_dir/build.log" 2>&1
mkdir -p "$staging/Documentation"
ditto "$work_dir/build/Build/Products/Release/disk_hog.app" "$app"
ln -sfn /Applications "$staging/Applications"

stage="validating app metadata and signing"
python3 - "$app" "$version" "$revision" "$source_url" <<'PY'
import pathlib, plistlib, sys
app, version, revision, source_url = sys.argv[1:]
app = pathlib.Path(app)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
for key, expected in {
    'CFBundleName': 'Disk Hog',
    'CFBundleIdentifier': 'software.utilitybelt.diskhog',
    'CFBundleShortVersionString': version,
    'DiskHogSourceURL': source_url,
}.items():
    if info.get(key) != expected:
        raise SystemExit(f'Unexpected {key}: {info.get(key)!r}; expected {expected!r}')
if (app / 'Contents/Resources/BuildRevision.txt').read_text().strip() != revision:
    raise SystemExit('The built app does not identify the release source commit.')
for name in ['COPYING', 'THIRD-PARTY-NOTICES.txt', 'TreeMapView-1.0-readme.rtf', 'TreeMapView-1.0-GPL.txt']:
    if not (app / 'Contents/Resources' / name).is_file():
        raise SystemExit(f'Missing bundled notice: {name}')
PY
lipo "$app/Contents/MacOS/disk_hog" -verify_arch x86_64 arm64
codesign --verify --deep --strict "$app"
codesign --verify -R '=anchor apple generic and certificate leaf[subject.OU] = "YC7DSJ848Y"' "$app"
# Catch distribution-signing mistakes before uploading to Apple.
for arch in x86_64 arm64; do
    codesign --display --verbose=4 --arch "$arch" "$app" > "$work_dir/signature-$arch.txt" 2>&1
    if ! grep -q '^Timestamp=' "$work_dir/signature-$arch.txt"; then
        echo "Missing secure signing timestamp for $arch." >&2
        exit 1
    fi
    codesign --display --entitlements - --xml --arch "$arch" "$app" > "$work_dir/entitlements-$arch.plist" 2>/dev/null
    python3 - "$work_dir/entitlements-$arch.plist" <<'PYTHON'
import pathlib, plistlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
entitlements = plistlib.loads(raw) if raw.strip() else {}
if entitlements.get('com.apple.security.get-task-allow', False):
    raise SystemExit('Distribution app must not allow debugger attachment.')
PYTHON
done

notarize() {
    local artifact="$1" label="$2" result="$work_dir/$2-notarization.json"
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$result"
    if ! python3 - "$result" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print(f"Notarization {result.get('id', 'unknown')}: {result.get('status', 'unknown')}")
sys.exit(0 if result.get('status') == 'Accepted' else 1)
PY
    then
        local submission_id
        submission_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$result")"
        xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" \
            "$work_dir/$label-notarization-log.json" || true
        return 1
    fi
}

# Apple's ticket lookup can briefly lag an Accepted submission. Retry only
# stapling/validation; still fail closed after three attempts.
stapler_with_retry() {
    local attempt
    for attempt in 1 2 3; do
        if xcrun stapler "$@"; then
            return 0
        fi
        if [[ "$attempt" -lt 3 ]]; then
            echo "Ticket operation failed; retrying in 10 seconds ($attempt/3)." >&2
            sleep 10
        fi
    done
    return 1
}

stage="notarizing and stapling the app"
ditto -c -k --keepParent "$app" "$work_dir/application.zip"
notarize "$work_dir/application.zip" app
stapler_with_retry staple "$app"
stapler_with_retry validate "$app"
spctl --assess --type execute --verbose=2 "$app"

cp "$src/COPYING" "$src/THIRD-PARTY-NOTICES.txt" \
    "$src/docs/licensing/upstream/TreeMapView-1.0-readme.rtf" \
    "$src/docs/licensing/upstream/TreeMapView-1.0-GPL.txt" "$staging/Documentation/"
cat > "$staging/Documentation/Source.txt" <<SOURCE
Disk Hog $version
Source commit: $revision
Matching source download: $source_url
A matching $source_name is provided alongside this DMG.
Build instructions are in README.md in the source archive.
SOURCE
cat > "$staging/Documentation/Installation.txt" <<'INSTALL'
Drag Disk Hog.app onto Applications, then open it from Applications.
Supports Intel and Apple Silicon Macs running macOS 14.6 or later.
For protected locations, follow the app's Full Disk Access guidance.
INSTALL

stage="creating and signing the DMG"
hdiutil create -volname "Disk Hog $version" -srcfolder "$staging" -format UDZO -fs HFS+ "$dmg"
codesign --sign "$signing_identity" --timestamp "$dmg"
stage="notarizing and stapling the DMG"
notarize "$dmg" dmg
stapler_with_retry staple "$dmg"
stapler_with_retry validate "$dmg"
codesign --verify "$dmg"
hdiutil verify "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

stage="verifying the mounted download"
mount_path="$work_dir/mounted"
hdiutil attach -readonly -nobrowse -mountpoint "$mount_path" "$dmg"
codesign --verify --deep --strict "$mount_path/Disk Hog.app"
stapler_with_retry validate "$mount_path/Disk Hog.app"
spctl --assess --type execute --verbose=2 "$mount_path/Disk Hog.app"
[[ "$(cat "$mount_path/Disk Hog.app/Contents/Resources/BuildRevision.txt")" == "$revision" ]]
[[ "$(readlink "$mount_path/Applications")" == /Applications ]]
hdiutil detach "$mount_path"
mount_path=""

stage="publishing verified local artifacts"
(cd "$work_dir" && shasum -a 256 "$dmg_name" "$source_name" > "$checksum_name")
mkdir -p "$output_dir"
# All signing, notarization, and mounted-image checks have passed at this point.
for name in "$source_name" "$checksum_name" "$dmg_name"; do
    mv -f "$work_dir/$name" "$output_dir/$name"
done
echo "Notarized and verified: $output_dir/$dmg_name"
echo "Matching source and SHA-256 checksums are in $output_dir"
echo "Build and notarization records: $work_dir"
