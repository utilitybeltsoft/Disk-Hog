import Foundation
import UniformTypeIdentifiers


nonisolated final class DiskInventoryZScanner {
    typealias ProgressHandler = @Sendable (DiskScanProgress) async -> Void
    typealias ResourceValuesProvider = @Sendable (URL, Set<URLResourceKey>) throws -> URLResourceValues

    private let hardlinkDeduplicator: HardlinkDeduplicator
    private var kindNameByTypeIdentifier: [String: String] = [:]
    private let recursiveResourceValuesProvider: ResourceValuesProvider
    private static let firmlinkURLs: Set<URL> = DiskInventoryZScanner.loadFirmlinks()
    private static let firmlinkListPath: String = "/usr/share/firmlinks"
    fileprivate static let progressRefreshInterval: TimeInterval = 0.25

    private static let topLevelResourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isVolumeKey,
        .nameKey, .typeIdentifierKey,
        .fileSizeKey, .totalFileAllocatedSizeKey,
        .isExecutableKey, .isSymbolicLinkKey,
        .linkCountKey, .fileResourceIdentifierKey
    ]

    private static let recursiveResourceKeys: [URLResourceKey] = [
        .nameKey,
        .isVolumeKey,
        .isPackageKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .typeIdentifierKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .isExecutableKey,
        .linkCountKey,
        .fileResourceIdentifierKey
    ]

    init(
        recursiveResourceValuesProvider: @escaping ResourceValuesProvider = { url, keys in
            try url.resourceValues(forKeys: keys)
        }
    ) {
        self.recursiveResourceValuesProvider = recursiveResourceValuesProvider
        self.hardlinkDeduplicator = HardlinkDeduplicator()
    }

    private init(
        recursiveResourceValuesProvider: @escaping ResourceValuesProvider,
        hardlinkDeduplicator: HardlinkDeduplicator = HardlinkDeduplicator()
    ) {
        self.recursiveResourceValuesProvider = recursiveResourceValuesProvider
        self.hardlinkDeduplicator = hardlinkDeduplicator
    }

    func scan(
        source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault,
        progressHandler: ProgressHandler? = nil
    ) async throws -> DiskItem {
        try Task.checkCancellation()

        let rootURL: URL = try source.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }
        resetHardlinkDedup()
        let rootItem: DiskItem = makeItem(url: rootURL, parent: nil, values: nil)
        var progressState: ScanProgressState = ScanProgressState(currentPath: rootURL.path)

        await progressHandler?(progressState.snapshot())

        let topLevelChildren: [URL]
        do {
            topLevelChildren = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: Self.topLevelResourceKeys,
                options: []
            )
        } catch {
            throw DiskScannerError.topLevelEnumerationFailed(path: rootURL.path, underlyingDescription: error.localizedDescription)
        }

        let progressAggregator: ScanProgressAggregator = ScanProgressAggregator(currentPath: rootURL.path)
        var topLevelWorkItems: [TopLevelScanWorkItem] = []
        for (sourceOrder, childURL) in topLevelChildren.enumerated() {
            try Task.checkCancellation()
            if Self.shouldSkipTopLevelURL(childURL) {
                continue
            }

            let values: URLResourceValues
            do {
                values = try recursiveResourceValuesProvider(childURL, Set(Self.topLevelResourceKeys))
            } catch {
                continue
            }
            topLevelWorkItems.append(
                TopLevelScanWorkItem(
                    sourceOrder: sourceOrder,
                    item: makeItem(url: childURL, parent: nil, values: values),
                    isDirectory: values.isDirectory ?? false,
                    isPackage: values.isPackage ?? false,
                    isVolume: values.isVolume ?? false,
                    values: values
                )
            )
        }

        try await withThrowingTaskGroup(of: TopLevelScanResult.self) { taskGroup in
            for workItem: TopLevelScanWorkItem in topLevelWorkItems {
                let settings: DiskScanSettings = settings
                let recursiveResourceValuesProvider: ResourceValuesProvider = recursiveResourceValuesProvider
                let hardlinkDeduplicator: HardlinkDeduplicator = hardlinkDeduplicator
                let progressAggregator: ScanProgressAggregator = progressAggregator
                let progressHandler: ProgressHandler? = progressHandler

                taskGroup.addTask {
                    let scanner: DiskInventoryZScanner = DiskInventoryZScanner(
                        recursiveResourceValuesProvider: recursiveResourceValuesProvider,
                        hardlinkDeduplicator: hardlinkDeduplicator
                    )
                    return try await scanner.scanTopLevelWorkItem(
                        workItem,
                        settings: settings,
                        progressAggregator: progressAggregator,
                        progressHandler: progressHandler
                    )
                }
            }

            for try await result: TopLevelScanResult in taskGroup {
                rootItem.appendChild(result.item, updateSize: true)
            }
        }

        rootItem.sortChildrenInDiskInventoryZOrder(recursive: false, usePhysicalSize: settings.usePhysicalSize)
        progressState.setScannedBytes(rootItem.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        progressState.setScannedFileCount(await progressAggregator.scannedFileCount)
        progressState.setScannedFolderCount(await progressAggregator.scannedFolderCount)
        await progressHandler?(progressState.snapshot())
        return rootItem
    }

    private func scanTopLevelWorkItem(
        _ workItem: TopLevelScanWorkItem,
        settings: DiskScanSettings,
        progressAggregator: ScanProgressAggregator,
        progressHandler: ProgressHandler?
    ) async throws -> TopLevelScanResult {
        try Task.checkCancellation()

        var progressState: ScanProgressState = ScanProgressState(currentPath: workItem.item.path)
        progressState.recordItem(workItem.item)

        if workItem.isDirectory && !workItem.isVolume && (!workItem.isPackage || settings.lookInsidePackages) {
            progressState = try await loadChildren(
                of: workItem.item,
                settings: settings,
                progressState: progressState
            ) { progress in
                if let snapshot: DiskScanProgress = await progressAggregator.updateChild(
                    id: workItem.sourceOrder,
                    progress: progress
                ) {
                    await progressHandler?(snapshot)
                }
            }
        } else if workItem.isDirectory && workItem.isPackage && !settings.lookInsidePackages {
            let packageSize: OpaquePackageSize = try Self.opaquePackageSize(url: workItem.item.url)
            workItem.item.allocatedSizeValue = packageSize.allocated
            workItem.item.logicalSizeValue = packageSize.logical
            progressState.setScannedBytes(workItem.item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        } else if !workItem.isDirectory {
            markHardlinkDuplicateIfNeeded(item: workItem.item, values: workItem.values)
            progressState.setScannedBytes(workItem.item.isHardlinkDuplicate ? 0 : workItem.item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        }

        progressState.updateCurrentPath(workItem.item.path)
        let aggregateProgress: DiskScanProgress = await progressAggregator.finishChild(
            id: workItem.sourceOrder,
            progress: progressState.snapshot()
        )
        await progressHandler?(aggregateProgress)

        return TopLevelScanResult(
            sourceOrder: workItem.sourceOrder,
            item: workItem.item
        )
    }

    private static func shouldSkipTopLevelURL(_ url: URL) -> Bool {
        shouldSkipURL(url)
    }

    private static func shouldSkipRecursiveURL(_ url: URL, enumerator: FileManager.DirectoryEnumerator) -> Bool {
        guard shouldSkipURL(url) else {
            return false
        }

        enumerator.skipDescendants()
        return true
    }

    private static func shouldSkipURL(_ url: URL) -> Bool {
        if url.path == "/Volumes" {
            return true
        }
        let leaf: String = url.lastPathComponent
        if leaf == ".nofollow" || leaf == ".resolve" {
            return true
        }
        return false
    }

    private func loadChildren(
        of item: DiskItem,
        settings: DiskScanSettings,
        progressState: ScanProgressState,
        progressHandler: ProgressHandler?
    ) async throws -> ScanProgressState {
        var progressState: ScanProgressState = progressState
        if !item.isFolder {
            return progressState
        }
        progressState.updateCurrentPath(item.path)
        if progressState.shouldPublish() { await progressHandler?(progressState.snapshot()) }
        item.removeAllChildren()
        var itemStack: [DiskItem] = []
        itemStack.append(item)
        guard let directoryEnumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(
            at: item.url,
            includingPropertiesForKeys: Self.recursiveResourceKeys,
            options: [],
            errorHandler: { url, _ in url != item.url }
        ) else {
            item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
            progressState.setScannedBytes(item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
            return progressState
        }
        var lastEnumLevel: Int = 1
        var lastItemWasDirectory: Bool = false
        var lastDirectoryItem: DiskItem? = nil
        var filesSinceYield: Int = 0
        while let currentURL: URL = directoryEnumerator.nextObject() as? URL {
            filesSinceYield += 1
            if filesSinceYield >= 64 {
                filesSinceYield = 0
                try Task.checkCancellation()
                if progressState.shouldPublish() { await progressHandler?(progressState.snapshot()) }
            }
            if Self.shouldSkipRecursiveURL(currentURL, enumerator: directoryEnumerator) {
                continue
            }
            let currentValues: URLResourceValues
            do {
                currentValues = try recursiveResourceValuesProvider(currentURL, Set(Self.recursiveResourceKeys))
            } catch {
                directoryEnumerator.skipDescendants()
                continue
            }
            if directoryEnumerator.level > lastEnumLevel {
                if let lastDirectoryItem: DiskItem = lastDirectoryItem {
                    itemStack.append(lastDirectoryItem)
                } else if lastItemWasDirectory {
                    throw DiskScannerError.traversalInconsistency("A directory was reported without a matching item.")
                }
            } else if directoryEnumerator.level < lastEnumLevel {
                let levelsWalkedUp: Int = lastEnumLevel - directoryEnumerator.level
                for _: Int in 0..<levelsWalkedUp {
                    if itemStack.count > 1 {
                        itemStack.removeLast()
                    }
                }
            }
            guard let parentItem: DiskItem = itemStack.last else {
                throw DiskScannerError.traversalInconsistency("A child item was reported without a parent.")
            }
            let currentItem: DiskItem = makeItem(url: currentURL, parent: parentItem, values: currentValues)
            parentItem.appendChild(currentItem, updateSize: false)
            progressState.recordItem(currentItem)
            let isCurrentDirectory: Bool = currentValues.isDirectory ?? false
            if !isCurrentDirectory {
                markHardlinkDuplicateIfNeeded(item: currentItem, values: currentValues)
            }
            if Self.isFirmlink(currentURL) {
                directoryEnumerator.skipDescendants()
                progressState = try await loadChildren(
                    of: currentItem,
                    settings: settings,
                    progressState: progressState,
                    progressHandler: progressHandler
                )
            } else if currentValues.isVolume ?? false {
                directoryEnumerator.skipDescendants()
            } else if (currentValues.isPackage ?? false) && !settings.lookInsidePackages {
                directoryEnumerator.skipDescendants()
                let packageSize: OpaquePackageSize = try Self.opaquePackageSize(url: currentURL)
                currentItem.allocatedSizeValue = packageSize.allocated
                currentItem.logicalSizeValue = packageSize.logical
            } else if !isCurrentDirectory {
                progressState.addScannedBytes(currentItem.isHardlinkDuplicate ? 0 : currentItem.sizeValue(usePhysicalSize: settings.usePhysicalSize))
            }
            if isCurrentDirectory { progressState.updateCurrentPath(currentURL.path) }
            lastItemWasDirectory = isCurrentDirectory
            lastDirectoryItem = lastItemWasDirectory ? currentItem : nil
            lastEnumLevel = directoryEnumerator.level
        }
        item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
        progressState.setScannedBytes(item.sizeValue(usePhysicalSize: settings.usePhysicalSize))
        return progressState
    }

    private func resetHardlinkDedup() {
        hardlinkDeduplicator.reset()
    }

    private func markHardlinkDuplicateIfNeeded(item: DiskItem, values: URLResourceValues) {
        guard let linkCount: Int = values.linkCount,
              linkCount > 1,
              let fileIdentifier: Any = values.fileResourceIdentifier else {
            return
        }

        item.isHardlinkDuplicate = hardlinkDeduplicator.isDuplicate(fileIdentifier)
    }

    private static func opaquePackageSize(url: URL) throws -> OpaquePackageSize {
        var packageSize: OpaquePackageSize = OpaquePackageSize()
        let packageKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let packageEnumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: packageKeys,
            options: [],
            errorHandler: nil
        ) else {
            return packageSize
        }
        for case let descendantURL as URL in packageEnumerator {
            try Task.checkCancellation()
            let descendantValues: URLResourceValues? = try? descendantURL.resourceValues(forKeys: Set(packageKeys))
            if let allocatedSize: Int = descendantValues?.totalFileAllocatedSize ?? descendantValues?.fileAllocatedSize {
                packageSize.allocated += UInt64(allocatedSize)
            }
            if let logicalSize: Int = descendantValues?.fileSize {
                packageSize.logical += UInt64(logicalSize)
            }
        }
        return packageSize
    }

    private static func isFirmlink(_ url: URL) -> Bool {
        Self.firmlinkURLs.contains(url)
    }

    private static func loadFirmlinks() -> Set<URL> {
        var loadedFirmlinks: Set<URL> = []
        let fileContents: String? = try? String(contentsOfFile: Self.firmlinkListPath, encoding: .ascii)
        let allLines: [String] = fileContents?.components(separatedBy: .newlines) ?? []
        for line: String in allLines {
            let linkFromTo: [String] = line.components(separatedBy: "\t")
            if linkFromTo.count >= 2 {
                let firmlinkSourcePath: String = linkFromTo[0]
                let firmlinkSourceURL: URL = URL(fileURLWithPath: firmlinkSourcePath)
                if FileManager.default.fileExists(atPath: firmlinkSourceURL.path) {
                    loadedFirmlinks.insert(firmlinkSourceURL)
                }
            }
        }
        return loadedFirmlinks
    }

    private func makeItem(url: URL, parent: DiskItem?, values: URLResourceValues?) -> DiskItem {
        let isDirectory: Bool = values?.isDirectory ?? url.hasDirectoryPath
        let isPackage: Bool = values?.isPackage ?? false
        let isSymbolicLink: Bool = values?.isSymbolicLink ?? false
        let allocatedSize: UInt64 = UInt64(values?.totalFileAllocatedSize ?? 0)
        let logicalSize: UInt64 = UInt64(values?.fileSize ?? 0)
        let name: String = values?.name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        let kindName: String? = kindName(for: url, values: values, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
        return DiskItem(
            url: url,
            parent: parent,
            name: name,
            allocatedSizeValue: isDirectory ? 0 : allocatedSize,
            logicalSizeValue: isDirectory ? 0 : logicalSize,
            kindName: kindName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isAliasOrSymbolicLink: isSymbolicLink
        )
    }

    private func kindName(for url: URL, values: URLResourceValues?, isDirectory: Bool, isSymbolicLink: Bool) -> String? {
        let typeIdentifier: String? = values?.typeIdentifier ?? ((try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier)
        guard let typeIdentifier: String = typeIdentifier else {
            return Self.fallbackKindName(for: url, values: values, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
        }
        if let cachedKindName: String = kindNameByTypeIdentifier[typeIdentifier] {
            return cachedKindName
        }
        var resolvedKindName: String? = UTType(typeIdentifier)?.localizedDescription
        if resolvedKindName == nil {
            resolvedKindName = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        }
        if let resolvedKindName: String = resolvedKindName {
            kindNameByTypeIdentifier[typeIdentifier] = resolvedKindName
        }
        return resolvedKindName ?? Self.fallbackKindName(for: url, values: values, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
    }

    private static func fallbackKindName(for url: URL, values: URLResourceValues?, isDirectory: Bool, isSymbolicLink: Bool) -> String? {
        if isSymbolicLink { return "symbolic link" }
        let extensionKey: String = url.pathExtension.lowercased()
        if isDirectory { return Self.directoryKindByExtension[extensionKey] ?? "folder" }
        if extensionKey.isEmpty { return Self.executableFallbackKind(for: url, values: values) }
        return Self.fileKindByExtension[extensionKey] ?? "Document"
    }

    private static func executableFallbackKind(for url: URL, values: URLResourceValues?) -> String {
        let isExecutable: Bool? = values?.isExecutable ?? ((try? url.resourceValues(forKeys: [.isExecutableKey]))?.isExecutable)
        return isExecutable == true ? "Unix executable" : "data"
    }

    private static let directoryKindByExtension: [String: String] = [
        "app": "application",
        "bundle": "bundle",
        "framework": "framework",
        "xcodeproj": "Xcode Project",
        "xcworkspace": "Xcode Workspace",
        "xcassets": "Xcode Asset Catalog",
        "4dbase": "4D Database Package",
        "dsym": "Package"
    ]

    private static let fileKindByExtension: [String: String] = [
        "php": "PHP script", "py": "Python script", "pyc": "Python Bytecode", "h": "C header code",
        "rag": "Document", "js": "JavaScript", "pcm": "Document", "md": "Markdown Text",
        "json": "JSON", "txt": "text", "ts": "MPEG-2 Transport Stream", "png": "PNG image",
        "pyi": "Document", "d": "Source", "dart": "Document", "stamp": "Document",
        "xml": "XML text", "dia": "Document", "o": "object code", "obj": "Geometry Definition File Format",
        "mtl": "OBJ material file", "scan": "Document", "jpg": "JPEG image", "class": "Java class",
        "so": "Document", "bin": "MacBinary archive", "plist": "property list", "cmake": "Document",
        "len": "Document", "xcconfig": "Xcode Configuration Settings", "yaml": "YAML", "yml": "YAML",
        "map": "MAP file", "modulemap": "Module Map", "flat": "Document", "mat": "Document",
        "pyd": "Document", "dex": "Document", "sample": "Document", "swiftmodule": "Document",
        "c": "C source code", "pdf": "PDF document", "cpp": "C++ source code", "dill": "Document",
        "m": "Objective-C source code", "swift": "Swift Source Code", "zip": "Zip archive", "csv": "comma-separated values",
        "dat": "DAT file", "attrs": "Document", "swiftdeps": "Document", "swiftconstvalues": "Document",
        "sh": "shell script", "jar": "Java archive", "afm": "Document", "swiftsourceinfo": "Document",
        "swiftdoc": "Document", "a": "Ar archive", "hmap": "Document", "timestamp": "Document",
        "xls": "Microsoft Excel 97-2004 worksheet", "p": "Pascal source", "xcfilelist": "Build Phase File List", "f90": "Fortran source code",
        "tab": "Tab Separated Data File", "ninja": "Document", "typed": "Document", "cuh": "Document",
        "ttf": "TrueType® OpenType® font", "jpeg": "JPEG image", "sav": "Parallels VM state image", "svg": "SVG image",
        "css": "CSS", "lib": "Document", "properties": "Java properties file", "hpp": "C++ header code",
        "log": "text", "dylib": "Mach-O dynamic library", "xlsx": "Office Open XML spreadsheet", "html": "HTML text",
        "cc": "C++ source code", "docx": "Office Open XML word processing document", "mjs": "JavaScript", "npz": "Document",
        "exe": "Microsoft Windows application", "indd": "Adobe InDesign Document", "rtf": "rich text (RTF)", "wav": "Waveform audio",
        "sql": "SQL File", "frag": "OpenGL Fragment Shader Source", "cnv": "Canvas 3.5 Document", "psd": "Adobe Photoshop document",
        "gz": "GZip archive", "mts": "AVCHD MPEG-2 Transport Stream", "eps": "Encapsulated PostScript®", "cvd": "Canvas Draw Document",
        "4dd": "4D Data File", "4db": "4D interpreted Structure File", "memmap": "Document", "ds_store": "Document"
    ]
}

private nonisolated struct OpaquePackageSize: Sendable {
    var allocated: UInt64 = 0
    var logical: UInt64 = 0
}

private nonisolated struct TopLevelScanWorkItem: @unchecked Sendable {
    let sourceOrder: Int
    let item: DiskItem
    let isDirectory: Bool
    let isPackage: Bool
    let isVolume: Bool
    let values: URLResourceValues
}

private nonisolated struct TopLevelScanResult: Sendable {
    let sourceOrder: Int
    let item: DiskItem
}

// Hardlink byte ownership is intentionally first-claimer-wins across parallel
// subtree scans. Grand totals remain deterministic, but per-folder attribution
// for multiply-linked files can vary with task scheduling. If deterministic
// attribution becomes important, resolve ownership after scanning by path order.
private nonisolated final class HardlinkDeduplicator: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private let seenFileIdentifiers: NSMutableSet = NSMutableSet()

    func reset() {
        lock.withLock {
            seenFileIdentifiers.removeAllObjects()
        }
    }

    func isDuplicate(_ fileIdentifier: Any) -> Bool {
        lock.withLock {
            if seenFileIdentifiers.contains(fileIdentifier) {
                return true
            }

            seenFileIdentifiers.add(fileIdentifier)
            return false
        }
    }
}

private actor ScanProgressAggregator {
    private var activeProgressByChild: [Int: DiskScanProgress] = [:]
    private var completedFileCount: Int = 0
    private var completedFolderCount: Int = 0
    private var completedByteCount: UInt64 = 0
    private var currentPath: String
    private var lastPublishTime: CFAbsoluteTime = 0
    private var lastPublishedByteCount: UInt64 = 0

    init(currentPath: String) {
        self.currentPath = currentPath
    }

    var scannedFileCount: Int {
        completedFileCount + activeProgressByChild.values.reduce(0) { $0 + $1.scannedFileCount }
    }

    var scannedFolderCount: Int {
        completedFolderCount + activeProgressByChild.values.reduce(0) { $0 + $1.scannedFolderCount }
    }

    func updateChild(id: Int, progress: DiskScanProgress) -> DiskScanProgress? {
        activeProgressByChild[id] = progress
        currentPath = progress.currentPath
        guard shouldPublish() else {
            return nil
        }

        return snapshot()
    }

    func finishChild(id: Int, progress: DiskScanProgress) -> DiskScanProgress {
        activeProgressByChild[id] = nil
        completedFileCount += progress.scannedFileCount
        completedFolderCount += progress.scannedFolderCount
        completedByteCount += progress.scannedByteCount
        currentPath = progress.currentPath
        return snapshot()
    }

    private func shouldPublish() -> Bool {
        let now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        if lastPublishTime != 0 && now - lastPublishTime < DiskInventoryZScanner.progressRefreshInterval {
            return false
        }
        lastPublishTime = now
        return true
    }

    private func snapshot() -> DiskScanProgress {
        let activeProgress: [DiskScanProgress] = Array(activeProgressByChild.values)
        let computedByteCount: UInt64 = completedByteCount + activeProgress.reduce(0) { $0 + $1.scannedByteCount }
        let byteCount: UInt64 = max(lastPublishedByteCount, computedByteCount)
        lastPublishedByteCount = byteCount

        return DiskScanProgress(
            scannedFileCount: completedFileCount + activeProgress.reduce(0) { $0 + $1.scannedFileCount },
            scannedFolderCount: completedFolderCount + activeProgress.reduce(0) { $0 + $1.scannedFolderCount },
            scannedByteCount: byteCount,
            currentPath: currentPath
        )
    }
}

nonisolated private struct ScanProgressState {
    private(set) var scannedFileCount: Int = 0
    private(set) var scannedFolderCount: Int = 0
    private(set) var scannedByteCount: UInt64 = 0
    private(set) var currentPath: String
    private var lastPublishTime: CFAbsoluteTime = 0

    init(currentPath: String) {
        self.currentPath = currentPath
    }

    mutating func recordItem(_ item: DiskItem) {
        if item.isFolder {
            scannedFolderCount += 1
        } else {
            scannedFileCount += 1
        }
    }

    mutating func setScannedFileCount(_ count: Int) {
        scannedFileCount = count
    }

    mutating func setScannedFolderCount(_ count: Int) {
        scannedFolderCount = count
    }

    mutating func addScannedBytes(_ byteCount: UInt64) {
        scannedByteCount += byteCount
    }

    mutating func setScannedBytes(_ byteCount: UInt64) {
        scannedByteCount = byteCount
    }

    mutating func updateCurrentPath(_ path: String) {
        currentPath = path
    }

    mutating func shouldPublish() -> Bool {
        let now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        if lastPublishTime != 0 && now - lastPublishTime < DiskInventoryZScanner.progressRefreshInterval {
            return false
        }
        lastPublishTime = now
        return true
    }

    func snapshot() -> DiskScanProgress {
        DiskScanProgress(
            scannedFileCount: scannedFileCount,
            scannedFolderCount: scannedFolderCount,
            scannedByteCount: scannedByteCount,
            currentPath: currentPath
        )
    }
}
