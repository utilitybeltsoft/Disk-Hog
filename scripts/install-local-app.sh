#!/usr/bin/env bash

# Build and install Disk Hog for local use with the project's organization-named
# Developer ID certificate. Local installation does not perform notarization.
# Full Disk Access remains a user-controlled macOS setting.

set -Eeuo pipefail

stage="initialization"
trap 'echo "Installation failed during $stage (line $LINENO)." >&2' ERR

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

configuration="${CONFIGURATION:-Debug}"
case "$configuration" in
    Debug|Release) ;;
    *) echo "Only Debug or Release may be installed as Disk Hog." >&2; exit 1 ;;
esac
derived_data_path="${DERIVED_DATA_PATH:-/private/tmp/disk-hog-local-install}"
# The Xcode target still builds as `disk_hog.app`, but the user-facing installed
# app must use the product name "Disk Hog.app".
build_app_name="disk_hog.app"
installed_app_name="Disk Hog.app"
build_app_path="$derived_data_path/Build/Products/$configuration/$build_app_name"
install_path="/Applications/$installed_app_name"

if pgrep -x "disk_hog" >/dev/null 2>&1; then
    echo "Disk Hog is running. Quit it, then run this script again." >&2
    exit 1
fi

stage="building $configuration from $project_dir"
echo "Building $configuration from $project_dir"
echo "Build output: $build_app_path"
xcodebuild build \
    -project "$project_dir/disk_hog.xcodeproj" \
    -scheme disk_hog \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_path" \
    DISKHOG_APP_BUNDLE_IDENTIFIER=software.utilitybelt.diskhog \
    INFOPLIST_KEY_CFBundleDisplayName="Disk Hog"

if [[ ! -d "$build_app_path" ]]; then
    echo "Build completed but the expected app bundle was not found: $build_app_path" >&2
    exit 1
fi

stage="validating the built app"
# Check the generated app, not just Xcode's build settings: arbitrary
# INFOPLIST_KEY settings are not necessarily emitted into the bundle.
built_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$build_app_path/Contents/Info.plist")"
source_url="$(/usr/libexec/PlistBuddy -c 'Print :DiskHogSourceURL' "$build_app_path/Contents/Info.plist")"
if [[ "$built_name" != "Disk Hog" || "$source_url" != https://* ]]; then
    echo "Built app has unexpected name or source metadata; refusing installation." >&2
    exit 1
fi
built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$build_app_path/Contents/Info.plist")"
built_revision="$(cat "$build_app_path/Contents/Resources/BuildRevision.txt")"
echo "Verified app name: $built_name"
echo "Version: $built_version; revision: $built_revision"
echo "Source URL: $source_url"

# Refuse to replace the installed app with an isolated test/development host or
# an unsigned/ad-hoc build, which would invalidate its privacy identity.
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$build_app_path/Contents/Info.plist")"
if [[ "$bundle_id" != "software.utilitybelt.diskhog" ]]; then
    echo "Refusing to install unexpected bundle identity: $bundle_id" >&2
    exit 1
fi
codesign --verify --deep --strict "$build_app_path"
codesign --verify -R '=anchor apple generic and certificate leaf[subject.OU] = "YC7DSJ848Y"' "$build_app_path"

# Preserve the existing designated requirement (the identity macOS remembers).
# A deliberate signing-identity migration needs a separate, explicit workflow.
if [[ -d "$install_path" ]]; then
    existing_requirement="$(codesign -d -r- "$install_path" 2>/dev/null)"
    existing_requirement="${existing_requirement#designated => }"
    if [[ -z "$existing_requirement" ]]; then
        echo "Cannot establish the installed app's signing identity; leaving it untouched." >&2
        exit 1
    fi
    if ! codesign --verify -R "=$existing_requirement" "$build_app_path"; then
        if [[ "${ALLOW_SIGNING_IDENTITY_MIGRATION:-0}" != "1" ]]; then
            echo "The new build changes the installed signing identity; leaving it untouched." >&2
            echo "For an intentional migration, rerun with ALLOW_SIGNING_IDENTITY_MIGRATION=1." >&2
            exit 1
        fi
        echo "Migrating signing identity within the verified Apple developer team."
        echo "macOS may require enabling Full Disk Access again after this migration."
    fi
fi

# Replacing the complete bundle prevents stale resources or executable files from
# a previous build remaining in /Applications. The fixed, explicit destination
# keeps this destructive operation tightly scoped.
stage="installing to $install_path"
echo "Installing to $install_path (sudo may reuse cached authorization)."
sudo -v
if [[ -e "$install_path" ]]; then
    sudo rm -rf "$install_path"
fi
sudo ditto "$build_app_path" "$install_path"

stage="verifying the installed app"
codesign --verify --deep --strict "$install_path"
if ! diff -qr "$build_app_path" "$install_path"; then
    echo "Installed app differs from the build; refusing to launch it." >&2
    exit 1
fi

echo "Installed and verified $installed_app_name at $install_path"
echo "To scan protected locations, enable Disk Hog once in System Settings > Privacy & Security > Full Disk Access, then relaunch it."

if [[ "${OPEN_AFTER_INSTALL:-1}" == "1" ]]; then
    open "$install_path"
fi
