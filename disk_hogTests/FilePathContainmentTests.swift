import Testing
@testable import disk_hog

struct FilePathContainmentTests {
    @Test(arguments: [
        ("/", "/", true),
        ("/folder/file", "/", true),
        ("relative", "/", false),
        ("/folder", "/folder", true),
        ("/folder/file", "/folder", true),
        ("/folder/file", "/folder/", true),
        ("/folder-other/file", "/folder", false),
        ("/folder.txt", "/folder", false),
        ("/folder", "/folder/child", false),
        ("/Folder/file", "/folder", false),
        ("/tmp/file", "/private/tmp", false),
        ("/folder/link/../file", "/folder/link", true)
    ])
    func comparesLexicalPathsAtDirectoryBoundaries(candidate: String, directory: String, expected: Bool) {
        #expect(FilePathContainment.contains(candidate, in: directory) == expected)
    }
}
