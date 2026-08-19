import Foundation

nonisolated struct ScanSessionSizeModeUpdateResult: @unchecked Sendable {
    let rootItem: DiskItem
    let presentationMetrics: TreemapPresentationMetrics
    let selectionPath: String
    let usePhysicalSize: Bool
}

nonisolated protocol ScanSessionPresenting: Sendable {
    func presentationMetrics(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> TreemapPresentationMetrics

    func sizeModeUpdate(
        rootItem: DiskItem,
        selectionPath: String,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> ScanSessionSizeModeUpdateResult
}

nonisolated struct DiskInventoryZScanSessionPresentationWorker: ScanSessionPresenting {
    func presentationMetrics(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> TreemapPresentationMetrics {
        TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: usePhysicalSize,
            sharesKindColors: sharesKindColors,
            colorScheme: colorScheme
        )
    }

    func sizeModeUpdate(
        rootItem: DiskItem,
        selectionPath: String,
        usePhysicalSize: Bool,
        sharesKindColors: Bool,
        colorScheme: TreemapColorScheme
    ) -> ScanSessionSizeModeUpdateResult {
        let reorderedRoot: DiskItem = DiskItemTreeEditor.reordered(rootItem, usePhysicalSize: usePhysicalSize)
        return ScanSessionSizeModeUpdateResult(
            rootItem: reorderedRoot,
            presentationMetrics: presentationMetrics(
                rootItem: reorderedRoot,
                usePhysicalSize: usePhysicalSize,
                sharesKindColors: sharesKindColors,
                colorScheme: colorScheme
            ),
            selectionPath: selectionPath,
            usePhysicalSize: usePhysicalSize
        )
    }
}
