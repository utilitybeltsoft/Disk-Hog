import Foundation

struct ScanSource: Codable, Hashable, Identifiable {
    let path: String
    let displayName: String

    var id: String {
        path
    }

    var url: URL {
        URL(fileURLWithPath: path)
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

    static func scanSource(for url: URL) -> ScanSource {
        let standardizedURL: URL = url.standardizedFileURL

        return ScanSource(
            path: standardizedURL.path,
            displayName: displayName(for: standardizedURL)
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
