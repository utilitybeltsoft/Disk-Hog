import Foundation
import UniformTypeIdentifiers


nonisolated final class DiskInventoryZScanner {
    typealias ProgressHandler = @Sendable (DiskScanProgress) -> Void

    private let seenHardlinkInodes: NSMutableSet = NSMutableSet()
    private var kindNameByTypeIdentifier: [String: String] = [:]
    private static let firmlinkURLs: Set<URL> = DiskInventoryZScanner.loadFirmlinks()
    private static let firmlinkListPath: String = "/usr/share/firmlinks"
    fileprivate static let progressRefreshInterval: TimeInterval = 0.25

    private static let topLevelResourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isVolumeKey,
        .nameKey, .typeIdentifierKey,
        .fileSizeKey, .totalFileAllocatedSizeKey
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
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .linkCountKey,
        .fileResourceIdentifierKey
    ]

    func scan(
        source: ScanSource,
        settings: DiskScanSettings = .diskInventoryZDefault,
        progressHandler: ProgressHandler? = nil
    ) throws -> DiskItem {
        try Task.checkCancellation()

        let rootURL: URL = try source.resolvedURL()
        let didStartSecurityScopedAccess: Bool = rootURL.startAccessingSecurityScopedResource()
        defer { if didStartSecurityScopedAccess { rootURL.stopAccessingSecurityScopedResource() } }
        resetHardlinkDedup()
        let rootItem: DiskItem = makeItem(url: rootURL, parent: nil, values: nil)
        var progressState: ScanProgressState = ScanProgressState(currentPath: rootURL.path)

        progressHandler?(
            progressState.snapshot()
        )

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

        for childURL: URL in topLevelChildren {
            try Task.checkCancellation()
            if Self.shouldSkipTopLevelURL(childURL) {
                continue
            }

            let values: URLResourceValues = try childURL.resourceValues(forKeys: Set(Self.topLevelResourceKeys))
            let orphan: DiskItem = makeItem(url: childURL, parent: rootItem, values: values)
            let isDirectory: Bool = values.isDirectory ?? false
            let isPackage: Bool = values.isPackage ?? false
            let isVolume: Bool = values.isVolume ?? false

            if isDirectory && !isVolume && (!isPackage || settings.lookInsidePackages) {
                try loadChildren(of: orphan, settings: settings, progressState: &progressState, progressHandler: progressHandler)
            } else if isDirectory && isPackage && !settings.lookInsidePackages {
                let packageSize: UInt64 = try Self.topLevelOpaquePackageSize(url: childURL, usePhysicalSize: settings.usePhysicalSize)
                orphan.allocatedSizeValue = packageSize
                orphan.logicalSizeValue = packageSize
            } else if !isDirectory {
                progressState.addScannedBytes(orphan.allocatedSizeValue)
            }

            rootItem.appendChild(orphan, updateSize: true)
            progressState.updateCurrentPath(childURL.path)
            progressState.setScannedBytes(rootItem.allocatedSizeValue)
            progressHandler?(progressState.snapshot())
        }

        rootItem.sortChildrenInDiskInventoryZOrder(recursive: false)
        progressState.setScannedBytes(rootItem.allocatedSizeValue)
        progressHandler?(progressState.snapshot())
        return rootItem
    }

    private static func shouldSkipTopLevelURL(_ url: URL) -> Bool {
        if url.path == "/Volumes" {
            return true
        }
        let leaf: String = url.lastPathComponent
        if leaf == ".nofollow" || leaf == ".resolve" {
            return true
        }
        return false
    }

    private static func shouldSkipRecursiveURL(_ url: URL, enumerator: FileManager.DirectoryEnumerator) -> Bool {
        if url.path == "/Volumes" {
            enumerator.skipDescendants()
            return true
        }
        let leaf: String = url.lastPathComponent
        if leaf == ".nofollow" || leaf == ".resolve" {
            enumerator.skipDescendants()
            return true
        }
        return false
    }

    private func loadChildren(
        of item: DiskItem,
        settings: DiskScanSettings,
        progressState: inout ScanProgressState,
        progressHandler: ProgressHandler?
    ) throws {
        if !item.isFolder {
            return
        }
        progressState.updateCurrentPath(item.path)
        if progressState.shouldPublish() { progressHandler?(progressState.snapshot()) }
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
            return
        }
        var lastEnumLevel: Int = 1
        var lastItemWasDirectory: Bool = false
        var lastDirectoryItem: DiskItem? = nil
        var filesSinceYield: Int = 0
        for case let currentURL as URL in directoryEnumerator {
            filesSinceYield += 1
            if filesSinceYield >= 64 {
                filesSinceYield = 0
                try Task.checkCancellation()
                if progressState.shouldPublish() { progressHandler?(progressState.snapshot()) }
            }
            if Self.shouldSkipRecursiveURL(currentURL, enumerator: directoryEnumerator) {
                continue
            }
            let currentValues: URLResourceValues = try currentURL.resourceValues(forKeys: Set(Self.recursiveResourceKeys))
            if directoryEnumerator.level > lastEnumLevel {
                if let lastDirectoryItem: DiskItem = lastDirectoryItem {
                    itemStack.append(lastDirectoryItem)
                } else if lastItemWasDirectory {
                    throw DiskScannerError.zMethodNotPorted("FSItem.loadChildren stack descent")
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
                throw DiskScannerError.zMethodNotPorted("FSItem.loadChildren missing parent")
            }
            let currentItem: DiskItem = makeItem(url: currentURL, parent: parentItem, values: currentValues)
            parentItem.appendChild(currentItem, updateSize: false)
            progressState.recordItem(currentItem)
            let isCurrentDirectory: Bool = currentValues.isDirectory ?? false
            if !isCurrentDirectory {
                let linkCount: Int? = currentValues.linkCount
                if let linkCount: Int = linkCount, linkCount > 1 {
                    if let fileIdentifier: Any = currentValues.fileResourceIdentifier {
                        if seenHardlinkInodes.contains(fileIdentifier) {
                            currentItem.isHardlinkDuplicate = true
                        } else {
                            seenHardlinkInodes.add(fileIdentifier)
                        }
                    }
                }
            }
            if Self.isFirmlink(currentURL) {
                directoryEnumerator.skipDescendants()
                try loadChildren(of: currentItem, settings: settings, progressState: &progressState, progressHandler: progressHandler)
            } else if currentValues.isVolume ?? false {
                directoryEnumerator.skipDescendants()
            } else if (currentValues.isPackage ?? false) && !settings.lookInsidePackages {
                directoryEnumerator.skipDescendants()
                let packageSize: UInt64 = try Self.topLevelOpaquePackageSize(url: currentURL, usePhysicalSize: settings.usePhysicalSize)
                currentItem.allocatedSizeValue = packageSize
                currentItem.logicalSizeValue = packageSize
            } else if !isCurrentDirectory {
                progressState.addScannedBytes(currentItem.allocatedSizeValue)
            }
            if isCurrentDirectory { progressState.updateCurrentPath(currentURL.path) }
            lastItemWasDirectory = isCurrentDirectory
            lastDirectoryItem = lastItemWasDirectory ? currentItem : nil
            lastEnumLevel = directoryEnumerator.level
        }
        item.recalculateSize(usePhysicalSize: settings.usePhysicalSize)
    }

    private func resetHardlinkDedup() {
        seenHardlinkInodes.removeAllObjects()
    }

    private static func topLevelOpaquePackageSize(url: URL, usePhysicalSize: Bool) throws -> UInt64 {
        var packageSize: UInt64 = 0
        let packageKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
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
            let descendantSize: Int? = usePhysicalSize ? descendantValues?.totalFileAllocatedSize : descendantValues?.fileAllocatedSize
            if let descendantSize: Int = descendantSize {
                packageSize += UInt64(descendantSize)
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
            return Self.fallbackKindName(for: url, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
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
        return resolvedKindName ?? Self.fallbackKindName(for: url, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink)
    }

    private static func fallbackKindName(for url: URL, isDirectory: Bool, isSymbolicLink: Bool) -> String? {
        if isSymbolicLink { return "symbolic link" }
        let extensionKey: String = url.pathExtension.lowercased()
        if isDirectory { return Self.directoryKindByExtension[extensionKey] ?? "folder" }
        if extensionKey.isEmpty { return Self.executableFallbackKind(for: url) }
        return Self.fileKindByExtension[extensionKey] ?? "Document"
    }

    private static func executableFallbackKind(for url: URL) -> String {
        let permissions: NSNumber? = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        let mode: Int = permissions?.intValue ?? 0
        return (mode & 0o111) != 0 ? "Unix executable" : "data"
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
