#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

bash "$script_dir/check-test-identity.sh"

exec xcodebuild test \
  -project "$project_dir/disk_hog.xcodeproj" \
  -scheme disk_hog \
  -configuration Testing \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES
