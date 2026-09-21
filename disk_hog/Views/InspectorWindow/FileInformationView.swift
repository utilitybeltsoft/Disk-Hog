import AppKit
import Darwin
import SwiftUI

struct FileInformationView: View {
    @ObservedObject var session: ScanSession
    @ObservedObject var selectionCoordinator: ScanWindowSelectionCoordinator
    @State private var snapshot: FileInformationSnapshot?
    @State private var displayedItem: DiskItem?
    @State private var isLoading: Bool = false

    var body: some View {
        if let selectedItem: DiskItem = selectionCoordinator.selectedItem, !selectedItem.isSpecialItem {
            let item: DiskItem = displayedItem ?? selectedItem
            FileInformationContent(
                item: item,
                kindDescription: item.kindName
                    ?? (item.isFolder
                        ? String(localized: "Folder")
                        : String(localized: "File")),
                snapshot: snapshot,
                isLoading: isLoading
            )
            .task(id: selectedItem.id) {
                isLoading = snapshot == nil
                let usePhysicalSize: Bool = session.scanSettings.usePhysicalSize
                let isSizeUnknown: Bool = session.isAffectedBySkippedContent(selectedItem)
                let defaultApplication: String? = NSWorkspace.shared
                    .urlForApplication(toOpen: selectedItem.url)?
                    .lastPathComponent
                let loadedSnapshot: FileInformationSnapshot = await Task.detached(priority: .userInitiated) {
                    FileInformationSnapshot.load(
                        item: selectedItem,
                        usePhysicalSize: usePhysicalSize,
                        defaultApplication: defaultApplication,
                        isSizeUnknown: isSizeUnknown
                    )
                }.value
                guard !Task.isCancelled,
                      selectionCoordinator.selectedItem?.id == selectedItem.id else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.12)) {
                    snapshot = loadedSnapshot
                    displayedItem = selectedItem
                    isLoading = false
                }
            }
        } else {
            ContentUnavailableView(
                "No Item Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a file or folder in the active scan window.")
            )
        }
    }
}

struct VolumeInformationView: View {
    let source: ScanSource
    @State private var item: DiskItem
    @State private var snapshot: FileInformationSnapshot?
    @State private var isLoading: Bool = true

    init(source: ScanSource) {
        self.source = source
        _item = State(initialValue: FileInformationSnapshot.volumeItem(for: source))
    }

    var body: some View {
        FileInformationContent(
            item: item,
            kindDescription: source.volumeFormat ?? String(localized: "Volume"),
            snapshot: snapshot,
            isLoading: isLoading
        )
        .task(id: source.id) {
            isLoading = snapshot == nil
            let loadedSnapshot: FileInformationSnapshot = await Task.detached(priority: .utility) {
                FileInformationSnapshot.load(source: source)
            }.value
            guard !Task.isCancelled else {
                return
            }
            snapshot = loadedSnapshot
            isLoading = false
        }
    }
}

@MainActor
private struct FileInformationContent: View {
    let item: DiskItem
    let kindDescription: String
    let snapshot: FileInformationSnapshot?
    let isLoading: Bool

    @State private var icon: NSImage

    init(item: DiskItem, kindDescription: String, snapshot: FileInformationSnapshot?, isLoading: Bool) {
        self.item = item
        self.kindDescription = kindDescription
        self.snapshot = snapshot
        self.isLoading = isLoading
        _icon = State(initialValue: FileInformationContent.resizedIcon(
            DiskItemIconCache.shared.cachedIcon(forFile: item.path)
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayName)
                            .font(.system(size: NSFont.systemFontSize, weight: .semibold))
                            .lineLimit(1)
                        Text(kindDescription)
                            .font(.system(size: NSFont.smallSystemFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let snapshot {
                    ForEach(snapshot.sections) { section in
                        informationSection(section)
                    }
                } else if isLoading {
                    ProgressView("Reading file metadata")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .id(item.id)
            .transition(.opacity)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if snapshot != nil {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: InformationContentHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
        }
        .background {
            InformationContextMenuAugmenter(
                item: item,
                snapshot: snapshot,
                kindDescription: kindDescription
            )
        }
        .task(id: item.path) {
            icon = FileInformationContent.resizedIcon(
                await DiskItemIconCache.shared.loadIconAsync(forFile: item.path)
            )
        }
    }

    private static func resizedIcon(_ image: NSImage?) -> NSImage {
        let base: NSImage = image
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            ?? NSImage()
        let icon: NSImage = (base.copy() as? NSImage) ?? base
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    private func informationSection(_ section: FileInformationSection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(section.title)
                .font(.system(size: NSFont.smallSystemFontSize, weight: .semibold))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 1) {
                ForEach(informationLines(for: section.rows)) { line in
                    GridRow {
                        informationCell(line.first)
                        if let second: FileInformationRow = line.second {
                            informationCell(second)
                        } else {
                            Color.clear
                                .frame(width: 0, height: 0)
                        }
                    }
                }
            }
        }
    }

    private func informationCell(_ row: FileInformationRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(row.label):")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(row.value)
                .font(
                    row.monospaced
                        ? .system(size: NSFont.smallSystemFontSize, design: .monospaced)
                        : .system(size: NSFont.smallSystemFontSize)
                )
                .lineLimit(row.isMultiline ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: row.isMultiline)
                .textSelection(.enabled)
                .help(row.value)
        }
        .font(.system(size: NSFont.smallSystemFontSize))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func informationLines(for rows: [FileInformationRow]) -> [FileInformationLine] {
        stride(from: 0, to: rows.count, by: 2).map { index in
            FileInformationLine(
                first: rows[index],
                second: rows.indices.contains(index + 1) ? rows[index + 1] : nil
            )
        }
    }
}

struct InformationContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FileInformationLine: Identifiable {
    let first: FileInformationRow
    let second: FileInformationRow?

    var id: String {
        second.map { "\(first.id)|\($0.id)" } ?? first.id
    }
}

nonisolated struct FileInformationSnapshot: Sendable {
    let sections: [FileInformationSection]

    func plainText(itemName: String, kindDescription: String) -> String {
        let sectionText: String = sections.map { section in
            let rows: String = section.rows.map { row in
                "\(row.label): \(row.value)"
            }.joined(separator: "\n")
            return "\(section.title)\n\(rows)"
        }.joined(separator: "\n\n")

        return "\(itemName)\n\(kindDescription)\n\n\(sectionText)"
    }

    static func volumeItem(for source: ScanSource) -> DiskItem {
        let totalBytes: UInt64 = source.totalCapacity ?? 0
        let freeBytes: UInt64 = min(source.availableCapacity ?? 0, totalBytes)
        return DiskItem(
            url: source.url,
            displayName: source.displayName,
            name: source.url.lastPathComponent.isEmpty
                ? source.displayName
                : source.url.lastPathComponent,
            allocatedSizeValue: totalBytes - freeBytes,
            logicalSizeValue: totalBytes - freeBytes,
            kindName: source.volumeFormat ?? String(localized: "Volume"),
            isDirectory: true
        )
    }

    static func load(source: ScanSource) -> FileInformationSnapshot {
        let item: DiskItem = volumeItem(for: source)
        var sections: [FileInformationSection] = load(
            item: item,
            usePhysicalSize: true
        ).sections.filter { $0.title != String(localized: "Sizes") }
        sections.insert(volumeSection(source: source), at: min(1, sections.count))
        return FileInformationSnapshot(sections: sections)
    }

    static func load(
        item: DiskItem,
        usePhysicalSize: Bool,
        defaultApplication: String? = nil,
        isSizeUnknown: Bool = false
    ) -> FileInformationSnapshot {
        let url: URL = item.url
        let path: String = item.path
        let fileManager: FileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .localizedNameKey,
            .localizedTypeDescriptionKey,
            .typeIdentifierKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .attributeModificationDateKey,
            .addedToDirectoryDateKey,
            .fileResourceIdentifierKey,
            .generationIdentifierKey,
            .documentIdentifierKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .isHiddenKey,
            .hasHiddenExtensionKey,
            .isReadableKey,
            .isWritableKey,
            .isExecutableKey,
            .isUserImmutableKey,
            .isSystemImmutableKey,
            .isExcludedFromBackupKey,
            .tagNamesKey,
            .labelNumberKey,
            .quarantinePropertiesKey
        ]
        let values: URLResourceValues? = try? url.resourceValues(forKeys: resourceKeys)
        let attributes: [FileAttributeKey: Any] = (try? fileManager.attributesOfItem(atPath: path)) ?? [:]
        let extendedAttributes: [FileExtendedAttribute] = readExtendedAttributes(atPath: path)

        var sections: [FileInformationSection] = []
        sections.append(identitySection(item: item, values: values, defaultApplication: defaultApplication))
        sections.append(sizeSection(item: item, values: values, attributes: attributes, usePhysicalSize: usePhysicalSize, isSizeUnknown: isSizeUnknown))
        sections.append(dateSection(values: values))
        sections.append(finderSection(item: item, values: values, attributes: attributes, extendedAttributes: extendedAttributes))
        sections.append(permissionSection(path: path, values: values, attributes: attributes))
        sections.append(fileSystemSection(item: item, values: values, attributes: attributes))
        sections.append(extendedAttributeSection(extendedAttributes))
        return FileInformationSnapshot(sections: sections.filter { !$0.rows.isEmpty })
    }

    private static func volumeSection(source: ScanSource) -> FileInformationSection {
        let resourceKeys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsReadOnlyKey
        ]
        let values: URLResourceValues? = try? source.url.resourceValues(forKeys: resourceKeys)
        let totalBytes: UInt64? = values?.volumeTotalCapacity.map(UInt64.init)
            ?? source.totalCapacity
        let availableBytes: UInt64? = values?.volumeAvailableCapacity.map(UInt64.init)
            ?? source.availableCapacity
        var rows: [FileInformationRow] = [
            FileInformationRow("Mount point", source.path)
        ]
        append("Volume name", values?.volumeName ?? source.displayName, to: &rows)
        append(
            "Format",
            values?.volumeLocalizedFormatDescription ?? source.volumeFormat,
            to: &rows
        )
        if let totalBytes {
            rows.append(FileInformationRow("Capacity", byteString(totalBytes)))
        }
        if let availableBytes {
            rows.append(FileInformationRow("Available", byteString(availableBytes)))
        }
        if let totalBytes, let availableBytes {
            rows.append(
                FileInformationRow(
                    "Used",
                    byteString(totalBytes > availableBytes ? totalBytes - availableBytes : 0)
                )
            )
        }
        appendBoolean("Local", values?.volumeIsLocal ?? source.isLocalVolume, to: &rows)
        appendBoolean("Internal", values?.volumeIsInternal ?? source.isInternalVolume, to: &rows)
        appendBoolean("Removable", values?.volumeIsRemovable ?? source.isRemovableVolume, to: &rows)
        appendBoolean("Ejectable", values?.volumeIsEjectable ?? source.isEjectableVolume, to: &rows)
        appendBoolean("Read-only", values?.volumeIsReadOnly, to: &rows)
        rows.append(
            FileInformationRow(
                "Disk image",
                yesNo(source.isDiskImageVolume == true)
            )
        )
        rows.append(
            FileInformationRow(
                "Scan availability",
                source.scanDisabledReason ?? String(localized: "Available")
            )
        )
        return FileInformationSection(title: "Volume", rows: rows)
    }

    private static func identitySection(
        item: DiskItem,
        values: URLResourceValues?,
        defaultApplication: String?
    ) -> FileInformationSection {
        var rows: [FileInformationRow] = [
            FileInformationRow("Name", item.name),
            FileInformationRow("Display name", item.displayName),
            FileInformationRow(
                "Kind",
                values?.localizedTypeDescription
                    ?? item.kindName
                    ?? (item.isFolder
                        ? String(localized: "Folder")
                        : String(localized: "File"))
            ),
            FileInformationRow("Path", item.path)
        ]
        append("Type identifier", values?.typeIdentifier, to: &rows)
        append("Default application", defaultApplication, to: &rows)

        let resolvedPath: String = item.url.resolvingSymlinksInPath().path
        if resolvedPath != item.path {
            rows.append(FileInformationRow("Resolved path", resolvedPath))
        }
        append("Resource ID", values?.fileResourceIdentifier.map { String(describing: $0) }, to: &rows, monospaced: true)
        append("Generation ID", values?.generationIdentifier.map { String(describing: $0) }, to: &rows, monospaced: true)
        append("Document ID", values?.documentIdentifier.map(String.init), to: &rows, monospaced: true)

        if let bundle: Bundle = Bundle(url: item.url) {
            append("Bundle identifier", bundle.bundleIdentifier, to: &rows)
            append("Version", bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, to: &rows)
            append("Build", bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, to: &rows)
            append("Executable", bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, to: &rows)
        }
        return FileInformationSection(title: "Identity", rows: rows)
    }

    private static func sizeSection(
        item: DiskItem,
        values: URLResourceValues?,
        attributes: [FileAttributeKey: Any],
        usePhysicalSize: Bool,
        isSizeUnknown: Bool
    ) -> FileInformationSection {
        // Scan-derived sizes default to 0 when the item (or something inside it)
        // couldn't be scanned - showing "0 KB" would misleadingly claim a verified,
        // empty size instead of an unknown one.
        var rows: [FileInformationRow] = [
            FileInformationRow("Scan size", isSizeUnknown ? "?" : byteString(item.sizeValue(usePhysicalSize: usePhysicalSize))),
            FileInformationRow("Physical size", isSizeUnknown ? "?" : byteString(item.allocatedSizeValue)),
            FileInformationRow("Logical size", isSizeUnknown ? "?" : byteString(item.logicalSizeValue))
        ]
        appendBytes("Data size", values?.fileSize, to: &rows)
        appendBytes("Allocated data", values?.fileAllocatedSize, to: &rows)
        appendBytes("Total size", values?.totalFileSize, to: &rows)
        appendBytes("Total allocated", values?.totalFileAllocatedSize, to: &rows)

        if item.isFolder {
            let counts: (files: Int, folders: Int) = item.scanCounts(includeSelf: false)
            rows.append(FileInformationRow("Contents", "\(counts.files.formatted()) files, \(counts.folders.formatted()) folders"))
        }
        appendNumber("Hard links", attributes[.referenceCount], to: &rows)
        return FileInformationSection(title: "Sizes", rows: rows)
    }

    private static func dateSection(values: URLResourceValues?) -> FileInformationSection {
        var rows: [FileInformationRow] = []
        appendDate("Created", values?.creationDate, to: &rows)
        appendDate("Modified", values?.contentModificationDate, to: &rows)
        appendDate("Last accessed", values?.contentAccessDate, to: &rows)
        appendDate("Attributes changed", values?.attributeModificationDate, to: &rows)
        appendDate("Added to folder", values?.addedToDirectoryDate, to: &rows)
        return FileInformationSection(title: "Dates", rows: rows)
    }

    private static func finderSection(
        item: DiskItem,
        values: URLResourceValues?,
        attributes: [FileAttributeKey: Any],
        extendedAttributes: [FileExtendedAttribute]
    ) -> FileInformationSection {
        var rows: [FileInformationRow] = []
        if let commentAttribute: FileExtendedAttribute = extendedAttributes.first(where: {
            $0.name == "com.apple.metadata:kMDItemFinderComment"
        }) {
            append("Finder comment", propertyListDescription(commentAttribute.data), to: &rows)
        } else {
            rows.append(FileInformationRow("Finder comment", "None"))
        }
        if let tags: [String] = values?.tagNames, !tags.isEmpty {
            rows.append(FileInformationRow("Tags", tags.joined(separator: ", ")))
        }
        if let labelNumber: Int = values?.labelNumber {
            rows.append(FileInformationRow("Finder label", String(labelNumber)))
        }

        rows.append(FileInformationRow("Hidden", yesNo(values?.isHidden == true)))
        rows.append(FileInformationRow("Extension hidden", yesNo(values?.hasHiddenExtension == true || (attributes[.extensionHidden] as? Bool) == true)))
        rows.append(FileInformationRow("Package", yesNo(item.isPackage)))
        rows.append(FileInformationRow("Alias or symlink", yesNo(item.isAliasOrSymbolicLink)))
        rows.append(FileInformationRow("Excluded from backup", yesNo(values?.isExcludedFromBackup == true)))
        rows.append(FileInformationRow("User immutable", yesNo(values?.isUserImmutable == true)))
        rows.append(FileInformationRow("System immutable", yesNo(values?.isSystemImmutable == true)))

        if let finderInfo: FileExtendedAttribute = extendedAttributes.first(where: { $0.name == "com.apple.FinderInfo" }),
           let data: Data = finderInfo.data {
            rows.append(FileInformationRow("Finder flags", finderFlagsDescription(data), monospaced: true))
            rows.append(FileInformationRow("FinderInfo", hexString(data), monospaced: true))
        }
        if let quarantine = values?.quarantineProperties {
            rows.append(FileInformationRow("Quarantine", String(describing: quarantine), monospaced: true))
        }
        return FileInformationSection(title: "Finder", rows: rows)
    }

    private static func permissionSection(
        path: String,
        values: URLResourceValues?,
        attributes: [FileAttributeKey: Any]
    ) -> FileInformationSection {
        var rows: [FileInformationRow] = []
        append("Owner", attributes[.ownerAccountName] as? String, to: &rows)
        appendNumber("Owner ID", attributes[.ownerAccountID], to: &rows)
        append("Group", attributes[.groupOwnerAccountName] as? String, to: &rows)
        appendNumber("Group ID", attributes[.groupOwnerAccountID], to: &rows)

        if let permissions: NSNumber = attributes[.posixPermissions] as? NSNumber {
            let mode: UInt16 = permissions.uint16Value
            rows.append(FileInformationRow("POSIX mode", String(format: "%04o", mode), monospaced: true))
            rows.append(FileInformationRow("Permissions", symbolicPermissions(mode), monospaced: true))
        }
        rows.append(FileInformationRow("Readable", yesNo(values?.isReadable == true)))
        rows.append(FileInformationRow("Writable", yesNo(values?.isWritable == true)))
        rows.append(FileInformationRow("Executable", yesNo(values?.isExecutable == true)))
        rows.append(FileInformationRow("Append only", yesNo((attributes[.appendOnly] as? Bool) == true)))
        rows.append(FileInformationRow("Immutable", yesNo((attributes[.immutable] as? Bool) == true)))

        if let acl: String = accessControlList(atPath: path), !acl.isEmpty {
            rows.append(FileInformationRow("Access control list", acl, monospaced: true))
        } else {
            rows.append(FileInformationRow("Access control list", "None"))
        }
        return FileInformationSection(title: "Ownership and Access", rows: rows)
    }

    private static func fileSystemSection(
        item: DiskItem,
        values: URLResourceValues?,
        attributes: [FileAttributeKey: Any]
    ) -> FileInformationSection {
        var rows: [FileInformationRow] = []
        append("File type", attributes[.type].map { String(describing: $0) }, to: &rows)
        appendNumber("File number", attributes[.systemFileNumber], to: &rows)
        appendNumber("File system number", attributes[.systemNumber], to: &rows)
        appendNumber("Device identifier", attributes[.deviceIdentifier], to: &rows)
        appendNumber("Reference count", attributes[.referenceCount], to: &rows)
        rows.append(FileInformationRow("Directory", yesNo(values?.isDirectory == true)))
        rows.append(FileInformationRow("Regular file", yesNo(values?.isRegularFile == true)))
        rows.append(FileInformationRow("Symbolic link", yesNo(values?.isSymbolicLink == true)))
        rows.append(FileInformationRow("Busy", yesNo((attributes[.busy] as? Bool) == true)))
        rows.append(FileInformationRow("Hardlink duplicate", yesNo(item.isHardlinkDuplicate)))
        return FileInformationSection(title: "File System", rows: rows)
    }

    private static func extendedAttributeSection(_ attributes: [FileExtendedAttribute]) -> FileInformationSection {
        let rows: [FileInformationRow] = attributes.isEmpty ? [
            FileInformationRow("Attributes", "None")
        ] : attributes.map { attribute in
            let value: String
            if let data: Data = attribute.data {
                value = "\(attribute.size.formatted()) bytes\n\(extendedAttributeDescription(name: attribute.name, data: data))"
            } else {
                value = "\(attribute.size.formatted()) bytes"
            }
            return FileInformationRow(
                verbatimLabel: attribute.name,
                value,
                monospaced: true
            )
        }
        return FileInformationSection(title: "Extended Attributes", rows: rows)
    }

    private static func append(
        _ label: String.LocalizationValue,
        _ value: String?,
        to rows: inout [FileInformationRow],
        monospaced: Bool = false
    ) {
        guard let value, !value.isEmpty else {
            return
        }
        rows.append(FileInformationRow(label, value, monospaced: monospaced))
    }

    private static func appendBytes(
        _ label: String.LocalizationValue,
        _ value: Int?,
        to rows: inout [FileInformationRow]
    ) {
        guard let value, value >= 0 else {
            return
        }
        rows.append(FileInformationRow(label, byteString(UInt64(value))))
    }

    private static func appendBoolean(
        _ label: String.LocalizationValue,
        _ value: Bool?,
        to rows: inout [FileInformationRow]
    ) {
        guard let value else {
            return
        }
        rows.append(FileInformationRow(label, yesNo(value)))
    }

    private static func appendNumber(
        _ label: String.LocalizationValue,
        _ value: Any?,
        to rows: inout [FileInformationRow]
    ) {
        guard let number: NSNumber = value as? NSNumber else {
            return
        }
        rows.append(FileInformationRow(label, number.stringValue, monospaced: true))
    }

    private static func appendDate(
        _ label: String.LocalizationValue,
        _ value: Date?,
        to rows: inout [FileInformationRow]
    ) {
        guard let value else {
            return
        }
        rows.append(FileInformationRow(label, value.formatted(date: .complete, time: .standard)))
    }

    private static func byteString(_ bytes: UInt64) -> String {
        String(
            localized: "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) (\(bytes.formatted()) bytes)"
        )
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    private static func symbolicPermissions(_ mode: UInt16) -> String {
        let masks: [UInt16] = [
            0o400, 0o200, 0o100,
            0o040, 0o020, 0o010,
            0o004, 0o002, 0o001
        ]
        let symbols: [Character] = ["r", "w", "x", "r", "w", "x", "r", "w", "x"]
        var characters: [Character] = zip(masks, symbols).map {
            mode & $0.0 == 0 ? "-" : $0.1
        }
        if mode & 0o4000 != 0 {
            characters[2] = mode & 0o100 == 0 ? "S" : "s"
        }
        if mode & 0o2000 != 0 {
            characters[5] = mode & 0o010 == 0 ? "S" : "s"
        }
        if mode & 0o1000 != 0 {
            characters[8] = mode & 0o001 == 0 ? "T" : "t"
        }
        return String(characters)
    }

    private static func accessControlList(atPath path: String) -> String? {
        guard let acl = acl_get_file(path, ACL_TYPE_EXTENDED) else {
            return nil
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length) else {
            return nil
        }
        defer { acl_free(text) }
        return String(cString: text)
    }

    private static func readExtendedAttributes(atPath path: String) -> [FileExtendedAttribute] {
        path.withCString { filePath in
            let nameBufferSize: Int = listxattr(filePath, nil, 0, XATTR_NOFOLLOW)
            guard nameBufferSize > 0 else {
                return []
            }

            var nameBuffer: [CChar] = Array(repeating: 0, count: nameBufferSize)
            let namesRead: Int = listxattr(filePath, &nameBuffer, nameBuffer.count, XATTR_NOFOLLOW)
            guard namesRead > 0 else {
                return []
            }

            let namesData: Data = nameBuffer.withUnsafeBytes { buffer in
                Data(buffer.prefix(namesRead))
            }
            let names: [String] = namesData.split(separator: 0).map {
                String(decoding: $0, as: UTF8.self)
            }
            return names.sorted().compactMap { name in
                name.withCString { attributeName in
                    let size: Int = getxattr(filePath, attributeName, nil, 0, 0, XATTR_NOFOLLOW)
                    guard size >= 0 else {
                        return nil
                    }
                    guard size <= 65_536 else {
                        return FileExtendedAttribute(name: name, size: size, data: nil)
                    }
                    guard size > 0 else {
                        return FileExtendedAttribute(name: name, size: 0, data: Data())
                    }
                    var bytes: [UInt8] = Array(repeating: 0, count: size)
                    let bytesRead: Int = getxattr(filePath, attributeName, &bytes, bytes.count, 0, XATTR_NOFOLLOW)
                    let data: Data? = bytesRead >= 0 ? Data(bytes.prefix(bytesRead)) : nil
                    return FileExtendedAttribute(name: name, size: size, data: data)
                }
            }
        }
    }

    private static func propertyListDescription(_ data: Data?) -> String? {
        guard let data,
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }
        if let string: String = value as? String {
            return string
        }
        if let strings: [String] = value as? [String] {
            return strings.joined(separator: ", ")
        }
        return String(describing: value)
    }

    private static func finderFlagsDescription(_ data: Data) -> String {
        guard data.count >= 10 else {
            return String(localized: "Unavailable")
        }
        let flags: UInt16 = UInt16(data[8]) << 8 | UInt16(data[9])
        let knownFlags: [(UInt16, String)] = [
            (0x0001, "On desktop"),
            (0x0040, "Shared"),
            (0x0100, "Initialized"),
            (0x0400, "Custom icon"),
            (0x0800, "Stationery"),
            (0x1000, "Name locked"),
            (0x2000, "Bundle"),
            (0x4000, "Invisible"),
            (0x8000, "Alias")
        ]
        let names: [String] = knownFlags.compactMap { flags & $0.0 == 0 ? nil : $0.1 }
        let description: String = names.isEmpty
            ? String(localized: "None")
            : names.joined(separator: ", ")
        return String(format: "0x%04X (%@)", flags, description)
    }

    private static func extendedAttributeDescription(name: String, data: Data) -> String {
        if name.hasPrefix("com.apple.metadata:"),
           let description: String = propertyListDescription(data) {
            return description
        }
        if name == "com.apple.quarantine",
           let string: String = String(data: data, encoding: .utf8) {
            return string
        }
        if name == "com.apple.FinderInfo" {
            return hexString(data)
        }
        if let string: String = String(data: data, encoding: .utf8),
           string.unicodeScalars.allSatisfy({
               !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t"
           }) {
            return string
        }
        return hexString(data.prefix(128)) + (data.count > 128 ? "\n(first 128 bytes)" : "")
    }

    private static func hexString<T: DataProtocol>(_ data: T) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

nonisolated struct FileInformationSection: Identifiable, Sendable {
    let title: String
    let rows: [FileInformationRow]

    init(title: String.LocalizationValue, rows: [FileInformationRow]) {
        self.title = String(localized: title)
        self.rows = rows
    }

    var id: String { title }
}

nonisolated struct FileInformationRow: Identifiable, Sendable {
    let label: String
    let value: String
    let monospaced: Bool

    init(
        _ label: String.LocalizationValue,
        _ value: String,
        monospaced: Bool = false
    ) {
        self.label = String(localized: label)
        self.value = value
        self.monospaced = monospaced
    }

    init(verbatimLabel label: String, _ value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var id: String { label }
    var isMultiline: Bool { value.contains("\n") }
}

nonisolated private struct FileExtendedAttribute {
    let name: String
    let size: Int
    let data: Data?
}
