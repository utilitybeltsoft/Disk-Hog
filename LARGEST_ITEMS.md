# Largest items

The scan window offers Folder Tree, Largest Files (the initial mode), and
Largest Folders. Rankings use the immutable scanned snapshot, never live file
metadata. Sizes follow the scan's physical/logical setting; they are not a
promise of reclaimable space.

The scan root itself and synthetic free/other-space nodes are excluded.
Folder sizes include descendants and overlap with ancestor totals. Symlinks
and aliases are not traversed. Opaque packages count as single file-like items;
when package contents were scanned, packages appear as folders and their
contents participate normally. Hard-link sizes use the scanner's accounting.

The ranked views always cover the entire scan. There are no scope, depth,
search, or Show More controls. Ordering is size descending, then path ascending.
The query engine retains its independently tested filtering capabilities,
but these are not exposed in the ranked-list interface.

Show at most 1,000 results per ranked view. This is an
intentional release limit, not a claim that the remaining matches do not exist.
When capped, a quiet label shows “Largest 1,000 of N files/folders.” Column sorting is
disabled in ranked views so a partial result set cannot masquerade as a full
alphabetical listing; existing inspector lists keep their sorting.

The persistent segmented selector exposes all three modes. Visited ranked
views retain their native tables, selections, and scroll positions while hidden
(at most two 1,000-row result sets per scan window). Hidden tables cannot receive
input. Returning to a ranking restores its selection as the active selection.

Direct treemap selections (clicks, context clicks, and arrow-key navigation)
switch to Folder Tree, whose existing selection synchronization expands ancestors
and reveals the selected row. Ranked tabs retain their own selection and scroll
position. Hovering, programmatic selection, and Show in Treemap do not trigger
the switch. Synthetic free/other space has no tree row and does not switch tabs.

Ranked columns are Name, Size, Kind, Path. Name uses the available viewport
width beside Size and wraps long names (including names without spaces) onto
additional lines. Row heights follow the wrapped text. Kind and Path remain
horizontally scrollable; inspector lists retain their existing single-line cells.

Ranked-item actions live in one context menu, opened by right-click, Shift-F10,
or the accessibility Show Menu action. Single selections offer Folder Tree,
Treemap, Finder, Information, and the existing cleanup queue action. Multiple
selections offer the batch cleanup action only. Right-clicking an unselected
row selects that row; right-clicking within a selection preserves the batch.

Changes to snapshot identity, package settings, or size mode
cancel old work. Cancelled/stale results cannot publish. Resizing does not
change the query. Incomplete-scan warnings remain visible.

Ranking runs off the main actor with at most two workers across all scan
windows. Waiting and active queries support cancellation. The bounded heap
uses O(limit + tree depth) temporary storage and O(items × log(limit)) work;
there is no all-items row dictionary or all-items sort in production ranking.

## Verification

From the repository root, run the focused checks without building the full
application test target:

```sh
xcrun swiftc -O -whole-module-optimization -parse-as-library \
  disk_hog/Models/DiskItems/*.swift \
  disk_hog/Support/Selection/{SelectionListFilter,SelectionListPipeline,LargestItemsQuery,LargestItemsPipeline,LargestItemsWorkQueue}.swift \
  scripts/largest-items-check.swift -o /private/tmp/diskhog-largest-check
/private/tmp/diskhog-largest-check 100000
```

Checks compare bounded results to a brute-force oracle, including size ties,
physical/logical sizes, search-before-limit, folder ranking, immediate children,
opaque/expanded packages, links, cancellation, and queued-worker permit recovery.
The oracle deliberately uses a full sort; its memory and total runtime are not
measurements of the production ranking algorithm.

Validation on September 22, 2026: the unsigned Release app build passed;
100,000-file and 1,000,000-file ranking/queue checks passed. Top-73 ranking alone
took approximately 0.51 seconds per size mode for the million-file fixture on
the development Mac. This is a synthetic measurement, not a UI latency promise.
The complete application test suite has not been run for this feature.

### In-app acceptance checklist (still requires interactive validation)

- Switch among all three modes, resize narrow/wide, and verify native scrolling.
- Verify long filenames, unbroken names, and Unicode names remain fully readable
  at narrow widths, with Size still visible beside Name and no clipped row text.
- Select ranked rows; verify tree, treemap, Information, Finder, and cleanup queue
  actions target the same item. Check keyboard navigation and multi-selection.
- Open the context menu with right-click and Shift-F10. Verify clicks outside
  the selection target the clicked row, clicks inside retain the selection,
  and blank space has no item menu. There is no separate bottom action menu.
- Scroll and select in each ranking, switch to Folder Tree and back, and verify
  selection and scroll position are retained independently for each ranking.
- Change size mode, switch modes, rescan, and close windows during
  ranking: stale results must not return or clear a newer result set.
- Run several scans/windows concurrently; resizing must not restart ranking.
- Inspect incomplete scans: affected sizes show a lower bound or Unknown, and
  the Scan Issues warning remains visible.
- Trash through the existing cleanup flow and confirm refreshed rankings no
  longer contain removed items.
- Confirm the 1,000-row cap and total counts, with no extra filtering controls.
