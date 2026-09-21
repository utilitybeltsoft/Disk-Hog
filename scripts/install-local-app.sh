#!/usr/bin/env bash

# Build and install Disk Hog for local use. This intentionally relies on Xcode's
# normal local signing; it does not require Developer ID distribution signing or
# notarization. Full Disk Access remains a user-controlled macOS setting.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

configuration="${CONFIGURATION:-Debug}"
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

xcodebuild build \
    -project "$project_dir/disk_hog.xcodeproj" \
    -scheme disk_hog \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_path"

if [[ ! -d "$build_app_path" ]]; then
    echo "Build completed but the expected app bundle was not found: $build_app_path" >&2
    exit 1
fi

# Replacing the complete bundle prevents stale resources or executable files from
# a previous build remaining in /Applications. The fixed, explicit destination
# keeps this destructive operation tightly scoped.
if [[ -e "$install_path" ]]; then
    sudo rm -rf "$install_path"
fi
sudo ditto "$build_app_path" "$install_path"

echo "Installed $installed_app_name at $install_path"
echo "To scan protected locations, enable Disk Hog once in System Settings > Privacy & Security > Full Disk Access, then relaunch it."

if [[ "${OPEN_AFTER_INSTALL:-1}" == "1" ]]; then
    open "$install_path"
fi
