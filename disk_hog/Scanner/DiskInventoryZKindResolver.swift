import Foundation
import UniformTypeIdentifiers

nonisolated final class DiskInventoryZKindResolver: @unchecked Sendable {
    private var kindNameByUTI: [String: String]
    private let lock: NSLock

    init() {
        self.kindNameByUTI = [:]
        self.lock = NSLock()
    }

    func kindName(typeIdentifier: String?, url: URL) -> String? {
        let kindStartTime: CFAbsoluteTime = ScanPerformanceRecorder.isEnabled ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            if ScanPerformanceRecorder.isEnabled {
                ScanPerformanceRecorder.shared.addTime("kind.total", seconds: CFAbsoluteTimeGetCurrent() - kindStartTime)
            }
        }

        if Self.zLegacyDataExtensions.contains(url.pathExtension.lowercased()) {
            return Self.legacyDataKindName
        }

        guard let typeIdentifier: String = typeIdentifier else {
            return ScanPerformanceRecorder.shared.measure("kind.localizedDescriptionFallback") {
                localizedTypeDescription(for: url)
            }
        }

        lock.lock()
        let cacheStartTime: CFAbsoluteTime = ScanPerformanceRecorder.isEnabled ? CFAbsoluteTimeGetCurrent() : 0
        if let cachedKindName: String = kindNameByUTI[typeIdentifier] {
            if ScanPerformanceRecorder.isEnabled {
                ScanPerformanceRecorder.shared.addTime("kind.cacheLookup", seconds: CFAbsoluteTimeGetCurrent() - cacheStartTime)
            }
            lock.unlock()
            return cachedKindName
        }
        if ScanPerformanceRecorder.isEnabled {
            ScanPerformanceRecorder.shared.addTime("kind.cacheLookup", seconds: CFAbsoluteTimeGetCurrent() - cacheStartTime)
        }
        lock.unlock()

        var kindName: String? = ScanPerformanceRecorder.shared.measure("kind.uttypeDescription") {
            UTType(typeIdentifier)?.localizedDescription
        }
        if kindName == nil {
            kindName = ScanPerformanceRecorder.shared.measure("kind.localizedDescriptionFallback") {
                localizedTypeDescription(for: url)
            }
        }

        if let kindName: String = kindName {
            lock.lock()
            kindNameByUTI[typeIdentifier] = kindName
            lock.unlock()
        }

        return kindName
    }

    private func localizedTypeDescription(for url: URL) -> String? {
        try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription
    }

    private static let legacyDataKindName: String = "data"
    private static let zLegacyDataExtensions: Set<String> = ["cnv"]
}
