import Foundation

nonisolated enum ScanItemSizePresentation {
    static func text(bytes: UInt64, isIncomplete: Bool) -> String {
        if isIncomplete && bytes == 0 { return String(localized: "Unknown") }
        let measured = ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
        return isIncomplete ? "≥ " + measured : measured
    }
}
