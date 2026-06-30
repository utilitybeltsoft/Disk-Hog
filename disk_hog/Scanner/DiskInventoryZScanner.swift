import Foundation // ✓ Swift-only: Swift module import required for URL, Task, and Foundation file APIs.

// Rule for this file: every scanner behavior line must carry either "✓ Z:" with the exact Disk Inventory Z source reference, or "✓ Swift-only:" with the reason the line has no direct Z equivalent. // ✓ Swift-only: port discipline requested for the scanner rewrite.
nonisolated final class DiskInventoryZScanner: @unchecked Sendable { // ✓ Swift-only: Swift type shell replacing Z's FSItem/FileSystemDoc Objective-C split.
    typealias ProgressHandler = @Sendable (DiskScanProgress) -> Void // ✓ Swift-only: callback bridge for SwiftUI progress; Z uses FileSystemDoc delegate/status fields.

    func scan( // ✓ Z: FileSystemDoc.m:589 runTopLevelOrchestrationForURL:usePhysicalSize:showPackageContents: is the corresponding scanner entry point.
        source: ScanSource, // ✓ Z: FileSystemDoc.m:589 rootURL parameter.
        settings: DiskScanSettings = .diskInventoryZDefault, // ✓ Z: FileSystemDoc.m:591 usePhysicalSize/showPackageContents parameters.
        progressHandler: ProgressHandler? = nil // ✓ Swift-only: SwiftUI progress bridge; Z stores worker status on FileSystemDoc.
    ) throws -> DiskItem { // ✓ Z: FileSystemDoc.m:589 scanner entry body begins.
        try Task.checkCancellation() // ✓ Swift-only: Swift cancellation bridge; Z checks atomic _cancelRequested and raises FSItemLoadingCanceledException.

        let rootURL: URL = URL(fileURLWithPath: source.path) // ✓ Z: FileSystemDoc.m:589 rootURL is the NSURL scan root.
        let rootItem: DiskItem = DiskItem( // ✓ Z: FSItem.m:92-126 initWithURL: creates the root FSItem.
            url: rootURL, // ✓ Z: FSItem.m:107 _fileURL = [url retain].
            name: rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent, // ✓ Z: NSURL-Extensions.m:101-104 name, adapted for empty root names.
            isDirectory: true // ✓ Z: FSItem.m:111-112 creates _childs when [url isDirectory]; phase-zero scaffold assumes selected scan sources are directories.
        ) // ✓ Z: FSItem.m:126 returns initialized root item.

        progressHandler?( // ✓ Swift-only: immediate progress publication so existing UI does not hang while scanner is rebuilt.
            DiskScanProgress( // ✓ Swift-only: Swift value object corresponding to Z's worker status fields.
                scannedFileCount: 0, // ✓ Swift-only: phase-zero scaffold has not walked children yet.
                scannedFolderCount: 0, // ✓ Swift-only: phase-zero scaffold has not walked children yet.
                scannedByteCount: 0, // ✓ Swift-only: phase-zero scaffold has not computed size yet.
                currentPath: rootURL.path // ✓ Z: FileSystemDoc.m:632 _workerCurrentPath = [[childURL path] copy], adapted to root.
            ) // ✓ Swift-only: closes Swift progress value.
        ) // ✓ Swift-only: closes optional progress callback.

        return rootItem // ✓ Z: FileSystemDoc.m:690-704 publishes completed orphan/root into the document tree, adapted to return value.
    } // ✓ Z: FileSystemDoc.m:705 ends top-level orchestration.
} // ✓ Swift-only: closes Swift scanner shell.
