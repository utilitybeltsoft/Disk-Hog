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
        let kindStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        defer {
            ScanPerformanceRecorder.shared.addTime("kind.total", seconds: CFAbsoluteTimeGetCurrent() - kindStartTime)
        }

        guard let typeIdentifier: String = typeIdentifier else {
            return ScanPerformanceRecorder.shared.measure("kind.localizedDescriptionFallback") {
                localizedTypeDescription(for: url)
            }
        }

        lock.lock()
        let cacheStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        if let cachedKindName: String = kindNameByUTI[typeIdentifier] {
            ScanPerformanceRecorder.shared.addTime("kind.cacheLookup", seconds: CFAbsoluteTimeGetCurrent() - cacheStartTime)
            lock.unlock()
            return cachedKindName
        }
        ScanPerformanceRecorder.shared.addTime("kind.cacheLookup", seconds: CFAbsoluteTimeGetCurrent() - cacheStartTime)
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
}
