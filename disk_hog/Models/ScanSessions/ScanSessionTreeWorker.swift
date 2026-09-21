import Foundation

nonisolated struct ScanSessionTreeUpdateResult: @unchecked Sendable {
    let source: ScanSource
    let rootItem: DiskItem
    let presentationMetrics: TreemapPresentationMetrics
    let selectionPath: String
    let builtUsingPhysicalSize: Bool
    let skippedItems: [ScanSkippedItem]
    let refreshedSubtreePath: String
}

nonisolated protocol ScanSessionTreeUpdating: Sendable {
    func refresh(
        item: DiskItem,
        currentRoot: DiskItem,
        source: ScanSource,
        settings: DiskScanSettings
    ) async throws -> ScanSessionTreeUpdateResult

    func delete(
        item: DiskItem,
        deletionMethod: DiskItemDeletionMethod,
        currentRoot: DiskItem,
        source: ScanSource,
        settings: DiskScanSettings
    ) async throws -> ScanSessionTreeUpdateResult
}

nonisolated struct DiskInventoryZScanSessionTreeWorker: ScanSessionTreeUpdating {
    func refresh(
        item: DiskItem,
        currentRoot: DiskItem,
        source: ScanSource,
        settings: DiskScanSettings
    ) async throws -> ScanSessionTreeUpdateResult {
        let resolvedSource: ScanSource = try refreshingStaleBookmark(in: source)
        let refreshPath: String = Self.nearestExistingPath(
            from: item.path,
            stoppingAt: currentRoot.path
        )
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner()
        let updatedRoot: DiskItem
        let skippedItems: [ScanSkippedItem]
        if refreshPath == currentRoot.path {
            let outcome: DiskScanOutcome = try await scanner.scan(source: resolvedSource, settings: settings)
            updatedRoot = outcome.item
            skippedItems = outcome.skippedItems
        } else {
            let outcome: DiskScanOutcome = try await scanner.scanItem(
                at: URL(fileURLWithPath: refreshPath),
                from: resolvedSource,
                settings: settings
            )
            guard let replacementRoot: DiskItem = DiskItemTreeEditor.replacingSubtree(
                in: currentRoot,
                atPath: refreshPath,
                with: outcome.item,
                usePhysicalSize: settings.usePhysicalSize
            ) else {
                throw DiskScannerError.traversalInconsistency("The refreshed item was no longer present in the scan tree.")
            }
            updatedRoot = replacementRoot
            skippedItems = outcome.skippedItems
        }

        return ScanSessionTreeUpdateResult(
            source: resolvedSource,
            rootItem: updatedRoot,
            presentationMetrics: TreemapPresentationMetrics(
                rootItem: updatedRoot,
                usePhysicalSize: settings.usePhysicalSize,
                sharesKindColors: ScanPreferenceDefaults.sharesKindColors,
                colorScheme: ScanPreferenceDefaults.treemapColorScheme
            ),
            selectionPath: item.path,
            builtUsingPhysicalSize: settings.usePhysicalSize,
            skippedItems: skippedItems,
            refreshedSubtreePath: refreshPath
        )
    }

    func delete(
        item: DiskItem,
        deletionMethod: DiskItemDeletionMethod,
        currentRoot: DiskItem,
        source: ScanSource,
        settings: DiskScanSettings
    ) async throws -> ScanSessionTreeUpdateResult {
        let resolvedSource: ScanSource = try refreshingStaleBookmark(in: source)
        let rootURL: URL = try resolvedSource.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }

        switch deletionMethod {
        case .deletePermanently:
            try FileManager.default.removeItem(at: item.url)
        case .moveToTrash:
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
        }
        try Task.checkCancellation()

        guard let updatedRoot: DiskItem = DiskItemTreeEditor.removingSubtree(
            from: currentRoot,
            atPath: item.path,
            usePhysicalSize: settings.usePhysicalSize
        ) else {
            throw DiskScannerError.traversalInconsistency("The deleted item was no longer present in the scan tree.")
        }
        return ScanSessionTreeUpdateResult(
            source: resolvedSource,
            rootItem: updatedRoot,
            presentationMetrics: TreemapPresentationMetrics(
                rootItem: updatedRoot,
                usePhysicalSize: settings.usePhysicalSize,
                sharesKindColors: ScanPreferenceDefaults.sharesKindColors,
                colorScheme: ScanPreferenceDefaults.treemapColorScheme
            ),
            selectionPath: item.url.deletingLastPathComponent().path,
            builtUsingPhysicalSize: settings.usePhysicalSize,
            skippedItems: [],
            refreshedSubtreePath: item.path
        )
    }

    private static func nearestExistingPath(from path: String, stoppingAt rootPath: String) -> String {
        var candidateURL: URL = URL(fileURLWithPath: path).standardizedFileURL
        let standardizedRootPath: String = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        while !FileManager.default.fileExists(atPath: candidateURL.path) {
            guard candidateURL.path != standardizedRootPath else {
                return standardizedRootPath
            }
            let parentURL: URL = candidateURL.deletingLastPathComponent()
            guard parentURL.path != candidateURL.path else {
                return standardizedRootPath
            }
            candidateURL = parentURL
        }
        return candidateURL.path
    }

    private func refreshingStaleBookmark(in source: ScanSource) throws -> ScanSource {
        let resolution: ScanSourceBookmarkResolution = try source.resolvingBookmark()
        guard let refreshedBookmarkData: Data = resolution.refreshedBookmarkData else {
            return source
        }
        return source.replacingBookmarkData(refreshedBookmarkData)
    }
}
