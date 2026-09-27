import Foundation

nonisolated struct ScanSessionScanResult: @unchecked Sendable {
    let source: ScanSource
    let rootItem: DiskItem
    let presentationMetrics: TreemapPresentationMetrics
    let builtUsingPhysicalSize: Bool
    let skippedItems: [ScanSkippedItem]
}

nonisolated protocol ScanSessionScanning: Sendable {
    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        presentation: ScanPresentationSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        stage: @escaping @Sendable (DiskScanStage) async -> Void,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult
}

nonisolated struct DiskInventoryZScanSessionWorker: ScanSessionScanning {
    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        presentation: ScanPresentationSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        stage: @escaping @Sendable (DiskScanStage) async -> Void,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult {
        let activityID = ScanActivity.shared.begin()
        var outcomeLabel = "failed"
        defer {
            ScanActivity.shared.end(activityID, outcome: Task.isCancelled ? "cancelled" : outcomeLabel)
        }
        let resolution: ScanSourceBookmarkResolution = try source.resolvingBookmark()
        let resolvedSource: ScanSource = resolution.refreshedBookmarkData.map(source.replacingBookmarkData) ?? source
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner()
        let outcome: DiskScanOutcome = try await scanner.scan(
            source: resolvedSource,
            settings: settings
        ) { scanProgress in
            await progress(scanProgress)
        } stageHandler: { scanStage in
            let label: String
            switch scanStage {
            case .enumeratingRootItems: label = "enumerating"
            case .scanningFiles: label = "scanning"
            case .packagingScanResults: label = "packaging"
            case .finalizingScan: label = "finalizing"
            }
            ScanActivity.shared.stage(label, scan: activityID)
            await stage(scanStage)
        }
        let rootItem: DiskItem = outcome.item
        try Task.checkCancellation()
        await willBuildTreemap()
        ScanActivity.shared.stage("preparing-presentation", scan: activityID)
        let presentationMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: settings.usePhysicalSize,
            sharesKindColors: presentation.sharesKindColors,
            colorScheme: presentation.colorScheme
        ) { progress in
            Task {
                await treemapProgress(progress)
            }
        }
        try Task.checkCancellation()
        outcomeLabel = "completed"
        return ScanSessionScanResult(
            source: resolvedSource,
            rootItem: rootItem,
            presentationMetrics: presentationMetrics,
            builtUsingPhysicalSize: settings.usePhysicalSize,
            skippedItems: outcome.skippedItems
        )
    }
}
