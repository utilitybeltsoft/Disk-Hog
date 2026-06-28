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
        guard let typeIdentifier: String = typeIdentifier else {
            return localizedTypeDescription(for: url)
        }

        lock.lock()
        if let cachedKindName: String = kindNameByUTI[typeIdentifier] {
            lock.unlock()
            return cachedKindName
        }
        lock.unlock()

        var kindName: String? = UTType(typeIdentifier)?.localizedDescription
        if kindName == nil {
            kindName = localizedTypeDescription(for: url)
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
