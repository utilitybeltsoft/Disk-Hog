import Foundation
import Testing
@testable import disk_hog

struct ScanItemSizePresentationTests {
    @Test func incompletePositiveSizeKeepsMeasuredLowerBound() {
        let measured = ScanItemSizePresentation.text(bytes: 5_000_000_000, isIncomplete: false)
        #expect(ScanItemSizePresentation.text(bytes: 5_000_000_000, isIncomplete: true) == "≥ " + measured)
    }

    @Test func incompleteZeroIsUnknownButCompleteZeroIsMeasured() {
        #expect(ScanItemSizePresentation.text(bytes: 0, isIncomplete: true) == String(localized: "Unknown"))
        #expect(ScanItemSizePresentation.text(bytes: 0, isIncomplete: false)
                == ByteCountFormatter.string(fromByteCount: 0, countStyle: .file))
    }

    @Test func largeUnsignedCountsDoNotOverflow() {
        #expect(ScanItemSizePresentation.text(bytes: UInt64.max, isIncomplete: true).hasPrefix("≥ "))
    }
}
