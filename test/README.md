# Test hosts and Full Disk Access

Use `bash test/run-tests.sh` or `bash test/run-coverage.sh`. Both check the
test-host identity before launching tests and explicitly select Testing.
The checked-in shared scheme also selects Testing for Xcode's Test action.

Both scripts accept `--unit-only` or `--ui-only`; without either flag they
run both. For example:

```sh
bash test/run-tests.sh --unit-only
bash test/run-tests.sh --ui-only
bash test/run-coverage.sh --unit-only
```

Only `run-tests.sh` and `run-coverage.sh` are user-facing commands. Shared
implementation and report formatting live under `test/internal/`.

The shared runner builds in `build/signed-tests`, checks the actual app identity
and bundle signatures, and launches the generated test manifest explicitly.
It prints the result-bundle location even when tests fail. Coverage runs also
attempt to print a short coverage summary after a test failure. The full
file/function report is saved as `coverage-details.txt` alongside the result
bundle; the script prints its path. The summary separates app coverage from
test-code coverage and highlights safety-related files and the largest gaps.
A valid signature is necessary but does not guarantee Gatekeeper approval.
If macOS rejects the runner, do not keep retrying or move it to Trash:
inspect the security logs and resolve the requested Developer Tools permission.
Changing the app under test does not remove that helper's permission requirement.

UI tests explicitly launch `/Applications/Disk Hog.app`, not the app in the
Testing build directory. Install the version you want to test first and quit
it before running tests. The UI test refuses to interrupt an already running
installed app. It does not re-sign or replace that app or reset its saved
Inspector frame. Its existing Full Disk Access grant remains applicable.

Unit tests still use an isolated test host: they load test code and exercise
internal implementation directly. Coverage measures that instrumented host;
it does not measure the uninstrumented installed app used by UI tests.
The separate UI-test runner is an automation helper, not another Disk Hog
installation, and still requires macOS's development/automation permissions.

## Workflow regression coverage

The normal commands above include these workflow checks; no additional script
or manually prepared scan is needed:

- Hosted ranked views: load Largest Files and Largest Folders through their real
  asynchronous ranking tasks, keep size second, select rows in descending order,
  synchronize an external selection back to the table, invoke Show in Folder Tree,
  and zoom into the selected folder (or file's parent) and back out.
- Installed app: choose a generated folder, complete its scan, navigate from a
  ranked file to Folder Tree, queue and unqueue it without deleting it, add a file,
  and verify Re-scan finds it.
- Installed app: scan a generated folder with an unreadable child, verify Scan
  Issues reports it, restore its permissions, and verify Re-scan clears the issue.
- Existing safety integration tests: partial scans, lower-bound sizes, cancellation,
  simulated trash failures, and subtree reconciliation after mutation.

UI fixtures live in the automation helper's temporary directory and are removed
afterward. Their permissions are restored before cleanup. The UI workflows never
confirm Finder Trash or permanent deletion and never scan a user's volume.
They exercise the installed version, which may differ from the working tree.
Keep the desktop unlocked and avoid interacting with it during UI automation.
Tests terminate only the app instance they launched, including on failure.
The folder chooser targets its path field directly, verifies the entered path
and destination folder, and waits for the path sheet to close and Scan to become
actionable. A timeout stops that workflow and attaches the UI hierarchy with the
failed stage to the result bundle. Do not assist a stuck chooser: intervention
invalidates the automation result.

These checks do not establish Full Disk Access correctness or cover every
multi-window, resize, drag-and-drop, or destructive-confirmation workflow.

Both runners enable normal Xcode development signing. A local Apple Development
certificate and its private key for the project's configured team must be
available in Keychain. Developer ID distribution signing and notarization are
not required. Do not disable signing: the UI-test runner must be signed after
Xcode assembles it, or Gatekeeper can kill it before tests connect.

Run UI tests from an interactive, unlocked desktop. macOS may request
authentication to "Enable UI Automation"; approve that prompt to let the
tests control their test app. Leaving it unanswered can produce "Timed out
while enabling automation mode." This is separate from Full Disk Access.
The scripts do not change system security settings.

Safety regression tests use unique temporary directories under /private/tmp.
Injected trash operations move only fixture files to a simulated destination,
never to the user's Trash. Permission tests restrict and restore permissions
only on their own fixtures. These cover POSIX permission failures, not macOS
Full Disk Access. Protected-location scans of the installed app still need a
separate integration test with an explicitly chosen safe location.

| Build | App bundle identifier |
| --- | --- |
| Testing | software.utilitybelt.diskhog.testhost |
| Debug (ordinary development) | software.utilitybelt.diskhog.development |
| Release / local installation | software.utilitybelt.diskhog |

The local installer explicitly selects the production identity, verifies
Apple signing from our development team, and checks that the replacement
satisfies the installed app's designated requirement before replacing it.
This preserves the local Debug installation workflow without sharing its
privacy identity with development or test builds.

Unsigned test hosts previously used the installed app's bundle identifier.
TCC logs confirmed that running one replaced the stored Full Disk Access
identity with its code hash; the installed, signed app then failed that check.
Do not run old test products or old .xctestrun files from before this isolation.
Build fresh with Testing; never override the test host's bundle identifier to
the production identifier or run tests using Release.

For manual testing:

```sh
xcodebuild test -project disk_hog.xcodeproj -scheme disk_hog \
  -configuration Testing -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES
```

Development builds and the unit-test host intentionally do not inherit installed
Disk Hog's Full Disk Access. Unit tests must not assume it is granted.
The installed app exercised by UI tests uses its own existing permission.
The fix does not repair a permission already invalidated: if needed, remove
the installed Disk Hog entry and add /Applications/Disk Hog.app again in
System Settings > Privacy & Security > Full Disk Access, then relaunch it.
Do not reset the TCC database. A deliberate signing-certificate migration is
separate work; the installer stops rather than silently changing that identity.
