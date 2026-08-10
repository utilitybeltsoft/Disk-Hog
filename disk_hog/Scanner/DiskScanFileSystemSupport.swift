import Foundation

nonisolated enum DiskScanResourceKeys {
    static let item: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isVolumeKey,
        .nameKey, .typeIdentifierKey,
        .fileSizeKey, .totalFileAllocatedSizeKey,
        .isExecutableKey, .isSymbolicLinkKey,
        .linkCountKey, .fileResourceIdentifierKey
    ]

    static let packageSize: [URLResourceKey] = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]
}

nonisolated enum DiskScanFileSystemRules {
    private static let firmlinkListPath: String = "/usr/share/firmlinks"
    private static let firmlinkURLs: Set<URL> = loadFirmlinks()

    static func shouldSkip(_ url: URL) -> Bool {
        if url.path == "/Volumes" {
            return true
        }
        let leaf: String = url.lastPathComponent
        return leaf == ".nofollow" || leaf == ".resolve"
    }

    static func isFirmlink(_ url: URL) -> Bool {
        firmlinkURLs.contains(url)
    }

    private static func loadFirmlinks() -> Set<URL> {
        var loadedFirmlinks: Set<URL> = []
        let fileContents: String? = try? String(contentsOfFile: firmlinkListPath, encoding: .ascii)
        let allLines: [String] = fileContents?.components(separatedBy: .newlines) ?? []
        for line: String in allLines {
            let linkFromTo: [String] = line.components(separatedBy: "\t")
            if linkFromTo.count >= 2 {
                let sourceURL: URL = URL(fileURLWithPath: linkFromTo[0])
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    loadedFirmlinks.insert(sourceURL)
                }
            }
        }
        return loadedFirmlinks
    }
}

nonisolated struct OpaquePackageSize: Sendable {
    var allocated: UInt64 = 0
    var logical: UInt64 = 0
}

nonisolated protocol OpaquePackageSizing: Sendable {
    func size(of url: URL) throws -> OpaquePackageSize
}

nonisolated struct FileSystemOpaquePackageSizer: OpaquePackageSizing {
    func size(of url: URL) throws -> OpaquePackageSize {
        var packageSize: OpaquePackageSize = OpaquePackageSize()
        guard let enumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: DiskScanResourceKeys.packageSize,
            options: [],
            errorHandler: nil
        ) else {
            return packageSize
        }

        for case let descendantURL as URL in enumerator {
            try Task.checkCancellation()
            let values: URLResourceValues? = try? descendantURL.resourceValues(
                forKeys: Set(DiskScanResourceKeys.packageSize)
            )
            if let allocatedSize: Int = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                packageSize.allocated += UInt64(allocatedSize)
            }
            if let logicalSize: Int = values?.fileSize {
                packageSize.logical += UInt64(logicalSize)
            }
        }
        return packageSize
    }
}

// Hardlink byte ownership is intentionally first-claimer-wins across parallel
// subtree scans. Grand totals remain deterministic, but per-folder attribution
// for multiply-linked files can vary with task scheduling.
nonisolated protocol HardlinkDeduplicating: Sendable {
    func reset()
    func markDuplicateIfNeeded(item: DiskItemBuilder, values: URLResourceValues)
}

nonisolated final class HardlinkDeduplicator: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private let seenFileIdentifiers: NSMutableSet = NSMutableSet()

    func reset() {
        lock.withLock {
            seenFileIdentifiers.removeAllObjects()
        }
    }

    func markDuplicateIfNeeded(item: DiskItemBuilder, values: URLResourceValues) {
        guard let linkCount: Int = values.linkCount,
              linkCount > 1,
              let fileIdentifier: Any = values.fileResourceIdentifier else {
            return
        }

        item.isHardlinkDuplicate = isDuplicate(fileIdentifier)
    }

    private func isDuplicate(_ fileIdentifier: Any) -> Bool {
        lock.withLock {
            if seenFileIdentifiers.contains(fileIdentifier) {
                return true
            }
            seenFileIdentifiers.add(fileIdentifier)
            return false
        }
    }
}

extension HardlinkDeduplicator: HardlinkDeduplicating {}
