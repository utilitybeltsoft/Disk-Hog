import Foundation
import UniformTypeIdentifiers

nonisolated protocol DiskItemBuilding: Sendable {
    func makeItem(url: URL, values: URLResourceValues?) -> DiskItemBuilder
    func makeItem(url: URL, values: URLResourceValues?, in arenaOwner: DiskItemBuilder) -> DiskItemBuilder
}

nonisolated final class DiskItemBuilderFactory: @unchecked Sendable {
    private let kindNameLock: NSLock = NSLock()
    private var kindNameByTypeIdentifier: [String: String] = [:]

    func makeItem(url: URL, values: URLResourceValues?) -> DiskItemBuilder {
        DiskItemBuilder(metadata: makeMetadata(url: url, values: values))
    }

    func makeItem(url: URL, values: URLResourceValues?, in arenaOwner: DiskItemBuilder) -> DiskItemBuilder {
        arenaOwner.makeChild(metadata: makeMetadata(url: url, values: values))
    }

    private func makeMetadata(url: URL, values: URLResourceValues?) -> DiskItemMetadata {
        let isDirectory: Bool = values?.isDirectory ?? url.hasDirectoryPath
        let isPackage: Bool = values?.isPackage ?? false
        let isSymbolicLink: Bool = values?.isSymbolicLink ?? false
        let allocatedSize: UInt64 = UInt64(values?.totalFileAllocatedSize ?? 0)
        let logicalSize: UInt64 = UInt64(values?.fileSize ?? 0)
        let name: String = values?.name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        let kindName: String? = kindName(
            for: url,
            values: values,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink
        )
        return DiskItemMetadata(
            url: url,
            name: name,
            allocatedSizeValue: isDirectory ? 0 : allocatedSize,
            logicalSizeValue: isDirectory ? 0 : logicalSize,
            kindName: kindName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isAliasOrSymbolicLink: isSymbolicLink
        )
    }

    private func kindName(
        for url: URL,
        values: URLResourceValues?,
        isDirectory: Bool,
        isSymbolicLink: Bool
    ) -> String? {
        let typeIdentifier: String? = values?.typeIdentifier
            ?? ((try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier)
        guard let typeIdentifier: String = typeIdentifier else {
            return Self.fallbackKindName(
                for: url,
                values: values,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink
            )
        }
        if let cachedKindName: String = kindNameLock.withLock({
            kindNameByTypeIdentifier[typeIdentifier]
        }) {
            return cachedKindName
        }

        var resolvedKindName: String? = UTType(typeIdentifier)?.localizedDescription
        if resolvedKindName == nil {
            resolvedKindName = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        }
        if let resolvedKindName: String = resolvedKindName {
            kindNameLock.withLock {
                kindNameByTypeIdentifier[typeIdentifier] = resolvedKindName
            }
        }
        return resolvedKindName ?? Self.fallbackKindName(
            for: url,
            values: values,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink
        )
    }

    private static func fallbackKindName(
        for url: URL,
        values: URLResourceValues?,
        isDirectory: Bool,
        isSymbolicLink: Bool
    ) -> String? {
        if isSymbolicLink { return localizedFallbackKindName("symbolic link") }
        if isDirectory { return localizedFallbackKindName("folder") }
        if url.pathExtension.isEmpty { return executableFallbackKind(for: url, values: values) }
        return localizedFallbackKindName("Document")
    }

    private static func executableFallbackKind(for url: URL, values: URLResourceValues?) -> String {
        let isExecutable: Bool? = values?.isExecutable
            ?? ((try? url.resourceValues(forKeys: [.isExecutableKey]))?.isExecutable)
        return localizedFallbackKindName(isExecutable == true ? "Unix executable" : "data")
    }

    static func localizedFallbackKindName(_ kindName: String) -> String {
        switch kindName {
        case "Document":
            return String(localized: "Document")
        case "text":
            return String(localized: "text")
        case "folder":
            return String(localized: "folder")
        case "symbolic link":
            return String(localized: "symbolic link")
        case "data":
            return String(localized: "data")
        case "Unix executable":
            return String(localized: "Unix executable")
        default:
            return kindName
        }
    }

}

extension DiskItemBuilderFactory: DiskItemBuilding {}
