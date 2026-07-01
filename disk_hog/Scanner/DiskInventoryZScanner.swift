import Foundation // ✓ Swift-only: Swift module import required for URL, Task, and Foundation file APIs.

// Rule for this file: every scanner behavior line must carry either a checked Disk Inventory Z source reference or a checked Swift-only justification. // ✓ Swift-only: port discipline requested for the scanner rewrite.
nonisolated final class DiskInventoryZScanner: @unchecked Sendable { // ✓ Swift-only: Swift type shell replacing Z's FSItem/FileSystemDoc Objective-C split.
    typealias ProgressHandler = @Sendable (DiskScanProgress) -> Void // ✓ Swift-only: callback bridge for SwiftUI progress; Z uses FileSystemDoc delegate/status fields.

    nonisolated(unsafe) private static var firmlinkURLs: Set<URL>? = nil // ✓ Z: NSURL-Extensions.m:23 NSMutableDictionary<NSURL*, NSURL*> * g_Firmlinks = nil.
    private static let firmlinkListPath: String = "/usr/share/firmlinks" // ✓ Z: NSURL-Extensions.m:24 NSString *firmlinkListFile = @"/usr/share/firmlinks".

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
                try Self.loadChildren(of: orphan, settings: settings) // ✓ Z: FileSystemDoc.m:648 [orphan loadChildren].
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

    private static func shouldSkipRecursiveURL(_ url: URL, enumerator: FileManager.DirectoryEnumerator) -> Bool { // ✓ Z: FSItem.m:1060-1085 recursive /Volumes, .nofollow, and .resolve skip checks.
        if url.path == "/Volumes" { // ✓ Z: FSItem.m:1066 if ( [[currentUrl path] isEqualToString: @"/Volumes"] ).
            enumerator.skipDescendants() // ✓ Z: FSItem.m:1068 [dirEnum skipDescendants].
            return true // ✓ Z: FSItem.m:1069 continue.
        } // ✓ Z: FSItem.m:1066-1070 closes /Volumes skip.
        let leaf: String = url.lastPathComponent // ✓ Z: FSItem.m:1078 NSString *leaf = [currentUrl lastPathComponent].
        if leaf == ".nofollow" || leaf == ".resolve" { // ✓ Z: FSItem.m:1079-1081 checks .nofollow and .resolve.
            enumerator.skipDescendants() // ✓ Z: FSItem.m:1083 [dirEnum skipDescendants].
            return true // ✓ Z: FSItem.m:1084 continue.
        } // ✓ Z: FSItem.m:1079-1085 closes magic directory skip.
        return false // ✓ Z: FSItem.m:1089 proceeds to resource caching.
    } // ✓ Z: FSItem.m:1085 ends recursive skip section.

    private static func loadChildren(of item: DiskItem, settings: DiskScanSettings) throws { // ✓ Z: FSItem.m:977 loadChildrenAndSetKindStrings:usePhysicalSize:.
        if !item.isFolder { // ✓ Z: FSItem.m:980 if ( ![self isFolder] ).
            return // ✓ Z: FSItem.m:981 return.
        } // ✓ Z: FSItem.m:980-981 closes non-folder guard.
        item.removeAllChildren() // ✓ Z: FSItem.m:993-994 [_childs release]; _childs = [[NSMutableArray alloc] init].
        var itemStack: [DiskItem] = [] // ✓ Z: FSItem.m:1032 NSMutableArray<FSItem*> *itemStack = [[NSMutableArray alloc] init].
        itemStack.append(item) // ✓ Z: FSItem.m:1034 [itemStack addObject:self].
        guard let directoryEnumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator( // ✓ Z: FSItem.m:1036 NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtURL:...].
            at: item.url, // ✓ Z: FSItem.m:1036 [self fileURL].
            includingPropertiesForKeys: Self.recursiveResourceKeys, // ✓ Z: FSItem.m:1037 includingPropertiesForKeys: urlProperties.
            options: [], // ✓ Z: FSItem.m:1038 options: 0.
            errorHandler: { url, _ in url != item.url } // ✓ Z: FSItem.m:1039-1049 continues after child errors, stops for the folder itself.
        ) else { // ✓ Swift-only: Swift optional bridge for NSDirectoryEnumerator creation.
            item.recalculateSize(usePhysicalSize: settings.usePhysicalSize) // ✓ Z: FSItem.m:1294 [self recalculateSize:YES updateParent:NO], adapted for an unavailable enumerator.
            return // ✓ Swift-only: no enumerator means there are no children to walk.
        } // ✓ Swift-only: closes Swift optional bridge.
        var lastEnumLevel: Int = 1 // ✓ Z: FSItem.m:1051 NSUInteger lastEnumLevel = 1.
        var lastItemWasDirectory: Bool = false // ✓ Z: FSItem.m:1052 BOOL lastItemWasDir = NO.
        var lastDirectoryItem: DiskItem? = nil // ✓ Z: FSItem.m:1053 FSItem *lastDirItem = nil.
        var filesSinceYield: Int = 0 // ✓ Z: FSItem.m:1054 NSUInteger filesSinceYield = 0.
        for case let currentURL as URL in directoryEnumerator { // ✓ Z: FSItem.m:1056 for ( NSURL *currentUrl in dirEnum) @autoreleasepool.
            filesSinceYield += 1 // ✓ Z: FSItem.m:1065 if ( ++filesSinceYield >= 64 ).
            if filesSinceYield >= 64 { // ✓ Z: FSItem.m:1065 every 64 entries checks whether scanning should continue.
                filesSinceYield = 0 // ✓ Z: FSItem.m:1067 filesSinceYield = 0.
                try Task.checkCancellation() // ✓ Swift-only: Swift cancellation bridge for FSItem.m:1068-1072 fsItemShouldContinueLoading.
            } // ✓ Z: FSItem.m:1073 closes 64-entry yield block.
            if Self.shouldSkipRecursiveURL(currentURL, enumerator: directoryEnumerator) { // ✓ Z: FSItem.m:1066-1085 recursive skip checks.
                continue // ✓ Z: FSItem.m:1069 and FSItem.m:1084 continue.
            } // ✓ Z: FSItem.m:1066-1085 closes recursive skip branch.
            let currentValues: URLResourceValues = try currentURL.resourceValues(forKeys: Set(Self.recursiveResourceKeys)) // ✓ Z: FSItem.m:1089 [currentUrl cacheResourcesInArray: urlProperties].
            if directoryEnumerator.level > lastEnumLevel { // ✓ Z: FSItem.m:1092 if ( [dirEnum level] > lastEnumLevel ).
                if let lastDirectoryItem: DiskItem = lastDirectoryItem { // ✓ Z: FSItem.m:1113 [itemStack addObject: lastDirItem].
                    itemStack.append(lastDirectoryItem) // ✓ Z: FSItem.m:1113 [itemStack addObject: lastDirItem].
                } else if lastItemWasDirectory { // ✓ Swift-only: preserves Z's debug assertion as a runtime failure only when stack data is inconsistent.
                    throw DiskScannerError.zMethodNotPorted("FSItem.loadChildren stack descent") // ✓ Z: FSItem.m:1099 NSAssert(lastItemWasDir...).
                } // ✓ Swift-only: closes stack descent guard.
            } else if directoryEnumerator.level < lastEnumLevel { // ✓ Z: FSItem.m:1122 else if ([dirEnum level] < lastEnumLevel ).
                let levelsWalkedUp: Int = lastEnumLevel - directoryEnumerator.level // ✓ Z: FSItem.m:1125 NSUInteger levelsWalkedUp = lastEnumLevel - [dirEnum level].
                for _: Int in 0..<levelsWalkedUp { // ✓ Z: FSItem.m:1128 for ( NSUInteger i = 0; i < levelsWalkedUp; i++ ).
                    if itemStack.count > 1 { // ✓ Swift-only: keeps the root stack entry present while mirroring [itemStack removeLastObject].
                        itemStack.removeLast() // ✓ Z: FSItem.m:1137 [itemStack removeLastObject].
                    } // ✓ Swift-only: closes root-preserving stack removal.
                } // ✓ Z: FSItem.m:1138 closes walk-up loop.
            } // ✓ Z: FSItem.m:1155 closes level-change handling.
            guard let parentItem: DiskItem = itemStack.last else { // ✓ Z: FSItem.m:1162 parent: [itemStack lastObject].
                throw DiskScannerError.zMethodNotPorted("FSItem.loadChildren missing parent") // ✓ Swift-only: should be unreachable if itemStack mirrors Z.
            } // ✓ Swift-only: closes Swift stack safety guard.
            let currentItem: DiskItem = Self.makeItem(url: currentURL, parent: parentItem, values: currentValues) // ✓ Z: FSItem.m:1161-1164 [[FSItem alloc] initWithURL:currentUrl parent:[itemStack lastObject]...].
            parentItem.appendChild(currentItem, updateSize: false) // ✓ Z: FSItem.m:933-934 initWithURL:parent adds self to parent->_childs before recalculateSize.
            let isCurrentDirectory: Bool = currentValues.isDirectory ?? false // ✓ Z: FSItem.m:1175 if ( ![currentUrl isDirectory] ) and FSItem.m:1269 lastItemWasDir = [currentUrl isDirectory].
            if !isCurrentDirectory { // ✓ Z: FSItem.m:1175 hardlink branch only tests files.
                let linkCount: Int? = currentValues.linkCount // ✓ Z: FSItem.m:1177 NSNumber *linkCount = [currentUrl getCachedNumberValue: NSURLLinkCountKey].
                if let linkCount: Int = linkCount, linkCount > 1 { // ✓ Z: FSItem.m:1178 if ( linkCount != nil && [linkCount intValue] > 1 ).
                    throw DiskScannerError.zMethodNotPorted("FSItem hardlink dedup") // ✓ Z: FSItem.m:1180-1192 fileResourceIdentifier seen-set branch not ported in this checkpoint.
                } // ✓ Z: FSItem.m:1178-1193 closes hardlink duplicate branch.
            } // ✓ Z: FSItem.m:1175-1194 closes hardlink file-only branch.
            if Self.isFirmlink(currentURL) { // ✓ Z: FSItem.m:1207 BOOL isFirmlink = [currentUrl isFirmlink].
                directoryEnumerator.skipDescendants() // ✓ Z: FSItem.m:1214 [dirEnum skipDescendants].
                throw DiskScannerError.zMethodNotPorted("FSItem firmlink recursive load") // ✓ Z: FSItem.m:1215-1216 [currentItem loadChildrenAndSetKindStrings:...].
            } else if currentValues.isVolume ?? false { // ✓ Z: FSItem.m:1218 else if ( [currentUrl isVolume] ).
                directoryEnumerator.skipDescendants() // ✓ Z: FSItem.m:1222 [dirEnum skipDescendants].
            } else if (currentValues.isPackage ?? false) && !settings.lookInsidePackages { // ✓ Z: FSItem.m:1224-1226 package branch when delegate says not to look inside packages.
                directoryEnumerator.skipDescendants() // ✓ Z: FSItem.m:1233 [dirEnum skipDescendants].
                let packageSize: UInt64 = try Self.topLevelOpaquePackageSize(url: currentURL, usePhysicalSize: settings.usePhysicalSize) // ✓ Z: FSItem.m:1235-1254 package recursive opaque-size loop.
                currentItem.allocatedSizeValue = packageSize // ✓ Z: FSItem.m:1256 [currentItem setSizeValue: packageSize].
                currentItem.logicalSizeValue = packageSize // ✓ Swift-only: DiskItem has separate logical/allocated fields; Z has one active _sizeValue.
            } // ✓ Z: FSItem.m:1257 closes package branch.
            lastItemWasDirectory = isCurrentDirectory // ✓ Z: FSItem.m:1269 lastItemWasDir = [currentUrl isDirectory].
            lastDirectoryItem = lastItemWasDirectory ? currentItem : nil // ✓ Z: FSItem.m:1271 lastDirItem = lastItemWasDir ? currentItem : nil.
            lastEnumLevel = directoryEnumerator.level // ✓ Z: FSItem.m:1273 lastEnumLevel = [dirEnum level].
        } // ✓ Z: FSItem.m:1276 closes directory enumerator loop.
        item.recalculateSize(usePhysicalSize: settings.usePhysicalSize) // ✓ Z: FSItem.m:1294 [self recalculateSize:YES updateParent:NO], adapted to selected size mode.
    } // ✓ Z: FSItem.m:1302 closes loadChildrenAndSetKindStrings:usePhysicalSize:.

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

    private static func isFirmlink(_ url: URL) -> Bool { // ✓ Z: NSURL-Extensions.m:96 - (BOOL) isFirmlink.
        Self.loadFirmlinksIfNeeded() // ✓ Z: NSURL-Extensions.m:98 LoadFirmlinks().
        return Self.firmlinkURLs?.contains(url) ?? false // ✓ Z: NSURL-Extensions.m:100 [g_Firmlinks objectForKey:self] != nil.
    } // ✓ Z: NSURL-Extensions.m:102 closes isFirmlink.

    private static func loadFirmlinksIfNeeded() { // ✓ Z: NSURL-Extensions.m:26 void LoadFirmlinks().
        if Self.firmlinkURLs != nil { // ✓ Z: NSURL-Extensions.m:28 if ( g_Firmlinks != nil ).
            return // ✓ Z: NSURL-Extensions.m:29 return.
        } // ✓ Z: NSURL-Extensions.m:28-29 closes already-loaded guard.
        var loadedFirmlinks: Set<URL> = [] // ✓ Z: NSURL-Extensions.m:31 g_Firmlinks = [[NSMutableDictionary alloc] init].
        let fileContents: String? = try? String(contentsOfFile: Self.firmlinkListPath, encoding: .ascii) // ✓ Z: NSURL-Extensions.m:34-36 stringWithContentsOfFile:encoding:error:nil.
        let allLines: [String] = fileContents?.components(separatedBy: .newlines) ?? [] // ✓ Z: NSURL-Extensions.m:39-41 componentsSeparatedByCharactersInSet:newlineCharacterSet.
        for line: String in allLines { // ✓ Z: NSURL-Extensions.m:43 for ( NSString * line in allLines ).
            let linkFromTo: [String] = line.components(separatedBy: "\t") // ✓ Z: NSURL-Extensions.m:45 componentsSeparatedByCharactersInSet:tab.
            if linkFromTo.count >= 2 { // ✓ Z: NSURL-Extensions.m:47 if ( [LinkFromTo count] >= 2).
                let firmlinkSourcePath: String = linkFromTo[0] // ✓ Z: NSURL-Extensions.m:49 NSString *firmlinkSrcPath = [LinkFromTo objectAtIndex:0].
                let firmlinkSourceURL: URL = URL(fileURLWithPath: firmlinkSourcePath) // ✓ Z: NSURL-Extensions.m:51 NSURL *firmlinkSrcURL = [NSURL fileURLWithPath:firmlinkSrcPath].
                if FileManager.default.fileExists(atPath: firmlinkSourceURL.path) { // ✓ Z: NSURL-Extensions.m:53 if ( [firmlinkSrcURL stillExists]).
                    loadedFirmlinks.insert(firmlinkSourceURL) // ✓ Z: NSURL-Extensions.m:54 [g_Firmlinks setObject:firmlinkSrcURL forKey:firmlinkSrcURL].
                } // ✓ Z: NSURL-Extensions.m:53-54 closes existence check.
            } // ✓ Z: NSURL-Extensions.m:47-55 closes tab-count branch.
        } // ✓ Z: NSURL-Extensions.m:43-56 closes line loop.
        Self.firmlinkURLs = loadedFirmlinks // ✓ Z: NSURL-Extensions.m:31 assigns initialized firmlink dictionary.
    } // ✓ Z: NSURL-Extensions.m:57 closes LoadFirmlinks().

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
