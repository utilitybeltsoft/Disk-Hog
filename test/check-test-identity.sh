#!/usr/bin/env bash

# Fail before launching a test host if its app identity regresses.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
settings="$(xcodebuild -project "$project_dir/disk_hog.xcodeproj" \
    -target disk_hog -configuration Testing -showBuildSettings CODE_SIGNING_ALLOWED=YES)"
bundle_id="$(printf '%s\n' "$settings" | awk '$1 == "PRODUCT_BUNDLE_IDENTIFIER" && $2 == "=" { print $3 }')"
if [[ "$bundle_id" != "software.utilitybelt.diskhog.testhost" ]]; then
    echo "Refusing to run tests with unexpected host identity: $bundle_id" >&2
    exit 1
fi
echo "Verified isolated test host: $bundle_id"
