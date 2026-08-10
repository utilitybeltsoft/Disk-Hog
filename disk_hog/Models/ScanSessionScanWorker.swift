import Foundation

nonisolated struct ScanSessionScanResult: @unchecked Sendable {
    let source: ScanSource
    let rootItem: DiskItem
    let presentationMetrics: TreemapPresentationMetrics
    let builtUsingPhysicalSize: Bool
}

nonisolated protocol ScanSessionScanning: Sendable {
    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult
}

nonisolated struct DiskInventoryZScanSessionWorker: ScanSessionScanning {
    func scan(
        source: ScanSource,
        settings: DiskScanSettings,
        progress: @escaping DiskInventoryZScanner.ProgressHandler,
        willBuildTreemap: @escaping @Sendable () async -> Void,
        treemapProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> ScanSessionScanResult {
        let resolution: ScanSourceBookmarkResolution = try source.resolvingBookmark()
        let resolvedSource: ScanSource = resolution.refreshedBookmarkData.map(source.replacingBookmarkData) ?? source
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner()
        let rootItem: DiskItem = try await scanner.scan(
            source: resolvedSource,
            settings: settings
        ) { scanProgress in
            await progress(scanProgress)
        }
        try Task.checkCancellation()
        await willBuildTreemap()
        let presentationMetrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: settings.usePhysicalSize,
            sharesKindColors: ScanPreferenceDefaults.sharesKindColors
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
            builtUsingPhysicalSize: settings.usePhysicalSize
        )
    }
}
