# License and source packaging

For each public download, publish the signed, notarized DMG and a matching
source archive together on the same release page. GPLv3 section 6(d)
permits separate source downloads; users need not download source along
with the application. A source archive inside the DMG is optional.

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

Put a direct, permanent URL for this source archive next to the binary
download and in `Source.txt`. The app's About/Source action should use this
version-specific destination. A moving development branch is insufficient.
Keep the source available with the binaries; do not require a support request
or charge an additional fee for access.

## Before the first public release

- Configure the public release/source URL (there is currently no Git remote).
- Finish the About interface's offline license/notices access and source action.
- Verify contributor builds without the organization certificate; shared
  project defaults currently select that certificate.
- Finish and validate DMG packaging and notarization. No release pipeline is
  created by this documentation change.
- Complete asset-origin verification noted in AUDIT.md.
- Extract and build the source archive, check bundled notices in the installed
  app, and test both download URLs before publishing.

References: [GPLv3, sections 1, 4–6](https://www.gnu.org/licenses/gpl-3.0.html)
and [GNU distribution FAQ](https://www.gnu.org/licenses/gpl-faq.html).
