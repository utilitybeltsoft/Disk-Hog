# License and source packaging

Our release workflow is to publish a signed, notarized DMG and a matching
source archive on the same release page. Signing, notarization, checksums,
and this particular packaging layout are project choices, not GPL
requirements.

GPLv3 section 6(d) permits separate source downloads, with equivalent access
to the Corresponding Source at no further charge and clear directions next
to the binary download. The source may be on another server. Users need not
download it with the application; including a source archive inside the DMG
is optional.

Suggested release artifacts (substitute the actual version):

- `Disk-Hog-VERSION.dmg`
- `Disk-Hog-VERSION-source.tar.gz`
- checksums for both artifacts

The DMG may contain a `Documentation` folder with copies of `COPYING`,
`THIRD-PARTY-NOTICES.txt`, the two TreeMapView provenance notices, and
`Source.txt`. This folder is helpful but optional. Keep the license and
notices in the application bundle as well, so removing the DMG does not
remove them. Xcode copies the canonical repository documents into the
application's Resources directory; do not maintain separate edited copies.

## Build a notarized download

Run the release packager from the repository root with an existing notarytool
Keychain profile (the profile name is a nickname, not a password):

```sh
NOTARY_PROFILE=your-saved-profile bash scripts/package-release.sh
```

It defaults to `VERSION=1.0.0`, `RELEASE_REF=v1.0.0`, and the repository's parent
folder as `OUTPUT_DIR`. These can be overridden through environment variables.
It builds the selected commit from a source archive, rather than packaging a
possibly stale installed app or including uncommitted checkout changes.

The packager checks credentials before building, disables injected debugger
entitlements, and requests a secure signing timestamp. It verifies the universal
app's signature, distribution entitlements, timestamp, and embedded source
revision, submits the app to Apple, and staples
and validates its ticket. It then creates and signs the DMG, submits that DMG,
and staples and validates its ticket too. Both Apple submissions must report
`Accepted`. Gatekeeper assessment and a read-only mounted-image check must also
pass before the final DMG, matching source archive, and SHA-256 checksums are
placed in the output folder. A failed build or notarization leaves intermediate
files and diagnostics in the printed temporary directory; there is no option
to publish an unnotarized download through this script.

The About source link in this build targets the exact commit's GitHub archive.
Ensure that commit is available on the public remote before distributing the
artifacts. The local installation script remains separate from this download
packaging workflow.

## Source for the released binary

Create the source archive from the exact clean commit used for the binary.
Include the Swift source, assets, Xcode project, build/test scripts, license
and notices, and instructions identifying the required Xcode/macOS versions.
Include any additional generated inputs needed to rebuild it. Record the
version, build number, full commit ID and source archive checksum in the
release metadata. Check the extracted archive builds without the maintainer's
private signing identity. A Git archive can be a starting point, but it is
not sufficient if required inputs are untracked or supplied from elsewhere.

Do not include private signing keys, notarization credentials, local build
products, personal backups or the enclosing competitors directory. Apple
system frameworks and Xcode do not need to be repackaged. Full Git history
is not required; keep attribution and modification notices in the archive.

Put a direct, stable URL for this source archive next to the binary
download and in `Source.txt` if the optional documentation folder is shipped.
The app's About/Source action should use this version-specific destination. A moving development branch is insufficient.
Keep the source available with the binaries; do not require a support request
or charge an additional fee for access.

## Current repository status

As of 2026-10-03, `DiskHogSourceURL` points to
https://github.com/utilitybeltsoft/Disk-Hog in Debug, Release, and Testing.
Shared signing settings select the organization's Developer ID certificate.
For a public binary release, replace the repository URL with the matching
version-specific source archive described below.

## Version milestones

A version tag identifies a source commit; it does not publish a binary or claim
that packaging and notarization are complete. Set the marketing version, commit
the intended changes, validate that candidate, and create an annotated tag such
as `v1.0.0` at the validated commit. Do not move an existing release tag.

The build embeds the full Git revision in `BuildRevision.txt`. About shows the
short revision and marks locally modified checkouts. No build timestamp is used.
Record test results against the candidate commit before distributing a binary.

## Before the first public release

- Publish a version-specific source archive and configure its public URL.
- Set `DISKHOG_SOURCE_URL` for the release build to the stable
  HTTPS URL of its matching source archive. Verify the About source button
  opens that archive. Without this value the button is disabled; do not ship
  a public release with the development placeholder.
- Verify contributor builds without the organization certificate; shared
  project defaults currently select that certificate.
- Build the download with `scripts/package-release.sh` and verify that its
  notarization, stapling, and mounted-image checks all pass.
- Resolve the framework-revision licensing question described in
  [AUDIT.md](AUDIT.md#treemapview-license-evidence).
- Extract and build the source archive, check bundled notices in the installed
  app, and test both download URLs before publishing.

References: [GPLv3, sections 1, 4–6](https://www.gnu.org/licenses/gpl-3.0.en.html)
and [GNU distribution FAQ](https://www.gnu.org/licenses/gpl-faq.en.html).

## About window verification

Open About Disk Hog from the app menu. Verify version/build and attribution,
then open License and Third-Party Notices while offline. Confirm scrolling,
text selection/copying, window resizing, closing/reopening, and VoiceOver
reading. Notices must include the original TreeMapView warranty and GPLv2
text as well as current attribution. Check the layout in all five supported
languages. With no source URL, the source button is disabled with an
explanation; with release metadata configured, verify that it opens the
matching source.
The app validates URL syntax only, so an enabled button does not establish
source availability or a version match.
