import Testing
@testable import disk_hog

struct ScanWindowTitleTests {
    @Test func folderTitleIncludesFullPathEvenWhenNameIsVolumeName() {
        let source = ScanSource(path: "/Volumes/Media/TV episodes", displayName: "Media")
        #expect(source.scanWindowTitle == "Media — /Volumes/Media/TV episodes")
    }

    @Test func foldersOnSameVolumeHaveDistinctTitles() {
        let first = ScanSource(path: "/Users/test/Photos", displayName: "Macintosh HD")
        let second = ScanSource(path: "/Users/test/Archive/Photos", displayName: "Macintosh HD")
        #expect(first.scanWindowTitle != second.scanWindowTitle)
    }

    @Test func volumeTitlesRetainNameAndRootPath() {
        #expect(ScanSource(path: "/", displayName: "Macintosh HD").scanWindowTitle == "Macintosh HD — /")
        #expect(ScanSource(path: "/Volumes/Media", displayName: "Media").scanWindowTitle == "Media — /Volumes/Media")
    }

    @Test func absentOrPathDisplayNameDoesNotDuplicatePath() {
        #expect(ScanSource(path: "/scan", displayName: "").scanWindowTitle == "/scan")
        #expect(ScanSource(path: "/scan", displayName: "/scan").scanWindowTitle == "/scan")
    }
}
