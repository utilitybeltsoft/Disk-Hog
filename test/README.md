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

The shared runner builds in `build/signed-tests`, checks the actual app identity
and bundle signatures, and launches the generated test manifest explicitly.
It prints the result-bundle location even when tests fail. Coverage runs also
attempt to print the available coverage report after a test failure.
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
