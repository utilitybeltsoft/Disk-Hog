import Foundation
import Testing
@testable import disk_hog

@MainActor
struct ScanSourceClassificationTests {
    @Test func choosingVolumeRootPreservesBookmarkAndLoadsVolumeMetadata() throws {
        let bookmark = Data([1, 2, 3])
        let source = ScanSourceProvider.scanSource(for: URL(fileURLWithPath: "/", isDirectory: true), bookmarkData: bookmark)
        #expect(source.isVolumeRoot == true)
        #expect(source.volumeKind != .folder)
        #expect(source.bookmarkData == bookmark)
        #expect(source.totalCapacity != nil)
        #expect(source.availableCapacity != nil)
    }

    @Test func folderWithoutBookmarkDoesNotBecomeAVolume() {
        let source = ScanSourceProvider.scanSource(for: FileManager.default.temporaryDirectory)
        #expect(source.isVolumeRoot == false)
        #expect(source.volumeKind == .folder)
        #expect(source.totalCapacity == nil)
    }

    @Test func volumeTypesAreIndependentOfBookmarks() throws {
        let bookmark = Data([1])
        let sources: [(ScanSource, ScanSourceVolumeKind)] = [
            (ScanSource(path: "/", displayName: "Internal", bookmarkData: bookmark, isVolumeRoot: true, isInternalVolume: true), .internalVolume),
            (ScanSource(path: "/Volumes/External", displayName: "External", bookmarkData: bookmark, isVolumeRoot: true, isRemovableVolume: true), .externalVolume),
            (ScanSource(path: "/Volumes/Network", displayName: "Network", bookmarkData: bookmark, isVolumeRoot: true, isLocalVolume: false), .networkVolume),
            (ScanSource(path: "/Volumes/Image", displayName: "Image", bookmarkData: bookmark, isVolumeRoot: true, isDiskImageVolume: true), .diskImage)
        ]
        for (source, expected) in sources {
            #expect(source.volumeKind == expected)
            #expect(source.applyingScanSettings(.diskInventoryZDefault).volumeKind == expected)
            #expect(source.replacingBookmarkData(Data([2])).volumeKind == expected)
            let decoded = try JSONDecoder().decode(ScanSource.self, from: JSONEncoder().encode(source))
            #expect(decoded.isVolumeRoot == true)
            #expect(decoded.bookmarkData == bookmark)
            #expect(decoded.volumeKind == expected)
        }
    }

    @Test func oldSourcesStillDecodeWithoutExplicitIdentity() throws {
        let data = Data(#"{"path":"/old","displayName":"Old","bookmarkData":"AQ=="}"#.utf8)
        let source = try JSONDecoder().decode(ScanSource.self, from: data)
        #expect(source.isVolumeRoot == nil)
        #expect(source.volumeKind == .folder)
    }
}
