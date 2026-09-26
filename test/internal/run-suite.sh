#!/usr/bin/env bash

# Shared implementation for normal and coverage runs. Never alter TCC or
# Gatekeeper state, strip quarantine attributes, or sign the installed app.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/../.." && pwd)"
coverage=NO
selection=all
for arg in "$@"; do
  case "$arg" in
    --coverage) coverage=YES ;;
    --unit-only|--ui-only)
      if [[ "$selection" != all ]]; then
        echo "Choose only one of --unit-only and --ui-only." >&2
        exit 2
      fi
      selection="$arg"
      ;;
    *) echo "Usage: $0 [--coverage] [--unit-only | --ui-only]" >&2; exit 2 ;;
  esac
done

bash "$project_dir/test/check-test-identity.sh"
derived_data="$project_dir/build/signed-tests"
result_dir="$(mktemp -d "${TMPDIR:-/tmp}/disk-hog-test-results.XXXXXX")"
result_bundle="$result_dir/results.xcresult"
echo "Test results: $result_bundle"
filter=(-only-testing:disk_hogTests -only-testing:disk_hogUITests)
case "$selection" in
  --unit-only) filter=(-only-testing:disk_hogTests) ;;
  --ui-only) filter=(-only-testing:disk_hogUITests) ;;
esac

xcodebuild build-for-testing -quiet \
  -project "$project_dir/disk_hog.xcodeproj" -scheme disk_hog \
  -configuration Testing -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" -enableCodeCoverage "$coverage" \
  "${filter[@]}" CODE_SIGNING_ALLOWED=YES

test_app="$derived_data/Build/Products/Testing/disk_hog.app"
runner="$derived_data/Build/Products/Testing/disk_hogUITests-Runner.app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$test_app/Contents/Info.plist")"
if [[ "$bundle_id" != software.utilitybelt.diskhog.testhost ]]; then
  echo "Refusing to launch unexpected test-host identity: $bundle_id" >&2
  exit 1
fi
codesign --verify --deep --strict "$test_app"
if [[ "$selection" != --unit-only ]]; then
  codesign --verify --deep --strict "$runner"
  echo "Verified signed UI automation helper: $runner"
  echo "The UI test will control /Applications/Disk Hog.app; quit it first."
  echo "macOS may require Developer Tools permission and Enable UI Automation authentication."
fi

# Launch the manifest from this build, not a bundle resolved by Launch Services
# or an old test product in the default DerivedData directory.
shopt -s nullglob
manifests=("$derived_data"/Build/Products/*.xctestrun)
if [[ "${#manifests[@]}" -ne 1 ]]; then
  echo "Expected one current test manifest; found ${#manifests[@]} in $derived_data/Build/Products." >&2
  exit 1
fi
status=0
xcodebuild test-without-building -quiet \
  -xctestrun "${manifests[0]}" -destination 'platform=macOS' \
  -resultBundlePath "$result_bundle" "${filter[@]}" || status=$?

# A failing test must not hide the result path or the available coverage report.
if [[ "$status" -eq 0 ]]; then
  echo "Test result: PASS"
else
  echo "Test result: FAIL (exit $status)"
fi
echo "Test results: $result_bundle"
if [[ "$coverage" == YES && -d "$result_bundle" ]]; then
  if xcrun xccov view --report "$result_bundle" > "$result_dir/coverage-details.txt"; then
    xcrun xccov view --report --json "$result_bundle" | xcrun swift "$script_dir/CoverageSummary.swift" \
      || echo "Coverage summary unavailable; see the detailed report." >&2
    echo "Detailed coverage: $result_dir/coverage-details.txt"
  else
    echo "No coverage report is available for this run." >&2
  fi
fi
if [[ "$status" -ne 0 ]]; then
  echo "Tests failed (exit $status). Inspect the result above; no security settings were changed." >&2
fi
exit "$status"
