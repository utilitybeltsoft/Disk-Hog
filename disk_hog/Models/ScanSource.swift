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
    let volumeFormat: String?
    let totalCapacity: UInt64?
    let availableCapacity: UInt64?
    let isLocalVolume: Bool?
    let isRemovableVolume: Bool?
    let isEjectableVolume: Bool?
    let isInternalVolume: Bool?
    let isDiskImageVolume: Bool?

    init(
        path: String,
        displayName: String,
        bookmarkData: Data? = nil,
        volumeFormat: String? = nil,
        totalCapacity: UInt64? = nil,
        availableCapacity: UInt64? = nil,
        isLocalVolume: Bool? = nil,
        isRemovableVolume: Bool? = nil,
        isEjectableVolume: Bool? = nil,
        isInternalVolume: Bool? = nil,
        isDiskImageVolume: Bool? = nil
    ) {
        self.path = path
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.volumeFormat = volumeFormat
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.isLocalVolume = isLocalVolume
        self.isRemovableVolume = isRemovableVolume
        self.isEjectableVolume = isEjectableVolume
        self.isInternalVolume = isInternalVolume
        self.isDiskImageVolume = isDiskImageVolume
    }

    var id: String {
        path
    }

    nonisolated var url: URL {
        URL(fileURLWithPath: path)
    }

    var volumeKind: ScanSourceVolumeKind {
        if bookmarkData != nil {
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

    nonisolated func resolvedURL() throws -> URL {
        guard let bookmarkData: Data = bookmarkData else {
            return url
        }

        var isStale: Bool = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

enum ScanSourceProvider {
    static func mountedVolumes() -> [ScanSource] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsLocalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]
        let volumeURLs: [URL] = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumeURLs.map { url in
            let resourceValues: URLResourceValues? = try? url.resourceValues(forKeys: Set(keys))
            return ScanSource(
                path: url.path,
                displayName: displayName(for: url),
                volumeFormat: resourceValues?.volumeLocalizedFormatDescription,
                totalCapacity: resourceValues?.volumeTotalCapacity.map(UInt64.init),
                availableCapacity: resourceValues?.volumeAvailableCapacity.map(UInt64.init),
                isLocalVolume: resourceValues?.volumeIsLocal,
                isRemovableVolume: resourceValues?.volumeIsRemovable,
                isEjectableVolume: resourceValues?.volumeIsEjectable,
                isInternalVolume: resourceValues?.volumeIsInternal,
                isDiskImageVolume: isDiskImage(url)
            )
        }
    }

    static func scanSource(for url: URL, bookmarkData: Data? = nil) -> ScanSource {
        let standardizedURL: URL = url.standardizedFileURL

        return ScanSource(
            path: standardizedURL.path,
            displayName: displayName(for: standardizedURL),
            bookmarkData: bookmarkData,
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
