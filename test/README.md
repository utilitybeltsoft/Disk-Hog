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
It prints the result-bundle location even when tests fail. Both commands print
passed, failed, and skipped counts. The summary
identifies the selected test scope and warns about skipped tests. Counts come
from Xcode's reported tests; excluded/disabled tests and individual parameterized
iterations are not included in those counts. Unavailable counts are reported
explicitly, never interpreted as zero, and reporting does not change the test
runner's exit status. Coverage runs also
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

All configurations explicitly select the organization certificate
`Developer ID Application: Utility Belt Software LLC (YC7DSJ848Y)`. This
certificate and its private key must be available in Keychain. Automatic
identity selection is disabled to avoid falling back to a personal certificate.
Local test runs do not require notarization. Do not disable signing: the UI-test
runner must be signed after Xcode assembles it, or Gatekeeper can kill it before
tests connect.

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

## Accessibility and localization checks

Unit tests check treemap accessibility selection/actions, shipped plural forms,
translation completeness and format-argument preservation. The single
`Localizable.xcstrings` catalog remains the translation source; provide translator
comments for ambiguous metadata and accessibility strings. Static-literal checks
are a guardrail, not a Swift parser or proof that every runtime string is localized.

Before release, use VoiceOver and keyboard navigation on a small fixture scan:

- Reach the treemap, hear the selected name/size/path, invoke directional actions,
  zoom and return, and open the selected item's context menu. Compare with the
  Files table; the treemap exposes its selection rather than every rectangle.
- Tab through breadcrumbs with keyboard navigation enabled and verify visible
  focus and the current-folder announcement. Check selected inspector tabs.
- Queue two identically named files from different folders. Verify checkbox names,
  path/size/status hints, checked state and all queue actions without a mouse.
- Check scan completion, cancellation, failure and cleanup results for discoverable
  status and sensible focus. Check increased contrast, reduced motion and long
  translated labels. Verify one-item and multiple-item counts in each language.

These manual checks are not performed by the unit-test runner.


## Full Disk Access onboarding

`FullDiskAccessService` attempts shallow directory listings under the current
user's Library. It reads no file contents and does not query or modify TCC's
permission database. These are access observations, not a definitive permission
API: two readable candidates provide positive evidence; protected-access denial
opens setup; missing candidates, ordinary POSIX permissions and unexpected errors
can leave the result inconclusive. Inconclusive checks do not block scanning.
Source preflight uses the same candidates and error classification, scoped to
folders within the selected source.

The Settings button performs another access check before opening the documented
Full Disk Access URL, allowing macOS to record the requesting application. The
application delegate skips the new launch workflow in the isolated Testing host.
Permission regression tests inject probe results and Settings/termination actions;
they do not change grants or open System Settings. The setup panel is nonmodal,
permits system-requested termination and stays visible when the app is inactive.

Manual release verification remains necessary on each supported macOS version:

1. Use a freshly signed development app identity on a disposable account/VM with
   no existing Full Disk Access entry. Do not reset the installed production
   app's grant just to run this check, and do not launch an unbundled binary from
   Terminal (permission attribution may differ).
2. Launch the app without access. Verify setup, unavailable scan commands,
   keyboard focus, VoiceOver reading order, and Quit Disk Hog / Command-Q.
3. Choose Open Full Disk Access. Verify the pane opens and Disk Hog is already
   listed. This OS-level registration behavior is **not** proven by unit tests.
   If absent, inspect the probe behavior before release; confirm the manual-add
   disclosure and Show Disk Hog in Finder reveal the running app bundle.
4. Enable the app and accept macOS's Quit & Reopen. Verify the panel does not
   block termination, the relaunched app can scan, and sources are refreshed.
5. Revisit without enabling access; the app must not infer a grant just because
   Settings opened. Verify Check Again and missing-entry instructions.
6. Test an existing grant, revocation, a home with missing probe directories,
   ordinary folder permission denial, and Settings opening failure. Verify an
   inconclusive result permits continued use with an explanatory source banner.
7. Check German, Spanish, French and Italian layouts, the expanded disclosure,
   multiple displays, and that the instruction panel can be moved clear of the
   System Settings controls.

At implementation time, automated tests cover the state machine and service;
fresh-entry registration and the live Quit & Reopen flow have not been verified.
