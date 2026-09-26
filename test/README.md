# Test hosts and Full Disk Access

Use `bash test/run-tests.sh` or `bash test/run-coverage.sh`. Both check the
test-host identity before launching tests and explicitly select Testing.
The checked-in shared scheme also selects Testing for Xcode's Test action.

| Build | App bundle identifier |
| --- | --- |
| Testing | software.utilitybelt.diskhog.testhost |
| Debug (ordinary development) | software.utilitybelt.diskhog.development |
| Release / local installation | software.utilitybelt.diskhog |

The local installer explicitly selects the production identity, verifies
Apple signing from our development team, and checks that the replacement
satisfies the installed app's designated requirement before replacing it.
This preserves the local Debug installation workflow without sharing its
privacy identity with unsigned test builds.

Unsigned test hosts previously used the installed app's bundle identifier.
TCC logs confirmed that running one replaced the stored Full Disk Access
identity with its code hash; the installed, signed app then failed that check.
Do not run old test products or old .xctestrun files from before this isolation.
Build fresh with Testing; never override the test host's bundle identifier to
the production identifier or run tests using Release.

For manual testing:

```sh
xcodebuild test -project disk_hog.xcodeproj -scheme disk_hog \
  -configuration Testing -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Development and test builds intentionally do not inherit installed Disk Hog's
Full Disk Access. Tests requiring protected files must not assume it is granted.
The fix does not repair a permission already invalidated: if needed, remove
the installed Disk Hog entry and add /Applications/Disk Hog.app again in
System Settings > Privacy & Security > Full Disk Access, then relaunch it.
Do not reset the TCC database. A deliberate signing-certificate migration is
separate work; the installer stops rather than silently changing that identity.
