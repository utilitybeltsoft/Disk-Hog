import Foundation
import DiskArbitration

enum ScanSourceVolumeKind: String, Codable, Hashable {
    case internalVolume
    case externalVolume
    case networkVolume
    case diskImage
    case folder
}

struct ScanSource: Codable, Hashable, Identifiable {
    let path: String
    let displayName: String
    let bookmarkData: Data?
    /// Explicit source identity; optional only for compatibility with older saved sources.
    let isVolumeRoot: Bool?
    let volumeFormat: String?
    let totalCapacity: UInt64?
    let availableCapacity: UInt64?
    let isLocalVolume: Bool?
    let isRemovableVolume: Bool?
    let isEjectableVolume: Bool?
    let isInternalVolume: Bool?
    let isDiskImageVolume: Bool?
    let scanDisabledReason: String?
    let scanSettings: DiskScanSettings?

    nonisolated init(
        path: String,
        displayName: String,
        bookmarkData: Data? = nil,
        isVolumeRoot: Bool? = nil,
        volumeFormat: String? = nil,
        totalCapacity: UInt64? = nil,
        availableCapacity: UInt64? = nil,
        isLocalVolume: Bool? = nil,
        isRemovableVolume: Bool? = nil,
        isEjectableVolume: Bool? = nil,
        isInternalVolume: Bool? = nil,
        isDiskImageVolume: Bool? = nil,
        scanDisabledReason: String? = nil,
        scanSettings: DiskScanSettings? = nil
    ) {
        self.path = path
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.isVolumeRoot = isVolumeRoot
        self.volumeFormat = volumeFormat
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.isLocalVolume = isLocalVolume
        self.isRemovableVolume = isRemovableVolume
        self.isEjectableVolume = isEjectableVolume
        self.isInternalVolume = isInternalVolume
        self.isDiskImageVolume = isDiskImageVolume
        self.scanDisabledReason = scanDisabledReason
        self.scanSettings = scanSettings
    }

    var id: String {
        path
    }

    /// A source's friendly name may identify its enclosing volume. Always retain
    /// the scan root's full path so different folder scans have distinct titles.
    nonisolated var scanWindowTitle: String {
        displayName == path || displayName.isEmpty ? path : "\(displayName) — \(path)"
    }

    var scanWindowRegistryKey: String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    var canScan: Bool {
        scanDisabledReason == nil
    }

    nonisolated var url: URL {
        URL(fileURLWithPath: path)
    }

    var volumeKind: ScanSourceVolumeKind {
        // Only legacy sources without explicit identity use the old bookmark heuristic.
        if !(isVolumeRoot ?? (bookmarkData == nil)) {
            return .folder
        }

        if isLocalVolume == false {
            return .networkVolume
        }

        if isDiskImageVolume == true {
            return .diskImage
        }

        if isRemovableVolume == true || isEjectableVolume == true {
            return .externalVolume
        }

        if isInternalVolume == true {
            return .internalVolume
        }

        return .externalVolume
    }

    nonisolated func resolvingBookmark() throws -> ScanSourceBookmarkResolution {
        guard let bookmarkData: Data = bookmarkData else {
            return ScanSourceBookmarkResolution(url: url, refreshedBookmarkData: nil)
        }

        return try Self.bookmarkResolution(
            for: bookmarkData,
            resolving: { bookmarkData in
                var isStale: Bool = false
                let resolvedURL: URL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return (resolvedURL, isStale)
            },
            creating: { resolvedURL in
                try resolvedURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
        )
    }

    nonisolated func resolvedURL() throws -> URL {
        try resolvingBookmark().url
    }

    nonisolated func replacingBookmarkData(_ bookmarkData: Data) -> ScanSource {
        ScanSource(
            path: path,
            displayName: displayName,
            bookmarkData: bookmarkData,
            isVolumeRoot: isVolumeRoot,
            volumeFormat: volumeFormat,
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            isLocalVolume: isLocalVolume,
            isRemovableVolume: isRemovableVolume,
            isEjectableVolume: isEjectableVolume,
            isInternalVolume: isInternalVolume,
            isDiskImageVolume: isDiskImageVolume,
            scanDisabledReason: scanDisabledReason,
            scanSettings: scanSettings
        )
    }

    nonisolated static func bookmarkResolution(
        for bookmarkData: Data,
        resolving: (Data) throws -> (url: URL, isStale: Bool),
        creating: (URL) throws -> Data
    ) throws -> ScanSourceBookmarkResolution {
        let result: (url: URL, isStale: Bool) = try resolving(bookmarkData)
        return ScanSourceBookmarkResolution(
            url: result.url,
            refreshedBookmarkData: result.isStale ? try creating(result.url) : nil
        )
    }

    func applyingScanSettings(_ settings: DiskScanSettings) -> ScanSource {
        ScanSource(
            path: path,
            displayName: displayName,
            bookmarkData: bookmarkData,
            isVolumeRoot: isVolumeRoot,
            volumeFormat: volumeFormat,
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            isLocalVolume: isLocalVolume,
            isRemovableVolume: isRemovableVolume,
            isEjectableVolume: isEjectableVolume,
            isInternalVolume: isInternalVolume,
            isDiskImageVolume: isDiskImageVolume,
            scanDisabledReason: scanDisabledReason,
            scanSettings: settings
        )
    }
}

nonisolated struct ScanSourceBookmarkResolution: Sendable {
    let url: URL
    let refreshedBookmarkData: Data?
}

nonisolated enum ScanSourceProvider {
    private static let volumeKeys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeLocalizedFormatDescriptionKey,
        .volumeIsLocalKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsInternalKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey
    ]

    static func mountedVolumes() -> [ScanSource] {
        let volumeURLs: [URL] = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: volumeKeys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumeURLs.map { volumeSource(for: $0) }
    }

    private static func volumeSource(for url: URL, bookmarkData: Data? = nil) -> ScanSource {
        let resourceValues = try? url.resourceValues(forKeys: Set(volumeKeys))
        return ScanSource(
            path: url.path,
            displayName: displayName(for: url),
            bookmarkData: bookmarkData,
            isVolumeRoot: true,
            volumeFormat: resourceValues?.volumeLocalizedFormatDescription,
            totalCapacity: resourceValues?.volumeTotalCapacity.map(UInt64.init),
            availableCapacity: resourceValues?.volumeAvailableCapacity.map(UInt64.init),
            isLocalVolume: resourceValues?.volumeIsLocal,
            isRemovableVolume: resourceValues?.volumeIsRemovable,
            isEjectableVolume: resourceValues?.volumeIsEjectable,
            isInternalVolume: resourceValues?.volumeIsInternal,
            isDiskImageVolume: isDiskImage(url),
            scanDisabledReason: scanDisabledReason(
                for: url,
                isLocalVolume: resourceValues?.volumeIsLocal
            )
        )
    }

    static func scanSource(for url: URL, bookmarkData: Data? = nil) -> ScanSource {
        let standardizedURL: URL = url.standardizedFileURL
        let didAccess = standardizedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { standardizedURL.stopAccessingSecurityScopedResource() } }
        let resolvedURL = standardizedURL.resolvingSymlinksInPath()
        let isVolume = (try? resolvedURL.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
        if isVolume {
            return volumeSource(for: standardizedURL, bookmarkData: bookmarkData)
        }

        return ScanSource(
            path: standardizedURL.path,
            displayName: displayName(for: standardizedURL),
            bookmarkData: bookmarkData,
            isVolumeRoot: false,
            volumeFormat: nil,
            totalCapacity: nil,
            availableCapacity: nil,
            isLocalVolume: nil,
            isRemovableVolume: nil,
            isEjectableVolume: nil,
            isInternalVolume: nil,
            isDiskImageVolume: nil
        )
    }

    private static func isDiskImage(_ url: URL) -> Bool {
        guard let session: DASession = DASessionCreate(kCFAllocatorDefault) else {
            return false
        }

        guard let disk: DADisk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            return false
        }

        guard let description: CFDictionary = DADiskCopyDescription(disk) else {
            return false
        }

        let descriptionDictionary: NSDictionary = description as NSDictionary
        guard let protocolName: String = descriptionDictionary[kDADiskDescriptionDeviceProtocolKey] as? String else {
            return false
        }

        return protocolName == "Virtual Interface"
    }

    static func scanDisabledReason(
        for url: URL,
        isLocalVolume: Bool?,
        protectedURLs: [URL] = fullDiskAccessProtectedURLs(),
        fileExists: (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        },
        directoryContents: (URL) throws -> [URL] = {
            try FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: nil,
                options: []
            )
        }
    ) -> String? {
        guard isLocalVolume != false else {
            return nil
        }

        do {
            _ = try directoryContents(url)
        } catch {
            guard isPermissionDenied(error) else {
                return nil
            }
            return String(localized: "Full Disk Access required")
        }

        for protectedURL: URL in protectedURLs
        where contains(protectedURL, within: url) && fileExists(protectedURL) {
            do {
                _ = try directoryContents(protectedURL)
            } catch {
                if isPermissionDenied(error) {
                    return String(localized: "Full Disk Access required")
                }
            }
        }

        return nil
    }

    private static func fullDiskAccessProtectedURLs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let libraryURL: URL = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            libraryURL.appendingPathComponent("Mail", isDirectory: true),
            libraryURL.appendingPathComponent("Messages", isDirectory: true),
            libraryURL.appendingPathComponent("Safari", isDirectory: true),
            libraryURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("AddressBook", isDirectory: true)
        ]
    }

    private static func contains(_ candidateURL: URL, within rootURL: URL) -> Bool {
        let rootPath: String = rootURL.standardizedFileURL.path
        let candidatePath: String = candidateURL.standardizedFileURL.path

        if rootPath == "/" {
            return candidatePath.hasPrefix("/")
        }

        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let error: NSError = error as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileReadNoPermissionError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(EPERM) || error.code == Int(EACCES) {
            return true
        }
        if let underlyingError: Error = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionDenied(underlyingError)
        }
        return false
    }

    private static func displayName(for url: URL) -> String {
        let resourceValues: URLResourceValues? = try? url.resourceValues(forKeys: [.volumeNameKey])
        if let volumeName: String = resourceValues?.volumeName, !volumeName.isEmpty {
            return volumeName
        }

        let displayName: String = FileManager.default.displayName(atPath: url.path)
        if !displayName.isEmpty {
            return displayName
        }

        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}
