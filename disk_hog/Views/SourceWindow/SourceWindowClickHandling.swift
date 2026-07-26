import AppKit
import SwiftUI

struct SourceBlankClickCatcherView: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> SourceBlankClickCatcherNSView {
        let view: SourceBlankClickCatcherNSView = SourceBlankClickCatcherNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: SourceBlankClickCatcherNSView, context: Context) {
        nsView.onClick = onClick
    }
}

final class SourceBlankClickCatcherNSView: NSView {
    var onClick: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

struct SourceRowClickCatcherView: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> SourceRowClickCatcherNSView {
        let view: SourceRowClickCatcherNSView = SourceRowClickCatcherNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: SourceRowClickCatcherNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

final class SourceRowClickCatcherNSView: NSView {
    var onSingleClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    private var pendingSingleClick: DispatchWorkItem?

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick()
            return
        }

        pendingSingleClick?.cancel()
        let workItem: DispatchWorkItem = DispatchWorkItem { [weak self] in
            self?.onSingleClick()
            self?.pendingSingleClick = nil
        }
        pendingSingleClick = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }
}
