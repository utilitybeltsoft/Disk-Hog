import Foundation

nonisolated enum ScanSessionOperationEvent: @unchecked Sendable {
    case cleanupFinished(Result<ScanSessionTreeUpdateResult, Error>, inputRoot: DiskItem)
    case progress(DiskScanProgress)
    case stage(DiskScanStage)
    case preparingTreemap
    case treemapProgress(Double)
    case scanFinished(Result<ScanSessionScanResult, Error>)
    case treeFinished(Result<ScanSessionTreeUpdateResult, Error>, ScanSessionOperation, Date?)

    var isTerminal: Bool {
        switch self {
        case .scanFinished, .treeFinished, .cleanupFinished: true
        default: false
        }
    }
}

/// Owns filesystem-operation identity, task lifetime, and deferred rescans.
/// Events are delivered only while their operation is current. It never owns
/// a session or writes published UI state.
@MainActor
final class ScanSessionOperationController {
    typealias Receiver = @MainActor @Sendable (ScanSessionOperationEvent) -> Void
    private let scanWorker: any ScanSessionScanning
    private let treeWorker: any ScanSessionTreeUpdating
    private let tasks = ScanSessionTaskCoordinator()
    private var rescans = ScanSessionRescanCoordinator()
    var isBusy: Bool { rescans.activeOperation != nil }

    init(scanWorker: any ScanSessionScanning, treeWorker: any ScanSessionTreeUpdating) {
        self.scanWorker = scanWorker
        self.treeWorker = treeWorker
    }

    func startScan(source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings,
                   willStart: () -> Void, receive: @escaping Receiver) {
        let operation = rescans.beginScan()
        willStart()
        let worker = scanWorker
        _ = tasks.start(.scan, operationID: operation.id) { _ in
            Task.detached(priority: .utility) { [weak self] in
                let result: Result<ScanSessionScanResult, Error>
                do {
                    result = .success(try await worker.scan(source: source, settings: settings, presentation: presentation,
                        progress: { [weak self] in await self?.deliver(.progress($0), for: operation, to: receive) },
                        stage: { [weak self] in await self?.deliver(.stage($0), for: operation, to: receive) },
                        willBuildTreemap: { [weak self] in await self?.deliver(.preparingTreemap, for: operation, to: receive) },
                        treemapProgress: { [weak self] in await self?.deliver(.treemapProgress($0), for: operation, to: receive) }))
                } catch { result = .failure(error) }
                await self?.deliver(.scanFinished(result), for: operation, to: receive)
            }
        }
    }

    func update(item: DiskItem, root: DiskItem, deletionMethod: DiskItemDeletionMethod?,
                source: ScanSource, settings: DiskScanSettings, presentation: ScanPresentationSettings,
                willStart: () -> Void, receive: @escaping Receiver) {
        let operation = rescans.beginTreeUpdate()
        let description: ScanSessionOperation = deletionMethod.map {
            .deletion(itemName: item.displayName, method: $0)
        } ?? .refresh(itemName: item.displayName)
        let refreshStartedAt: Date? = deletionMethod == nil ? Date() : nil
        willStart()
        let worker = treeWorker
        _ = tasks.start(.treeUpdate, operationID: operation.id) { _ in
            Task.detached(priority: .userInitiated) { [weak self] in
                let result: Result<ScanSessionTreeUpdateResult, Error>
                do {
                    if let deletionMethod {
                        result = .success(try await worker.delete(item: item, deletionMethod: deletionMethod,
                            currentRoot: root, source: source, settings: settings, presentation: presentation))
                    } else {
                        result = .success(try await worker.refresh(item: item, currentRoot: root,
                                                                  source: source, settings: settings, presentation: presentation))
                    }
                } catch { result = .failure(error) }
                await self?.deliver(.treeFinished(result, description, refreshStartedAt), for: operation, to: receive)
            }
        }
    }

    func reconcileCleanup(paths: [String], root: DiskItem, source: ScanSource, selectionPath: String,
                          settings: DiskScanSettings, presentation: ScanPresentationSettings,
                          willStart: () -> Void, receive: @escaping Receiver) {
        let operation = rescans.beginTreeUpdate()
        willStart()
        let worker = treeWorker
        _ = tasks.start(.treeUpdate, operationID: operation.id) { _ in
            Task.detached(priority: .userInitiated) { [weak self] in
                let result: Result<ScanSessionTreeUpdateResult, Error>
                do {
                    result = .success(try await worker.reconcileCleanup(paths: paths, currentRoot: root,
                        source: source, selectionPath: selectionPath, settings: settings, presentation: presentation))
                } catch { result = .failure(error) }
                await self?.deliver(.cleanupFinished(result, inputRoot: root), for: operation, to: receive)
            }
        }
    }

    /// Returns false when idle so the caller can start its scan immediately.
    func requestRescan(cancelActive: Bool) -> Bool {
        guard let operation = rescans.requestRescan() else { return false }
        if cancelActive {
            switch operation {
            case .scan: tasks.cancel(.scan)
            case .treeUpdate: tasks.cancel(.treeUpdate)
            }
        }
        return true
    }

    func consumePendingRescan() -> Bool { rescans.consumePendingRescan() }
    func cancel() { tasks.cancelAll() }

    private func deliver(_ event: ScanSessionOperationEvent, for operation: ScanSessionWorkOperation,
                         to receive: Receiver) {
        guard rescans.activeOperation == operation else { return }
        if event.isTerminal {
            let kind: ScanSessionTaskCoordinator.Kind
            switch operation {
            case .scan: kind = .scan
            case .treeUpdate: kind = .treeUpdate
            }
            guard tasks.finish(kind, operationID: operation.id), rescans.finish(operation) else { return }
        }
        receive(event)
    }
}
