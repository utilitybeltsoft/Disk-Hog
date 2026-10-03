# Disk Hog

A native macOS disk space analyzer with interactive treemaps, file and folder
rankings, and cleanup tools.

Disk Hog helps you see what is taking up space on your Mac. Scan a folder or
volume, explore its contents visually, and review selected items in a cleanup
queue before moving them to Finder Trash.

## Features

- Interactive treemaps with zoom, selection, and configurable colors.
- Folder Tree, Largest Files, and Largest Folders views, with up to 1,000 results
  in each ranked view.
- Physical and logical size reporting, with configurable package-content scanning.
- File information and Finder integration.
- A cleanup queue with confirmation and protected-path checks for important
  system and user folders, the running app, and Trash contents.
- Scan issue reporting for paths that could not be read.
- English, German, Spanish, French, and Italian interfaces.

Scans are snapshots, not continuous filesystem monitoring. Use **Re-scan** to
update them. Reported sizes do not necessarily equal reclaimable disk space.
Disk Hog does not offer an Empty Trash command.

## Full Disk Access

Disk Hog provides setup guidance when its access checks cannot establish access
to protected folders. The Settings button opens Full Disk Access in
**System Settings → Privacy & Security**. Enable Disk Hog and follow macOS's
Quit & Reopen prompt.

You can choose **Continue with Limited Access**. That choice is remembered, and
setup remains available through Help. Protected content may be skipped and disk
usage understated; scan warnings identify affected paths and reported errors.
Full Disk Access does not override every filesystem permission.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the scan pipeline, packed item storage,
and treemap rendering, with links to the implementation.

## Building from source

The app target is configured for macOS 14.6 or later. Development and the current
test suite use Xcode 26.3; test targets require macOS 15.7 or later.

```sh
git clone https://github.com/utilitybeltsoft/Disk-Hog.git
cd Disk-Hog
open disk_hog.xcodeproj
```

The checked-in project selects Utility Belt Software LLC's Developer ID signing
certificate. Other contributors need to configure their own signing identity
for runnable development builds. Keep a separate development bundle identifier
so a test build does not replace an installed release's privacy identity.

To compile the app without the maintainer's certificate:

```sh
xcodebuild build \
  -project disk_hog.xcodeproj -scheme disk_hog \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/unsigned CODE_SIGNING_ALLOWED=NO
```

This checks compilation; it does not produce a signed, notarized distribution.
The local installation script is intended for maintainers with the organization's
signing identity. See [release packaging](docs/licensing/RELEASES.md) for the
release workflow.

## Version identification

The 1.0.0 milestone is identified by the annotated Git tag `v1.0.0`.
About Disk Hog displays the version and the short commit hash embedded at build
time. Builds with uncommitted changes append `-modified`. No build date is shown.
The app retains its numeric macOS build number separately.

The build records the full revision in `Contents/Resources/BuildRevision.txt`.
Source archives made with `git archive` preserve the revision through
`.git-revision`; builds without revision information display only the version.

## Testing

With the required signing setup:

```sh
bash test/run-tests.sh --unit-only
bash test/run-tests.sh
bash test/run-coverage.sh --unit-only
```

The full suite includes UI automation against `/Applications/Disk Hog.app`.
Install the version to test, quit it before running the suite, and keep the
desktop unlocked. UI tests use the installed app; unit and integration tests use
an isolated test host.

See the [test guide](test/README.md) for signing, permissions, coverage, and
manual checks, and [session architecture](disk_hog/Models/ScanSessions/README.md)
for state ownership and asynchronous update boundaries.

## License and acknowledgements

Disk Hog is distributed under the [GNU General Public License, version 3](COPYING).
Copyright © 2026 Utility Belt Software LLC for its modifications and additions.

The app includes adaptations of
[Disk Inventory Z](https://github.com/danifunker/disk-inventory-z),
[Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x), and the
[TreeMapView framework](https://gitlab.com/tderlien/treemapview-framework),
with contributions by Tjark Derlien and Dani Sarfati.
See [third-party notices](THIRD-PARTY-NOTICES.txt) and the
[upstream lineage audit](docs/licensing/AUDIT.md) for attribution and the scope
of the licensing evidence. License and third-party notices are also available
offline in the app's About window.
