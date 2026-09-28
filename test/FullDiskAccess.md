# Full Disk Access setup

The application delegate composes the service, observable setup model and panel.
Source views and commands receive the model; filesystem and workflow tests inject
probe, Settings and termination actions. `ScanSourceProvider` shares candidate
locations and error classification but evaluates only the selected source.

The service reports evidence rather than querying permission status. Directory
access attempts also give macOS an opportunity to register the running app in the
Full Disk Access list. Registration is OS behavior and requires signed-app manual
verification; it is not guaranteed by the existence of a Settings URL.

Launch checks gate scan entry points until complete. Denied protected access
presents setup and gates new scans; an inconclusive result permits scanning with
an explanatory banner. Existing scans are not cancelled by an activation check.
There is no saved “permission granted” flag. Activation rechecks update the state,
and a transition to available refreshes source metadata. Opening Settings never
counts as approval. Rechecks do not restart scans or change their freshness.

The setup model coalesces repeated requests and discards superseded results.
The panel is nonmodal, stays visible outside the app, and permits termination for
System Settings' Quit & Reopen action. It controls only its own window; it does
not use Accessibility, AppleScript, or TCC database modifications to manipulate
System Settings. If the deep link fails, the panel provides written navigation.

See `test/README.md` for automated coverage and the outstanding live release checks.

## Launch prompt sequencing regression

Volume discovery performs filesystem access, so it must wait for the initial
access check and remain paused while the Full Disk Access guidance is shown.
The source model checks this gate for initial loads, manual refreshes, and
mount/unmount/rename events, including immediately before a queued load starts.
Discovery resumes when setup permits it. Folder-picker construction occurs on
user request, not as launch warm-up.

For live verification, use a signed app without Full Disk Access and with an
external volume attached. Launch without clicking anything: Full Disk Access
setup should appear without a concurrent removable-volume prompt caused by
source discovery. Grant access, quit/reopen as requested by macOS, and verify
sources load. Also verify an inconclusive check still allows discovery, and
closing optional guidance resumes it. macOS may still ask for volume access
when the app legitimately starts accessing volumes; this fix does not grant
that permission or suppress system dialogs. Automated tests use injected loaders
and do not reset the user's privacy grants.
