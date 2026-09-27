# Session state ownership

`ScanSession` is the MainActor UI facade. Views and commands keep using its
read-only properties and command methods. It publishes four value groups:
snapshot, activity, space visibility, and failure. Diagnostics builds also
publish export status. Computed accessors keep existing `ObservableObject`
consumers working without a second set of mutable scalar properties.

- `ScanSessionOperationController` owns scan/tree workers, task identities,
  cancellation, and coalesced pending rescans. It validates every callback
  against the active operation and clears both coordinators before delivering
  a terminal event. It never writes published session state.
- `ScanSessionPresentationController` owns requested colours and derived tasks.
  Its revision rejects results invalidated by a new tree operation or snapshot.
  The facade additionally checks the input tree and requested size mode before
  accepting a result. Preferences deferred during tree work are reconciled
  after success, failure, or cancellation.
- `ScanSessionSnapshot` applies accepted scan, refresh/delete, and size-mode
  results. Root, metrics, selection, counts, skipped paths, source/bookmark
  metadata, and freshness belong to this value. Copies share packed tree
  storage. Only successful acquisition updates freshness; deletion and
  presentation changes do not.
- `ScanSessionSpaceItems` projects volume capacity and scanned size into
  synthetic items. Visibility remains separate user state.
- `ScanSessionActivity` contains live progress and lifecycle/render timing.
  Progress counts are used while no completed root exists; the accepted
  snapshot owns completed counts.
- `ScanSessionDiagnostics` performs optional export and clipboard work without
  owning the session.

The facade constructs a new snapshot and publishes it before posting
`scanSessionTreeDidChange`. Subscribers to that notification can read all
matching metadata and activity. Ordinary Combine `objectWillChange` retains
its normal pre-change semantics. Metrics-only and selection-only changes do
not post a tree notification.

Presentation preferences are explicit operation inputs. The window constructor
supplies `ScanPreferences.presentationSettings` to a new session; standalone
sessions use stable defaults. Each scan, refresh, or delete captures the current
`ScanPresentationSettings` before dispatching work. Workers never consult
`UserDefaults`. A preference change during work is retained by the presentation
controller and reconciled against the resulting tree.

Command and context-menu queue checks and mutations use the same injected
`CleanupQueueStore`. Scan windows pass command state/router and queue dependencies
to their native tables and treemap. Preferences accept a registry and defaults
domain; window registration and unregistration use the same supplied registry.
Production shared instances remain constructor defaults, not action-time lookups.
`DependencyIsolationTests` covers queue routing, registry/persistence isolation,
real worker settings, and preference changes during an in-flight scan.

Do not assign source/bookmark metadata outside the accepted-result boundary.
Do not discard pending queue refreshes on cancellation/failure or cancel an
in-flight deletion merely to service an external refresh request. Filesystem
mutation reconciliation remains the tree worker's responsibility.

Run `bash test/run-tests.sh --unit-only` from the repository root. The stale-tree,
queue-refresh, snapshot, and publication suites cover these boundaries,
including weak session lifetime and notification-time consistency. Installed-app
UI tests exercise `/Applications/Disk Hog.app`, not this test host.
