# Snapshot freshness

Each scan window displays a permanent freshness strip with an absolute local
date/time, “Not updated automatically,” and a Re-scan button. Re-scan targets
the session's entire source, not the selected item or treemap zoom. It uses the
existing full-scan path, including clearing the old results while scanning.

`SnapshotFreshness` records successful data acquisitions independently of
`completedAt` (which remains the existing operation/render timing field).
Whole-scan data is dated when accepted, before the treemap finishes rendering.
Details expose the start–finish interval; a scan is not an atomic filesystem
snapshot. Skipped-item provenance is retained and existing Scan Issues warnings
remain visible. Freshness does not imply completeness.

Partial refreshes record their actual refreshed path and interval without
advancing the whole-scan date. A refresh that falls back to the scan root is a
whole scan. A successful whole refresh clears the partial-refresh annotation.
Direct deletion only reconciles data and does not advance freshness; cleanup's
existing successful root refresh does. Presentation changes do not advance it.
Failed/cancelled operations do not advance successful timestamps. Historical
timestamps remain available when a full rescan clears the displayed results;
the details explicitly explain this distinction.

The button is disabled while scanning, updating the tree, or initially preparing
the treemap. No duplicate refresh is queued. The existing Cancel Scan action
remains available during full scans. Window ownership is direct, not inferred
from a global active-window command. No monitoring, automatic refresh, relative
age timer, or arbitrary stale threshold is added.

## Validation

September 25, 2026: unsigned Release build, standalone model regression check,
and the focused `ScanSessionWorkerIntegrationTests` Xcode suite passed. The full
application test suite was not run. Interactive checks below remain outstanding.

Standalone model regression check:

```sh
xcrun swiftc -module-cache-path /private/tmp/diskhog-freshness-module-cache \
  -parse-as-library disk_hog/Models/ScanSessions/SnapshotFreshness.swift \
  scripts/snapshot-freshness-check.swift -o /private/tmp/snapshot-freshness-check
/private/tmp/snapshot-freshness-check
```

Lifecycle regression tests are in `ScanSessionWorkerIntegrationTests`, including
freshness before rendering, window isolation, partial and failed refreshes,
and cancellation of a whole refresh. Run that suite with the Xcode test target.

Interactive acceptance checks:

- At minimum window width, the Re-scan button stays visible and the status wraps.
- The timestamp details and button are accessible by keyboard/VoiceOver.
- Refresh while zoomed into a child scans the entire original source.
- Two scan windows keep independent timestamps, failures, and refresh actions.
- Partial refresh displays its annotation and correct path in details.
- Failed/cancelled refreshes retain the previous successful timestamp, never
  label the attempt as a successful fresh snapshot, and permit a retry.
- Skipped-item warnings remain visible alongside recent timestamps.
- Resizing, zooming, changing size mode, and direct deletion do not alter the
  whole-scan timestamp; a successful root refresh after cleanup does.

The feature does not install or restart the copy in `/Applications`.
