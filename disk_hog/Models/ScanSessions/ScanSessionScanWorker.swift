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
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        stage: @escaping @Sendable (DiskScanStage) async -> Void,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult {
        let resolution: ScanSourceBookmarkResolution = try source.resolvingBookmark()
        let resolvedSource: ScanSource = resolution.refreshedBookmarkData.map(source.replacingBookmarkData) ?? source
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner()
        let outcome: DiskScanOutcome = try await scanner.scan(
            source: resolvedSource,
            settings: settings
        ) { scanProgress in
            await progress(scanProgress)
        } stageHandler: { scanStage in
            await stage(scanStage)
        }
        let rootItem: DiskItem = outcome.item
        try Task.checkCancellation()
        await willBuildTreemap()
        let presentationMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: settings.usePhysicalSize,
            sharesKindColors: ScanPreferenceDefaults.sharesKindColors,
            colorScheme: ScanPreferenceDefaults.treemapColorScheme
        ) { progress in
            Task {
                await treemapProgress(progress)
            }
        }
        try Task.checkCancellation()
        return ScanSessionScanResult(
            source: resolvedSource,
            rootItem: rootItem,
            presentationMetrics: presentationMetrics,
            builtUsingPhysicalSize: settings.usePhysicalSize,
            skippedItems: outcome.skippedItems
        )
    }
}
