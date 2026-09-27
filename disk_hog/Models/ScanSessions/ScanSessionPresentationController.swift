import Foundation

nonisolated enum ScanSessionPresentationUpdate: @unchecked Sendable {
    case metrics(TreemapPresentationMetrics, inputRoot: DiskItem)
    case sizeMode(ScanSessionSizeModeUpdateResult, inputRoot: DiskItem)
}

/// Owns derived-work scheduling and the latest requested colours. Invalidation
/// rejects work already queued for MainActor as well as work still computing.
@MainActor
final class ScanSessionPresentationController {
    typealias Receiver = @MainActor @Sendable (ScanSessionPresentationUpdate) -> Void
    private let worker: any ScanSessionPresenting
    private let tasks = ScanSessionTaskCoordinator()
    private var revision: UInt64 = 0
    private var sharesKindColors = ScanPreferenceDefaults.sharesKindColors
    private var colorScheme = ScanPreferenceDefaults.treemapColorScheme

    init(worker: any ScanSessionPresenting) { self.worker = worker }

    func setPreferences(sharesKindColors: Bool, colorScheme: TreemapColorScheme) {
        self.sharesKindColors = sharesKindColors
        self.colorScheme = colorScheme
    }

    func invalidate() {
        revision &+= 1
        tasks.cancelAll()
    }

    func reconcile(snapshot: ScanSessionSnapshot, usePhysicalSize: Bool,
                   forceSize: Bool = false, forceColors: Bool = false, receive: @escaping Receiver) {
        guard let root = snapshot.root else { return }
        let resize = forceSize || snapshot.appliedSizeMode != usePhysicalSize
        guard resize || forceColors || snapshot.metrics?.sharesKindColors != sharesKindColors
                || snapshot.metrics?.colorScheme != colorScheme else { return }
        let kind: ScanSessionTaskCoordinator.Kind = resize ? .sizeModeUpdate : .presentationUpdate
        let revision = revision
        let worker = worker
        let colors = sharesKindColors
        let scheme = colorScheme
        let selectionPath = snapshot.selection?.path ?? root.path
        _ = tasks.start(kind) { id in
            Task.detached(priority: .userInitiated) { [weak self] in
                let update: ScanSessionPresentationUpdate
                if resize {
                    update = .sizeMode(worker.sizeModeUpdate(rootItem: root, selectionPath: selectionPath,
                        usePhysicalSize: usePhysicalSize, sharesKindColors: colors, colorScheme: scheme), inputRoot: root)
                } else {
                    update = .metrics(worker.presentationMetrics(rootItem: root, usePhysicalSize: usePhysicalSize,
                        sharesKindColors: colors, colorScheme: scheme), inputRoot: root)
                }
                let cancelled = Task.isCancelled
                await self?.finish(update, kind: kind, id: id, revision: revision, cancelled: cancelled, receive: receive)
            }
        }
    }

    private func finish(_ update: ScanSessionPresentationUpdate, kind: ScanSessionTaskCoordinator.Kind,
                        id: UUID, revision: UInt64, cancelled: Bool, receive: Receiver) {
        guard tasks.finish(kind, operationID: id), revision == self.revision, !cancelled else { return }
        receive(update)
    }
}
