import Foundation
import Testing
@testable import disk_hog

@MainActor
struct AboutDocumentsTests {
    @Test func bundledLicenseAndOriginalNoticesAreReadableOffline() throws {
        let license = try AboutDocuments.license()
        #expect(license.contains("Version 3, 29 June 2007"))
        #expect(license.contains("END OF TERMS AND CONDITIONS"))
        let notices = try AboutDocuments.notices()
        #expect(notices.contains("Tjark Derlien"))
        #expect(notices.contains("Dani Sarfati"))
        #expect(notices.contains("THE SOFTWARE IS PROVIDED"))
        #expect(notices.contains("Version 2, June 1991"))
    }

    @Test func sourceLinkRequiresExplicitSecureWebDestination() {
        for value: String? in [nil, "", "not a URL", "file:///tmp/source", "http://example.org/v1", "https://", "https://user:password@example.org/v1"] {
            #expect(AboutDocuments.sourceURL(from: value) == nil)
        }
        let release = "https://example.org/releases/v1.0/Disk-Hog-1.0-source.tar.gz"
        #expect(AboutDocuments.sourceURL(from: release)?.absoluteString == release)
    }

    @Test func builtAppIncludesReleaseMetadata() throws {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Disk Hog")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "1.0.1")
        #expect(AboutDocuments.sourceURL() != nil)
        let url = try #require(Bundle.main.url(forResource: "BuildRevision", withExtension: "txt"))
        let revision = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(revision.range(of: "^[0-9a-f]{40}(-modified)?$", options: .regularExpression) != nil)
    }

    @Test func versionIdentifiesCleanAndModifiedCommitsWithoutATimestamp() {
        let hash = "0123456789abcdef0123456789abcdef01234567"
        #expect(AboutDocuments.versionDescription(version: "1.0.1", revision: hash) == "1.0.1 (0123456)")
        #expect(AboutDocuments.versionDescription(version: "1.0.1", revision: hash + "-modified") == "1.0.1 (0123456-modified)")
        #expect(AboutDocuments.versionDescription(version: "1.0.1", revision: nil) == "1.0.1")
        #expect(AboutDocuments.versionDescription(version: "1.0.1", revision: "unknown") == "1.0.1")
    }

    @Test func missingDocumentsReportFailure() {
        #expect(throws: (any Error).self) {
            try AboutDocuments.license(in: Bundle(for: BundleMarker.self))
        }
    }
}

private final class BundleMarker: NSObject {}
