import Foundation

struct ScanSource: Codable, Hashable, Identifiable {
    let path: String
    let displayName: String
    let bookmarkData: Data?

    init(path: String, displayName: String, bookmarkData: Data? = nil) {
        self.path = path
        self.displayName = displayName
        self.bookmarkData = bookmarkData
    }

    var id: String {
        path
    }

    nonisolated var url: URL {
        URL(fileURLWithPath: path)
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
            .volumeIsLocalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]
        let volumeURLs: [URL] = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumeURLs.map { url in
            ScanSource(
                path: url.path,
                displayName: displayName(for: url)
            )
        }
    }

    static func scanSource(for url: URL, bookmarkData: Data? = nil) -> ScanSource {
        let standardizedURL: URL = url.standardizedFileURL

        return ScanSource(
            path: standardizedURL.path,
            displayName: displayName(for: standardizedURL),
            bookmarkData: bookmarkData
        )
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
