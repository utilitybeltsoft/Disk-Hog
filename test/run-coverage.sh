#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
result_dir="$(mktemp -d)"
result_bundle="$result_dir/disk-hog-tests.xcresult"

xcodebuild test -quiet \
  -project "$project_dir/disk_hog.xcodeproj" \
  -scheme disk_hog \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO

xcrun xccov view --report "$result_bundle"
printf '\nCoverage result bundle: %s\n' "$result_bundle"
