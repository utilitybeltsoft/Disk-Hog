import Foundation

nonisolated struct PackedDiskItemStringRange: Sendable {
    let offset: Int
    let length: Int

    static let none: PackedDiskItemStringRange = PackedDiskItemStringRange(offset: 0, length: -1)
}

nonisolated struct PackedDiskItemRecord: Sendable {
    let path: PackedDiskItemStringRange
    let fileSystemName: PackedDiskItemStringRange
    let displayName: PackedDiskItemStringRange
    let kindName: PackedDiskItemStringRange
    let firstChild: Int
    let childCount: Int
    let allocatedSizeValue: UInt64
    let logicalSizeValue: UInt64
    let fileCount: Int
    let folderCount: Int
    let itemType: DiskItemType
    let isDirectory: Bool
    let isPackage: Bool
    let isAliasOrSymbolicLink: Bool
    let isHardlinkDuplicate: Bool
    let isRoot: Bool
}

nonisolated final class PackedDiskItemChunk: @unchecked Sendable {
    let records: [PackedDiskItemRecord]
    let childIndices: [Int]
    private let stringBytes: Data

    init(records: [PackedDiskItemRecord], childIndices: [Int], stringBytes: Data) {
        self.records = records
        self.childIndices = childIndices
        self.stringBytes = stringBytes
    }

    func string(in range: PackedDiskItemStringRange) -> String? {
        guard range.length >= 0 else { return nil }
        guard range.length > 0 else { return "" }
        return stringBytes.withUnsafeBytes { bytes in
            guard let baseAddress: UnsafeRawPointer = bytes.baseAddress else { return "" }
            let start: UnsafePointer<UInt8> = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: range.offset)
            return String(decoding: UnsafeBufferPointer(start: start, count: range.length), as: UTF8.self)
        }
    }
}

nonisolated struct PackedDiskItemAddress: Hashable, Sendable {
    let chunkIndex: Int
    let recordIndex: Int
}

nonisolated final class PackedDiskItemSnapshot: @unchecked Sendable {
    let chunks: [PackedDiskItemChunk]
    let rootAddress: PackedDiskItemAddress
    private let rootChildren: [PackedDiskItemAddress]?

    init(
        chunks: [PackedDiskItemChunk],
        rootAddress: PackedDiskItemAddress,
        rootChildren: [PackedDiskItemAddress]? = nil
    ) {
        self.chunks = chunks
        self.rootAddress = rootAddress
        self.rootChildren = rootChildren
    }

    func record(at address: PackedDiskItemAddress) -> PackedDiskItemRecord {
        chunks[address.chunkIndex].records[address.recordIndex]
    }

    func string(_ range: PackedDiskItemStringRange, at address: PackedDiskItemAddress) -> String? {
        chunks[address.chunkIndex].string(in: range)
    }

    func children(of address: PackedDiskItemAddress) -> [PackedDiskItemAddress] {
        if address == rootAddress, let rootChildren {
            return rootChildren
        }
        let record: PackedDiskItemRecord = record(at: address)
        guard record.childCount > 0 else { return [] }
        let chunk: PackedDiskItemChunk = chunks[address.chunkIndex]
        return chunk.childIndices[record.firstChild..<(record.firstChild + record.childCount)].map {
            PackedDiskItemAddress(chunkIndex: address.chunkIndex, recordIndex: $0)
        }
    }

    func childCount(of address: PackedDiskItemAddress) -> Int {
        if address == rootAddress, let rootChildren { return rootChildren.count }
        return record(at: address).childCount
    }

    func child(of address: PackedDiskItemAddress, at index: Int) -> PackedDiskItemAddress {
        if address == rootAddress, let rootChildren { return rootChildren[index] }
        let record: PackedDiskItemRecord = record(at: address)
        let childRecordIndex: Int = chunks[address.chunkIndex].childIndices[record.firstChild + index]
        return PackedDiskItemAddress(chunkIndex: address.chunkIndex, recordIndex: childRecordIndex)
    }

    func scanCounts(at address: PackedDiskItemAddress) -> (files: Int, folders: Int) {
        let record: PackedDiskItemRecord = record(at: address)
        guard address == rootAddress, let rootChildren else {
            return (record.fileCount, record.folderCount)
        }
        return rootChildren.reduce(into: (files: record.fileCount, folders: record.folderCount)) { counts, child in
            let childRecord: PackedDiskItemRecord = self.record(at: child)
            counts.files += childRecord.fileCount
            counts.folders += childRecord.folderCount
        }
    }
}

nonisolated struct PackedDiskItemStringEncoder {
    private(set) var data: Data = Data()

    mutating func append(_ string: String?) -> PackedDiskItemStringRange {
        guard let string else { return .none }
        let bytes: [UInt8] = Array(string.utf8)
        let range: PackedDiskItemStringRange = PackedDiskItemStringRange(offset: data.count, length: bytes.count)
        data.append(contentsOf: bytes)
        return range
    }
}
