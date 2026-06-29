import Foundation

nonisolated final class DiskInventoryZFirmlinkTable: @unchecked Sendable {
    private let fileManager: FileManager
    private let firmlinkListURL: URL
    private let lock: NSLock
    private var loadedPaths: Set<String>?

    init(
        fileManager: FileManager = .default,
        firmlinkListURL: URL = URL(fileURLWithPath: "/usr/share/firmlinks")
    ) {
        self.fileManager = fileManager
        self.firmlinkListURL = firmlinkListURL
        self.lock = NSLock()
        self.loadedPaths = nil
    }

    func isFirmlink(_ url: URL) -> Bool {
        let startTime: CFAbsoluteTime = ScanPerformanceRecorder.isEnabled ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            if ScanPerformanceRecorder.isEnabled {
                ScanPerformanceRecorder.shared.addTime("url.isFirmlink", seconds: CFAbsoluteTimeGetCurrent() - startTime)
            }
        }

        lock.lock()
        if let loadedPaths: Set<String> = loadedPaths {
            lock.unlock()
            return loadedPaths.contains(url.path)
        }
        lock.unlock()

        let paths: Set<String> = loadFirmlinkPaths()

        lock.lock()
        if loadedPaths == nil {
            loadedPaths = paths
        }
        let result: Bool = loadedPaths?.contains(url.path) ?? false
        lock.unlock()

        return result
    }

    private func loadFirmlinkPaths() -> Set<String> {
        guard let contents: String = try? String(contentsOf: firmlinkListURL, encoding: .ascii) else {
            return []
        }

        var paths: Set<String> = []
        let lines: [Substring] = contents.split(whereSeparator: \.isNewline)
        for line: Substring in lines {
            let fields: [Substring] = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= Metrics.minimumFirmlinkFieldCount else {
                continue
            }

            let sourcePath: String = String(fields[Metrics.sourcePathIndex])
            guard fileManager.fileExists(atPath: sourcePath) else {
                continue
            }

            paths.insert(sourcePath)
        }

        return paths
    }
}

nonisolated private enum DiskInventoryZFirmlinkTableMetrics {
    static let minimumFirmlinkFieldCount: Int = 2
    static let sourcePathIndex: Int = 0
}

private typealias Metrics = DiskInventoryZFirmlinkTableMetrics
