# Treemap performance diagnostics

In macOS Console, select this Mac, start streaming, and filter by **Subsystem**
`software.utilitybelt.diskhog` and **Category** `TreemapPerformance`. Resize a
completed scan window. The messages use the default/notice level, so enabling
debug or info messages is not required. These logs are available in Release too.

From Terminal:

```sh
log stream --style compact --predicate 'subsystem == "software.utilitybelt.diskhog" AND category == "TreemapPerformance"'
```

For recent activity, replace `stream` with `show --last 10m`.

Each asynchronous render has a unique `render=` ID, allowing simultaneous scan
windows and cancelled renders to be distinguished. Its start message includes
the reason, build configuration, dimensions, and display scale. Root paths are
private; timings and counts are public.

Render starts and phase completions also include `activeScans`,
`activeTraversalWorkers`, and `scanStages`. Active scans cover the normal scan
session workflow through presentation preparation; traversal workers count
held traversal permits across budgets (including refresh operations), not
threads currently executing on a CPU. These are instantaneous snapshots, not
peak counts or measurements of CPU usage.

For scan start, stage changes, and completion/cancellation/failure, include
the `ScanPerformance` category too, or filter only on the subsystem:

```sh
log stream --style compact --predicate 'subsystem == "software.utilitybelt.diskhog"'
```

Scan events have unique `scan=` IDs and no filesystem paths. Packaging percentage
updates do not each produce a log: only stage changes do. Workers are counted
without per-subtree log messages. Compare the same completed window at the same
sizes with zero, one, and multiple scans active; use Release for every run.
These logs establish overlap, but a CPU profile/sample is still needed to
distinguish scheduling, locking, and memory pressure.

| Phase | Measures |
| --- | --- |
| `worker-queue` | Delay before background work starts |
| `geometry` | Walking visible portions of the tree and placing rectangles |
| `identity-index` | Building item, path, and parent lookup tables |
| `hit-index` | Building the spatial index for pointer selection |
| `navigation-index` | Building the spatial index for keyboard navigation |
| `layout-total` | Geometry and all indexes combined |
| `raster` | Shading rectangles into bitmap pixels |
| `main-queue` | Delay waiting to install the result on the UI thread |
| `install` | Bitmap conversion, state/cache update, and ready callback |
| `request-total` | End-to-end time through installation, not screen presentation |

`layout-total` includes its preceding geometry/index phases: do not add them
twice. Cancellation, stale-result, and cache-hit events explain renders that do
not install new pixels. Cache hits outside a render use `render=direct`.

## Repeatable synthetic benchmark

Run from the repository root. The benchmark generates an in-memory tree; it
does not scan the filesystem. It renders at two widths using production model,
layout, indexing, and rasterization code, and emits the same Console messages.

```sh
xcrun swiftc -Onone -D DEBUG -parse-as-library \
  disk_hog/Models/DiskItems/*.swift disk_hog/Treemap/*.swift \
  disk_hog/Diagnostics/{TreemapPerformance,ScanActivity}.swift scripts/treemap-benchmark.swift \
  -o /private/tmp/diskhog-treemap-debug
/private/tmp/diskhog-treemap-debug 100000

xcrun swiftc -O -whole-module-optimization -parse-as-library \
  disk_hog/Models/DiskItems/*.swift disk_hog/Treemap/*.swift \
  disk_hog/Diagnostics/{TreemapPerformance,ScanActivity}.swift scripts/treemap-benchmark.swift \
  -o /private/tmp/diskhog-treemap-release
/private/tmp/diskhog-treemap-release 100000
```

This flat synthetic tree is useful for controlled comparisons, not a substitute
for measuring the user's actual scan. The local installer defaults to Debug;
use `CONFIGURATION=Release ./scripts/install-local-app.sh` after quitting Disk
Hog to measure an optimized application build. It still uses local signing.

## Focused regression checks

### Folder chooser cold-start timing

The app constructs and configures its reusable `NSOpenPanel` 500 ms after showing
the source window. It does not present a dialog or change focus during preparation.
If the user requests the chooser first, that request constructs the same panel;
the scheduled preparation then does nothing. This moves construction cost, not
necessarily the system file picker's directory/sidebar loading cost.

In Console, filter subsystem `software.utilitybelt.diskhog` and category
`FolderChooserPerformance`. Notice-level messages are available from the normally
launched app; no debugger is required. No chosen paths are logged.

- `prepare started/finished`: construction/configuration cost, with `after-launch`
  or `user-request` identifying which path triggered it.
- `open requested`: request ID and whether a prepared panel already existed.
- `begin returned`: synchronous cost of calling `NSOpenPanel.begin`.
- `panel became key`: elapsed time from request to AppKit's key-window notification.
  This is not a first-pixel measurement or proof that directory contents are ready.
  If macOS does not deliver this notification for the panel, do not infer zero delay.
- `panel completed`: selection or cancellation, not opening latency.

Compare the first opening after a fresh launch with a second opening. Also check
an immediate click during launch and repeated clicks while the picker is open.
Verify preparation never shows a window or steals focus. A cold-launch comparison
in the installed app is still required before claiming a measured speedup.

### Treemap checks

```sh
xcrun swiftc -O -whole-module-optimization -parse-as-library \
  disk_hog/Models/DiskItems/*.swift disk_hog/Treemap/*.swift \
  disk_hog/Diagnostics/{TreemapPerformance,ScanActivity}.swift \
  scripts/treemap-cancellation-check.swift -o /private/tmp/diskhog-cancellation-check
/private/tmp/diskhog-cancellation-check

xcrun swiftc -O -parse-as-library disk_hog/Diagnostics/ScanActivity.swift \
  disk_hog/Scanner/ScanResourceBudget.swift scripts/scan-activity-check.swift \
  -o /private/tmp/diskhog-scan-activity-check
/private/tmp/diskhog-scan-activity-check

xcrun swiftc -O -whole-module-optimization -parse-as-library \
  disk_hog/Models/DiskItems/*.swift disk_hog/Treemap/*.swift \
  disk_hog/Diagnostics/{TreemapPerformance,ScanActivity}.swift \
  scripts/treemap-metadata-check.swift -o /private/tmp/diskhog-metadata-check
/private/tmp/diskhog-metadata-check
```

Treemap folder and kind checks must use packed snapshot fields, not reconstruct
`itemMetadata`. Reconstructing a file URL without its known directory flag can
cause Foundation to query the live filesystem. The metadata check covers
directory/package/link combinations, nil and empty kind names, and special
items; it also verifies reconstructed URLs use the stored directory flag.
