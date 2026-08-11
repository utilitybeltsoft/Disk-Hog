import AppKit
import Foundation

nonisolated final class DiskItemPasteboardWriter: NSObject, NSPasteboardWriting {
    static let writableTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string
    ]

    let item: DiskItem

    init(item: DiskItem) {
        self.item = item
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        Self.writableTypes
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL, .URL:
            item.url.absoluteString
        case .string:
            item.path
        default:
            nil
        }
    }

    @discardableResult
    func write(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([self])
    }
}
