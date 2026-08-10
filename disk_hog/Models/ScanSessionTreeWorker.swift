import Foundation

nonisolated struct ScanSessionTreeUpdateResult: @unchecked Sendable {
    let source: ScanSource
    let rootItem: DiskItem
    let presentationMetrics: TreemapPresentationMetrics
    let selectionPath: String
    let builtUsingPhysicalSize: Bool
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
        if refreshPath == currentRoot.path {
            updatedRoot = try await scanner.scan(source: resolvedSource, settings: settings)
        } else {
            let refreshedItem: DiskItem = try await scanner.scanItem(
                at: URL(fileURLWithPath: refreshPath),
                from: resolvedSource,
                settings: settings
            )
            guard let replacementRoot: DiskItem = DiskItemTreeEditor.replacingSubtree(
                in: currentRoot,
                atPath: refreshPath,
                with: refreshedItem,
                usePhysicalSize: settings.usePhysicalSize
            ) else {
                throw DiskScannerError.traversalInconsistency("The refreshed item was no longer present in the scan tree.")
            }
            updatedRoot = replacementRoot
        }

        return ScanSessionTreeUpdateResult(
            source: resolvedSource,
            rootItem: updatedRoot,
            presentationMetrics: TreemapPresentationMetrics(
                rootItem: updatedRoot,
                usePhysicalSize: settings.usePhysicalSize,
                sharesKindColors: KindColorPreferences.sharesColors
            ),
            selectionPath: item.path,
            builtUsingPhysicalSize: settings.usePhysicalSize
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
                sharesKindColors: KindColorPreferences.sharesColors
            ),
            selectionPath: item.url.deletingLastPathComponent().path,
            builtUsingPhysicalSize: settings.usePhysicalSize
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
