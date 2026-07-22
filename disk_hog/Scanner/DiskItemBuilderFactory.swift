import Foundation
import UniformTypeIdentifiers

nonisolated final class DiskItemBuilderFactory {
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
        if let cachedKindName: String = kindNameByTypeIdentifier[typeIdentifier] {
            return cachedKindName
        }

        var resolvedKindName: String? = UTType(typeIdentifier)?.localizedDescription
        if resolvedKindName == nil {
            resolvedKindName = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        }
        if let resolvedKindName: String = resolvedKindName {
            kindNameByTypeIdentifier[typeIdentifier] = resolvedKindName
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
        if isSymbolicLink { return "symbolic link" }
        let extensionKey: String = url.pathExtension.lowercased()
        if isDirectory { return directoryKindByExtension[extensionKey] ?? "folder" }
        if extensionKey.isEmpty { return executableFallbackKind(for: url, values: values) }
        return fileKindByExtension[extensionKey] ?? "Document"
    }

    private static func executableFallbackKind(for url: URL, values: URLResourceValues?) -> String {
        let isExecutable: Bool? = values?.isExecutable
            ?? ((try? url.resourceValues(forKeys: [.isExecutableKey]))?.isExecutable)
        return isExecutable == true ? "Unix executable" : "data"
    }

    private static let directoryKindByExtension: [String: String] = [
        "app": "application",
        "bundle": "bundle",
        "framework": "framework",
        "xcodeproj": "Xcode Project",
        "xcworkspace": "Xcode Workspace",
        "xcassets": "Xcode Asset Catalog",
        "4dbase": "4D Database Package",
        "dsym": "Package"
    ]

    private static let fileKindByExtension: [String: String] = [
        "php": "PHP script", "py": "Python script", "pyc": "Python Bytecode", "h": "C header code",
        "rag": "Document", "js": "JavaScript", "pcm": "Document", "md": "Markdown Text",
        "json": "JSON", "txt": "text", "ts": "MPEG-2 Transport Stream", "png": "PNG image",
        "pyi": "Document", "d": "Source", "dart": "Document", "stamp": "Document",
        "xml": "XML text", "dia": "Document", "o": "object code", "obj": "Geometry Definition File Format",
        "mtl": "OBJ material file", "scan": "Document", "jpg": "JPEG image", "class": "Java class",
        "so": "Document", "bin": "MacBinary archive", "plist": "property list", "cmake": "Document",
        "len": "Document", "xcconfig": "Xcode Configuration Settings", "yaml": "YAML", "yml": "YAML",
        "map": "MAP file", "modulemap": "Module Map", "flat": "Document", "mat": "Document",
        "pyd": "Document", "dex": "Document", "sample": "Document", "swiftmodule": "Document",
        "c": "C source code", "pdf": "PDF document", "cpp": "C++ source code", "dill": "Document",
        "m": "Objective-C source code", "swift": "Swift Source Code", "zip": "Zip archive", "csv": "comma-separated values",
        "dat": "DAT file", "attrs": "Document", "swiftdeps": "Document", "swiftconstvalues": "Document",
        "sh": "shell script", "jar": "Java archive", "afm": "Document", "swiftsourceinfo": "Document",
        "swiftdoc": "Document", "a": "Ar archive", "hmap": "Document", "timestamp": "Document",
        "xls": "Microsoft Excel 97-2004 worksheet", "p": "Pascal source", "xcfilelist": "Build Phase File List", "f90": "Fortran source code",
        "tab": "Tab Separated Data File", "ninja": "Document", "typed": "Document", "cuh": "Document",
        "ttf": "TrueType® OpenType® font", "jpeg": "JPEG image", "sav": "Parallels VM state image", "svg": "SVG image",
        "css": "CSS", "lib": "Document", "properties": "Java properties file", "hpp": "C++ header code",
        "log": "text", "dylib": "Mach-O dynamic library", "xlsx": "Office Open XML spreadsheet", "html": "HTML text",
        "cc": "C++ source code", "docx": "Office Open XML word processing document", "mjs": "JavaScript", "npz": "Document",
        "exe": "Microsoft Windows application", "indd": "Adobe InDesign Document", "rtf": "rich text (RTF)", "wav": "Waveform audio",
        "sql": "SQL File", "frag": "OpenGL Fragment Shader Source", "cnv": "Canvas 3.5 Document", "psd": "Adobe Photoshop document",
        "gz": "GZip archive", "mts": "AVCHD MPEG-2 Transport Stream", "eps": "Encapsulated PostScript®", "cvd": "Canvas Draw Document",
        "4dd": "4D Data File", "4db": "4D interpreted Structure File", "memmap": "Document", "ds_store": "Document"
    ]
}
