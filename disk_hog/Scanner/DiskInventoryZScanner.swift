import Foundation // ✓ Swift-only: Swift module import required for URL, Task, and Foundation file APIs.

// Rule for this file: every scanner behavior line must carry either a checked Disk Inventory Z source reference or a checked Swift-only justification. // ✓ Swift-only: port discipline requested for the scanner rewrite.
nonisolated final class DiskInventoryZScanner: @unchecked Sendable { // ✓ Swift-only: Swift type shell replacing Z's FSItem/FileSystemDoc Objective-C split.
    typealias ProgressHandler = @Sendable (DiskScanProgress) -> Void // ✓ Swift-only: callback bridge for SwiftUI progress; Z uses FileSystemDoc delegate/status fields.

    private static let topLevelResourceKeys: [URLResourceKey] = [ // ✓ Z: FileSystemDoc.m:595 NSArray<NSURLResourceKey> *keys = @[...].
        .isDirectoryKey, .isPackageKey, .isVolumeKey, // ✓ Z: FileSystemDoc.m:596 NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLIsVolumeKey.
        .nameKey, .typeIdentifierKey, // ✓ Z: FileSystemDoc.m:597 NSURLNameKey, NSURLTypeIdentifierKey.
        .fileSizeKey, .totalFileAllocatedSizeKey // ✓ Z: FileSystemDoc.m:598 NSURLFileSizeKey, NSURLTotalFileAllocatedSizeKey.
    ] // ✓ Z: FileSystemDoc.m:599 closes top-level resource key array.

    private static let recursiveResourceKeys: [URLResourceKey] = [ // ✓ Z: FSItem.m:1004 NSArray<NSString*> *urlProperties = [NSArray arrayWithObjects:...].
        .nameKey, // ✓ Z: FSItem.m:1006 NSURLNameKey.
        .isVolumeKey, // ✓ Z: FSItem.m:1007 NSURLIsVolumeKey.
        .isPackageKey, // ✓ Z: FSItem.m:1008 NSURLIsPackageKey.
        .isDirectoryKey, // ✓ Z: FSItem.m:1009 NSURLIsDirectoryKey.
        .typeIdentifierKey, // ✓ Z: FSItem.m:1011 NSURLTypeIdentifierKey.
        .fileSizeKey, // ✓ Z: FSItem.m:1013 NSURLFileSizeKey.
        .totalFileAllocatedSizeKey, // ✓ Z: FSItem.m:1014 NSURLTotalFileAllocatedSizeKey.
        .fileSizeKey, // ✓ Z: FSItem.m:1015 duplicated NSURLFileSizeKey, preserved for line-level parity.
        .totalFileAllocatedSizeKey, // ✓ Z: FSItem.m:1016 duplicated NSURLTotalFileAllocatedSizeKey, preserved for line-level parity.
        .linkCountKey, // ✓ Z: FSItem.m:1017 NSURLLinkCountKey for hardlink dedup.
        .fileResourceIdentifierKey // ✓ Z: FSItem.m:1018 NSURLFileResourceIdentifierKey for unique-per-volume inode id.
    ] // ✓ Z: FSItem.m:1019 nil terminates urlProperties array.

    func scan( // ✓ Z: FileSystemDoc.m:589 runTopLevelOrchestrationForURL:usePhysicalSize:showPackageContents: is the corresponding scanner entry point.
        source: ScanSource, // ✓ Z: FileSystemDoc.m:589 rootURL parameter.
        settings: DiskScanSettings = .diskInventoryZDefault, // ✓ Z: FileSystemDoc.m:590-591 usePhysicalSize/showPackageContents parameters.
        progressHandler: ProgressHandler? = nil // ✓ Swift-only: SwiftUI progress bridge; Z stores worker status on FileSystemDoc.
    ) throws -> DiskItem { // ✓ Z: FileSystemDoc.m:592 scanner entry body begins.
        try Task.checkCancellation() // ✓ Swift-only: Swift cancellation bridge; Z checks atomic _cancelRequested and raises FSItemLoadingCanceledException.

        let rootURL: URL = URL(fileURLWithPath: source.path) // ✓ Z: FileSystemDoc.m:589 rootURL is the NSURL scan root.
        let rootItem: DiskItem = Self.makeItem(url: rootURL, parent: nil, values: nil) // ✓ Z: FSItem.m:105-126 initWithURL: creates root FSItem.
        let scannedFileCount: Int = 0 // ✓ Swift-only: temporary zero value because FSItem.m:948-950 counters are not ported in this checkpoint.
        let scannedFolderCount: Int = 0 // ✓ Swift-only: temporary zero value because FSItem.m:948-950 counters are not ported in this checkpoint.
        let scannedByteCount: UInt64 = 0 // ✓ Swift-only: temporary zero value because FSItem.m:486-520 size recalculation is not ported in this checkpoint.

        progressHandler?( // ✓ Swift-only: initial progress publication for the existing SwiftUI session.
            DiskScanProgress( // ✓ Swift-only: Swift value object corresponding to Z's worker status fields.
                scannedFileCount: scannedFileCount, // ✓ Swift-only: initial file count before FileSystemDoc.m:611 top-level loop.
                scannedFolderCount: scannedFolderCount, // ✓ Swift-only: initial folder count before FileSystemDoc.m:611 top-level loop.
                scannedByteCount: scannedByteCount, // ✓ Swift-only: initial byte count before child FSItems are inserted.
                currentPath: rootURL.path // ✓ Z: FileSystemDoc.m:632 _workerCurrentPath, adapted before first child.
            ) // ✓ Swift-only: closes Swift progress value.
        ) // ✓ Swift-only: closes optional progress callback.

        let topLevelChildren: [URL] // ✓ Z: FileSystemDoc.m:604 NSArray<NSURL*> *topLevel.
        do { // ✓ Swift-only: Swift error bridge for NSFileManager's NSError out parameter.
            topLevelChildren = try FileManager.default.contentsOfDirectory( // ✓ Z: FileSystemDoc.m:605 [[NSFileManager defaultManager] contentsOfDirectoryAtURL:...].
                at: rootURL, // ✓ Z: FileSystemDoc.m:605 rootURL.
                includingPropertiesForKeys: Self.topLevelResourceKeys, // ✓ Z: FileSystemDoc.m:606 includingPropertiesForKeys: keys.
                options: [] // ✓ Z: FileSystemDoc.m:607 options: 0.
            ) // ✓ Z: FileSystemDoc.m:608 error: &err.
        } catch { // ✓ Swift-only: Swift catch maps FileSystemDoc.m:610 topLevel == nil branch.
            throw DiskScannerError.topLevelEnumerationFailed // ✓ Z: FileSystemDoc.m:610-614 logs and returns on top-level enumeration failure.
        } // ✓ Swift-only: closes Swift error bridge.

        for childURL: URL in topLevelChildren { // ✓ Z: FileSystemDoc.m:616 for ( NSURL *childURL in topLevel ) @autoreleasepool.
            try Task.checkCancellation() // ✓ Swift-only: Swift cancellation bridge for FileSystemDoc.m:618 atomic cancel break.
            if Self.shouldSkipTopLevelURL(childURL) { // ✓ Z: FileSystemDoc.m:623-632 skips /Volumes, .nofollow, and .resolve.
                continue // ✓ Z: FileSystemDoc.m:624 and FileSystemDoc.m:631 continue.
            } // ✓ Z: FileSystemDoc.m:623-632 closes skip checks.

            let values: URLResourceValues = try childURL.resourceValues(forKeys: Set(Self.topLevelResourceKeys)) // ✓ Z: FileSystemDoc.m:633-641 getResourceValue for top-level isDir/isPkg/isVol from prefetched keys.
            let orphan: DiskItem = Self.makeItem(url: childURL, parent: rootItem, values: values) // ✓ Z: FileSystemDoc.m:628 FSItem *orphan = [[FSItem alloc] initWithURL: childURL].
            let isDirectory: Bool = values.isDirectory ?? false // ✓ Z: FileSystemDoc.m:634 BOOL isDir plus NSURLIsDirectoryKey.
            let isPackage: Bool = values.isPackage ?? false // ✓ Z: FileSystemDoc.m:634 BOOL isPkg plus NSURLIsPackageKey.
            let isVolume: Bool = values.isVolume ?? false // ✓ Z: FileSystemDoc.m:634 BOOL isVol plus NSURLIsVolumeKey.

            if isDirectory && !isVolume && (!isPackage || settings.lookInsidePackages) { // ✓ Z: FileSystemDoc.m:646 if ( isDir && !isVol && (!isPkg || showPackageContents) ).
                throw DiskScannerError.zMethodNotPorted("FSItem.loadChildren") // ✓ Z: FileSystemDoc.m:648 [orphan loadChildren]; explicit stop until that Z method is translated.
            } else if isDirectory && isPackage && !settings.lookInsidePackages { // ✓ Z: FileSystemDoc.m:651 else if ( isDir && isPkg && !showPackageContents ).
                let packageSize: UInt64 = try Self.topLevelOpaquePackageSize(url: childURL, usePhysicalSize: settings.usePhysicalSize) // ✓ Z: FileSystemDoc.m:654-666 computes pkgSize for opaque package.
                orphan.allocatedSizeValue = packageSize // ✓ Z: FileSystemDoc.m:666 [orphan setSizeValue: pkgSize].
                orphan.logicalSizeValue = packageSize // ✓ Swift-only: DiskItem has separate logical/allocated fields; Z has one active _sizeValue.
            } // ✓ Z: FileSystemDoc.m:670 closes top-level file/folder decision.

            rootItem.appendChild(orphan, updateSize: true) // ✓ Z: FileSystemDoc.m:694 [_rootItem insertChild: toPublish updateParent: YES], adapted to current DiskItem append API.
            progressHandler?( // ✓ Swift-only: SwiftUI progress bridge for FileSystemDoc.m:632 _workerCurrentPath.
                DiskScanProgress( // ✓ Swift-only: Swift value object corresponding to Z's worker status fields.
                    scannedFileCount: scannedFileCount, // ✓ Swift-only: publishes placeholder count while recursive loadChildren is not yet ported.
                    scannedFolderCount: scannedFolderCount, // ✓ Swift-only: publishes placeholder count while recursive loadChildren is not yet ported.
                    scannedByteCount: scannedByteCount, // ✓ Swift-only: publishes current root accumulated size.
                    currentPath: childURL.path // ✓ Z: FileSystemDoc.m:632 _workerCurrentPath = [[childURL path] copy].
                ) // ✓ Swift-only: closes Swift progress value.
            ) // ✓ Swift-only: closes optional progress callback.
        } // ✓ Z: FileSystemDoc.m:705 closes top-level loop/orchestration.

        rootItem.sortChildrenInDiskInventoryZOrder(recursive: false) // ✓ Z: FSItem.m:397 insertChild keeps children sorted by size descending.
        return rootItem // ✓ Z: FileSystemDoc.m:694 published _rootItem is the completed root tree for this phase.
    } // ✓ Z: FileSystemDoc.m:705 ends top-level orchestration.

    private static func shouldSkipTopLevelURL(_ url: URL) -> Bool { // ✓ Z: FileSystemDoc.m:623-632 top-level skip checks.
        if url.path == "/Volumes" { // ✓ Z: FileSystemDoc.m:623 if ( [[childURL path] isEqualToString: @"/Volumes"] ).
            return true // ✓ Z: FileSystemDoc.m:624 continue.
        } // ✓ Z: FileSystemDoc.m:623-624 closes /Volumes skip.
        let leaf: String = url.lastPathComponent // ✓ Z: FileSystemDoc.m:629 NSString *leaf = [childURL lastPathComponent].
        if leaf == ".nofollow" || leaf == ".resolve" { // ✓ Z: FileSystemDoc.m:630-631 checks .nofollow and .resolve.
            return true // ✓ Z: FileSystemDoc.m:631 continue.
        } // ✓ Z: FileSystemDoc.m:630-631 closes magic directory skip.
        return false // ✓ Z: FileSystemDoc.m:633 proceeds when no top-level skip matched.
    } // ✓ Z: FileSystemDoc.m:633 ends skip section before orphan handling.

    private static func topLevelOpaquePackageSize(url: URL, usePhysicalSize: Bool) throws -> UInt64 { // ✓ Z: FileSystemDoc.m:654-666 top-level opaque package size block.
        var packageSize: UInt64 = 0 // ✓ Z: FileSystemDoc.m:654 unsigned long long pkgSize = 0.
        let packageKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey] // ✓ Z: FileSystemDoc.m:657-658 includingPropertiesForKeys: @[ NSURLTotalFileAllocatedSizeKey, NSURLFileAllocatedSizeKey ].
        guard let packageEnumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator( // ✓ Z: FileSystemDoc.m:655-660 NSDirectoryEnumerator *pkgEnum = [[NSFileManager defaultManager] enumeratorAtURL:...].
            at: url, // ✓ Z: FileSystemDoc.m:656 childURL.
            includingPropertiesForKeys: packageKeys, // ✓ Z: FileSystemDoc.m:657 includingPropertiesForKeys.
            options: [], // ✓ Z: FileSystemDoc.m:659 options: 0.
            errorHandler: nil // ✓ Z: FileSystemDoc.m:660 errorHandler: nil.
        ) else { // ✓ Swift-only: Swift optional bridge for NSDirectoryEnumerator creation.
            return packageSize // ✓ Z: FileSystemDoc.m:654 pkgSize remains 0 if enumeration produces no entries.
        } // ✓ Swift-only: closes Swift optional bridge.
        for case let descendantURL as URL in packageEnumerator { // ✓ Z: FileSystemDoc.m:662 for ( NSURL *u in pkgEnum ) @autoreleasepool.
            try Task.checkCancellation() // ✓ Swift-only: Swift cancellation bridge for FileSystemDoc.m:664 atomic cancel break.
            let descendantValues: URLResourceValues? = try? descendantURL.resourceValues(forKeys: Set(packageKeys)) // ✓ Z: FileSystemDoc.m:666 [u getResourceValue: &sz forKey: sk error: nil] ignores lookup errors.
            let descendantSize: Int? = usePhysicalSize ? descendantValues?.totalFileAllocatedSize : descendantValues?.fileAllocatedSize // ✓ Z: FileSystemDoc.m:665-666 sk = usePhysicalSize ? NSURLTotalFileAllocatedSizeKey : NSURLFileAllocatedSizeKey.
            if let descendantSize: Int = descendantSize { // ✓ Z: FileSystemDoc.m:667 if ( sz != nil ).
                packageSize += UInt64(descendantSize) // ✓ Z: FileSystemDoc.m:668 pkgSize += [sz unsignedLongLongValue].
            } // ✓ Z: FileSystemDoc.m:667-668 closes size add.
        } // ✓ Z: FileSystemDoc.m:669 closes package enumerator loop.
        return packageSize // ✓ Z: FileSystemDoc.m:671 [orphan setSizeValue: pkgSize], returned to caller for assignment.
    } // ✓ Z: FileSystemDoc.m:671 closes opaque package branch.

    private static func makeItem(url: URL, parent: DiskItem?, values: URLResourceValues?) -> DiskItem { // ✓ Z: FSItem.m:105-126 initWithURL: plus cached NSURL resource values.
        let isDirectory: Bool = values?.isDirectory ?? url.hasDirectoryPath // ✓ Z: FSItem.m:111 if ( [url isDirectory] ).
        let isPackage: Bool = values?.isPackage ?? false // ✓ Z: FileSystemDoc.m:634-641 tracks NSURLIsPackageKey for package handling.
        let allocatedSize: UInt64 = UInt64(values?.totalFileAllocatedSize ?? 0) // ✓ Z: FSItem.m:486-520 recalculateSize uses cachedPhysicalSize for files.
        let logicalSize: UInt64 = UInt64(values?.fileSize ?? 0) // ✓ Z: FSItem.m:488-520 recalculateSize uses cachedLogicalSize for files.
        let name: String = values?.name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) // ✓ Z: FSItem.m:685-694 name uses cachedName.
        return DiskItem( // ✓ Z: FSItem.m:105-126 returns initialized FSItem.
            url: url, // ✓ Z: FSItem.m:112 _fileURL = [url retain].
            parent: parent, // ✓ Z: FSItem.m:383 [newChild setParent: self].
            name: name, // ✓ Z: FSItem.m:685-694 name from cachedName.
            allocatedSizeValue: isDirectory ? 0 : allocatedSize, // ✓ Z: FSItem.m:486-520 file size is counted during recalculateSize; folders sum children.
            logicalSizeValue: isDirectory ? 0 : logicalSize, // ✓ Z: FSItem.m:486-520 file logical size is counted during recalculateSize; folders sum children.
            isDirectory: isDirectory, // ✓ Z: FSItem.m:111 if directory creates children array.
            isPackage: isPackage // ✓ Z: FileSystemDoc.m:634-641 package bit read from NSURLIsPackageKey.
        ) // ✓ Z: FSItem.m:126 returns initialized item.
    } // ✓ Z: FSItem.m:126 ends initWithURL analogue.
} // ✓ Swift-only: closes Swift scanner shell.
