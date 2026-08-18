#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

exec xcodebuild test \
  -project "$project_dir/disk_hog.xcodeproj" \
  -scheme disk_hog \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
