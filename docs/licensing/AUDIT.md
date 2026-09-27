# Upstream lineage and license audit

Audited 2026-09-27. This records the evidence examined, rather than claiming
that every asset or historical contribution has been independently cleared.

## Findings

Disk Hog incorporates adaptations of upstream implementations. GPLv3 is
the distribution basis for the combined application. Copyright notices
belong to the original authors as well as Utility Belt Software LLC for
its own modifications. Removing personal Git identities does not remove
third-party attribution obligations.

| Component | Evidence | License basis |
| --- | --- | --- |
| Filesystem scan and item construction | Historical `DiskInventoryZScanner.swift` at commit `2b2e316148f170041e53d886e029619abdbc23fc` maps statements to Z's `FileSystemDoc.m` and `FSItem.m`; current code is split across Scanner and Models/DiskItems. | Z's headers name Tjark Derlien (2003), Dani Sarfati (2026), and GPLv3 or later. Its filesystem extensions also carry Derlien's 2019 notices. |
| Treemap rendering and view behavior | The five annotated port snapshots at `378ece462ae7f39dd76d0a0eec5d61d9ede0845b` map Swift statements to `TMVCushionRenderer`, `TMVItem`, `TreeMapView`, and bitmap helpers. The current ridge calculations, lighting and color normalization preserve those implementations after refactoring. | Z declares GPLv3 at project level. Original TreeMapView distribution independently supplies a GPL grant; details below. |
| Linked libraries | App imports and Xcode target dependencies inspected; no Swift package products or bundled third-party frameworks/libraries were found. | Apple system frameworks; upstream dependencies are not automatically Disk Hog dependencies. |
| Other upstream vendor code | Z contains Omni replacement shims and CocoaTech helpers. | No wholesale inclusion or linked dependency found in Disk Hog. Do not label those entire components as included merely because Z uses them. This is not a proof excluding every adapted helper. |

Primary upstream references:

- [Disk Inventory Z](https://github.com/danifunker/disk-inventory-z):
  README, COPYING, BUILD.md, source headers and English credits.
- [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x):
  local source archive includes GPLv3 COPYING.
- [TreeMapView](https://gitlab.com/tderlien/treemapview-framework).
- [Original author's website](https://www.derlien.com/) declares Disk
  Inventory X GPL and credits KDirStat for the layout algorithm;
  [downloads](https://www.derlien.com/downloads/index.html) identifies both
  source repositories. This does not itself establish copied KDirStat code
  in Disk Hog; no separate KDirStat component was identified in this audit.

## TreeMapView's missing license file

The local modern TreeMapView ZIP has no standalone license and its headers
say “All rights reserved.” That alone does not establish a proprietary
license or override a separate grant. The original author's version 1.0
source DMG includes `readme.rtf`, dated 2004-12-6, explicitly granting GPL
use of the framework and its source, and `gpl.txt` containing GPLv2.

The README grant does not specify a GPL version number. GPLv2 section 9
permits choosing a published GPL version when the program does not specify
one. This supports selecting GPLv3 for the adaptation, together with Z's
explicit project license. This is the interpretation used here; the
unversioned grant must not be rewritten as an explicit original “v3 or
later” header. The inspected newer framework ZIP provides no separate
license statement for later edits.

The original README (including its warranty notice) and GPL text are
preserved unmodified under `upstream/`, and bundled with the app. The
GPLv2 document records the historical grant; it does not change the chosen
GPLv3 license for the combined application.

Evidence fingerprints (SHA-256):

- `TreeMapView 1.0 src (1).dmg`:
  `b4b963570cda5551d9c0059fac7f6f73fe8c17a1c03fda97939e42467f8ac1d9`
- `treemapview-framework-master.zip`:
  `906e532ea6ffe6629d6a7bdf675526173166b5076fd4324724bf1319aa82b980`
- Inspected Z `src/Source/FSItem.m`:
  `2992363181f04f8bf44e880cbea0ade54971c1b5175b63ee60392ca1aecf7023`

The local Z reference was a source snapshot; a precise upstream commit was
not established. These fingerprints identify the inspected evidence without
inventing an upstream revision.

## About wording

> Disk Hog
>
> Copyright © 2026 Utility Belt Software LLC.
>
> Includes code adapted from Disk Inventory Z, Disk Inventory X, and the
> TreeMapView framework, with contributions by Tjark Derlien and Dani Sarfati.
>
> Free software under the GNU General Public License, version 3. You may
> redistribute and modify it under that license. Provided without warranty.

The About interface offers **License**, **Third-Party Notices**, and
**Source for This Version**. The first two open bundled documents offline;
the third is enabled only when `DiskHogSourceURL` is configured in the app's
Info.plist with an HTTPS URL for the actual release source. Until then, the
About window explains that source downloads arrive with the public release.

## Scope still requiring evidence

The app icon source images and localizations are present in the repository,
but their authorship cannot be conclusively determined from the current
files. Do not credit upstream translators or declare all assets original
without verifying their provenance. Likewise, rewritten Git author fields
are not evidence of original authorship. Future imported components need
their own license review and notices.

See RELEASES.md for source availability and packaging work remaining before
public distribution. No claim of a completed release compliance review is
made by adding these documents.
