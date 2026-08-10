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
        sharesKindColors: Bool
    ) -> TreemapPresentationMetrics

    func sizeModeUpdate(
        rootItem: DiskItem,
        selectionPath: String,
        usePhysicalSize: Bool,
        sharesKindColors: Bool
    ) -> ScanSessionSizeModeUpdateResult
}

nonisolated struct DiskInventoryZScanSessionPresentationWorker: ScanSessionPresenting {
    func presentationMetrics(
        rootItem: DiskItem,
        usePhysicalSize: Bool,
        sharesKindColors: Bool
    ) -> TreemapPresentationMetrics {
        TreemapPresentationMetrics(
            rootItem: rootItem,
            usePhysicalSize: usePhysicalSize,
            sharesKindColors: sharesKindColors
        )
    }

    func sizeModeUpdate(
        rootItem: DiskItem,
        selectionPath: String,
        usePhysicalSize: Bool,
        sharesKindColors: Bool
    ) -> ScanSessionSizeModeUpdateResult {
        let reorderedRoot: DiskItem = rootItem.reordered(usePhysicalSize: usePhysicalSize)
        return ScanSessionSizeModeUpdateResult(
            rootItem: reorderedRoot,
            presentationMetrics: presentationMetrics(
                rootItem: reorderedRoot,
                usePhysicalSize: usePhysicalSize,
                sharesKindColors: sharesKindColors
            ),
            selectionPath: selectionPath,
            usePhysicalSize: usePhysicalSize
        )
    }
}
