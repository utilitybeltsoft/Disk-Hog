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
