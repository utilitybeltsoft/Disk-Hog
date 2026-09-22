# Largest items

The scan window offers Folder Tree, Largest Files (the initial mode), and
Largest Folders. Rankings use the immutable scanned snapshot, never live file
metadata. Sizes follow the scan's physical/logical setting; they are not a
promise of reclaimable space.

The scope root itself and synthetic free/other-space nodes are excluded.
Folder sizes include descendants and overlap with ancestor totals. Symlinks
and aliases are not traversed. Opaque packages count as single file-like items;
when package contents were scanned, packages appear as folders and their
contents participate normally. Hard-link sizes use the scanner's accounting.

Queries default to all descendants of the scan root. An explicit folder scope
can be captured from the treemap or a selected folder; ordinary selection must
not silently change it. Immediate-children queries allow drilling down.
Search and optional kind filters apply before choosing top results.
Ordering is size descending, then path ascending.

Initially show 1,000 matching results, with Show More in increments of 1,000.
To bound each live result set, stop at 10,000 and explicitly ask the user to
narrow scope/search. No additional ranking cache is retained. This is an
intentional release limit, not a claim that the remaining matches do not exist.
Headers show both displayed and total matching counts. Column sorting is
disabled in ranked views so a partial result set cannot masquerade as a full
alphabetical listing; existing inspector lists keep their sorting.

Changes to snapshot identity, scope, query, package settings, or size mode
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
- Select ranked rows; verify tree, treemap, Information, Finder, and cleanup queue
  actions target the same item. Check keyboard navigation and multi-selection.
- Capture a folder scope and select other items: scope must remain unchanged.
- Type rapidly, change size mode, switch modes, rescan, and close windows during
  ranking: stale results must not return or clear a newer result set.
- Run several scans/windows concurrently; resizing must not restart ranking.
- Inspect incomplete scans: affected sizes show a lower bound or Unknown, and
  the Scan Issues warning remains visible.
- Trash through the existing cleanup flow and confirm refreshed rankings no
  longer contain removed items.
- Confirm Show More counts and the explicit 10,000-row limit.
