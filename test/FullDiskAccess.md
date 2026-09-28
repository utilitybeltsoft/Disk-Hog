# Full Disk Access setup

The application delegate composes the service, observable setup model and panel.
Source views and commands receive the model; filesystem and workflow tests inject
probe, Settings and termination actions. `ScanSourceProvider` shares candidate
locations and error classification but evaluates only the selected source.

The service reports evidence rather than querying permission status. Directory
access attempts also give macOS an opportunity to register the running app in the
Full Disk Access list. Registration is OS behavior and requires signed-app manual
verification; it is not guaranteed by the existence of a Settings URL.

Launch completes the access check before presenting any setup window. The source window
is not constructed until access is confirmed or the user proceeds. Denied access
gates new scans until the user explicitly chooses Continue with Limited Access.
An inconclusive result leaves guidance visible with that same option. Only an
explicit Continue with Limited Access choice is saved in UserDefaults.
Quitting, opening Settings, or merely viewing/dismissing guidance does not save
that choice. On later launches the app still checks access; a saved choice allows
limited mode without automatically reopening setup. Help can always reopen it.
The earlier `fullDiskAccessGuidanceShown` preference is deliberately ignored;
it does not establish that the user chose limited access. A source banner and
existing scan-issue warnings explain limitations.
Readable volume roots remain selectable even when protected descendants are
denied. Existing scans are not cancelled by an activation check.
There is no saved “permission granted” flag. Activation rechecks outside the setup dialog update the state,
and a transition to available refreshes source metadata. Opening Settings never
counts as approval. Rechecks do not restart scans or change their freshness.

The setup model coalesces pending requests. Help and Settings requests wait for
an active check to finish before showing guidance. Once guidance is visible,
The Settings button opens its destination directly and activation does not probe.
There is no checking text, spinner, or Check Again button; granting access follows
the macOS Quit & Reopen flow.
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
Discovery resumes when setup permits it. Folder-picker warm-up waits until an
access check has finished and guidance is closed, then gives the source window
500 ms to settle. A new check or reopened guidance cancels the pending warm-up.
The panel is prepared only once and is reused if the user opened it first.

For live verification, use a signed app without Full Disk Access and with an
external volume attached. Launch without clicking anything: Full Disk Access
setup should appear without a concurrent removable-volume prompt caused by
source discovery. Grant access, quit/reopen as requested by macOS, and verify
sources load. Also verify an inconclusive check still allows discovery, and
closing optional guidance resumes it. macOS may still ask for volume access
when the app legitimately starts accessing volumes; this fix does not grant
that permission or suppress system dialogs. Automated tests use injected loaders
and do not reset the user's privacy grants.

The setup instructions always show the missing-app steps and the bundled example
image supplied for this app. The window fits its content without scrolling and is geometrically centered in
the screen’s visible area, including after its content changes. Continue with
Limited Access sits on the right;
Quit appears below on the left.
Verify initial launch shows no source/inspector window until proceeding, that
limited mode can scan a readable volume, and that Show Affected Items reports
unreadable paths. Full Disk Access does not override all filesystem permissions.

The button immediately after the example image opens Privacy & Security in
System Settings. Verify that destination and the Settings-open failure message.
No separate Open Full Disk Access or Finder-reveal button is offered in the setup dialog.
