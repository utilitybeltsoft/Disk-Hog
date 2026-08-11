import AppKit

@MainActor
protocol DiskItemPasteboardProviding: AnyObject {
    var pasteboardItemProvider: (() -> DiskItem?)? { get set }
}

@MainActor
extension DiskItemPasteboardProviding where Self: NSResponder {
    func copySelectedItem() {
        guard let item: DiskItem = pasteboardItemProvider?() else {
            return
        }
        DiskItemPasteboardWriter(item: item).write(to: .general)
    }

    func servicesRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        guard returnType == nil,
              let sendType,
              DiskItemPasteboardWriter.writableTypes.contains(sendType),
              pasteboardItemProvider?() != nil else {
            return nil
        }
        return self
    }

    func writeSelectedItem(to pasteboard: NSPasteboard) -> Bool {
        guard let item: DiskItem = pasteboardItemProvider?() else {
            return false
        }
        return DiskItemPasteboardWriter(item: item).write(to: pasteboard)
    }
}

final class DiskItemPasteboardOutlineView: NSOutlineView, DiskItemPasteboardProviding {
    var pasteboardItemProvider: (() -> DiskItem?)?

    @objc func copy(_ sender: Any?) {
        copySelectedItem()
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        servicesRequestor(forSendType: sendType, returnType: returnType)
            ?? super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc(writeSelectionToPasteboard:types:)
    func writeSelection(
        to pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        writeSelectedItem(to: pasteboard)
    }
}

class DiskItemPasteboardTableView: NSTableView, DiskItemPasteboardProviding {
    var pasteboardItemProvider: (() -> DiskItem?)?

    @objc func copy(_ sender: Any?) {
        copySelectedItem()
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        servicesRequestor(forSendType: sendType, returnType: returnType)
            ?? super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc(writeSelectionToPasteboard:types:)
    func writeSelection(
        to pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        writeSelectedItem(to: pasteboard)
    }
}
