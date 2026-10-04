import AppKit
import SwiftUI

@MainActor
enum AboutDocuments {
    static let companyWebsiteURL = URL(string: "https://utilitybelt.software/")!

    static func sourceURL(in bundle: Bundle = .main) -> URL? {
        sourceURL(from: bundle.object(forInfoDictionaryKey: "DiskHogSourceURL") as? String)
    }

    static func sourceURL(from value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func versionDescription(in bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let revision = bundle.url(forResource: "BuildRevision", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return versionDescription(version: version, revision: revision)
    }

    static func versionDescription(version: String, revision: String?) -> String {
        guard let revision, revision != "unknown", !revision.isEmpty else { return version }
        let hash = revision.split(separator: "-")[0]
        let suffix = revision.hasSuffix("-modified") ? "-modified" : ""
        return "\(version) (\(hash.prefix(7))\(suffix))"
    }

    static func license(in bundle: Bundle = .main) throws -> String {
        try text("COPYING", in: bundle)
    }

    static func notices(in bundle: Bundle = .main) throws -> String {
        let notice = try text("THIRD-PARTY-NOTICES.txt", in: bundle)
        let readmeURL = try resource("TreeMapView-1.0-readme.rtf", in: bundle)
        let readme = try NSAttributedString(
            url: readmeURL, options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ).string
        let historicalLicense = try text("TreeMapView-1.0-GPL.txt", in: bundle)
        return [notice, readme, historicalLicense].joined(separator: "\n\n────────────────────\n\n")
    }

    private static func resource(_ name: String, in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private static func text(_ name: String, in bundle: Bundle) throws -> String {
        try String(contentsOf: resource(name, in: bundle), encoding: .utf8)
    }
}

@MainActor
final class AboutWindowController {
    private var aboutWindow: NSWindow?
    private var documentWindow: NSWindow?

    func show() {
        if aboutWindow == nil {
            let window = makeWindow(title: String(localized: "About Disk Hog"), width: 510, height: 390)
            window.contentView = NSHostingView(rootView: AboutDiskHogView(
                sourceURL: AboutDocuments.sourceURL(),
                showLicense: { [weak self] in
                    self?.showDocument(title: String(localized: "License"), load: { try AboutDocuments.license() })
                },
                showNotices: { [weak self] in
                    self?.showDocument(title: String(localized: "Third-Party Notices"), load: { try AboutDocuments.notices() })
                }
            ))
            if let content = window.contentView { window.setContentSize(content.fittingSize) }
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    private func showDocument(title: String, load: () throws -> String) {
        do {
            let text = try load()
            let window = documentWindow ?? makeWindow(title: title, width: 720, height: 560, resizable: true)
            window.title = title
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))
            view.isEditable = false
            view.isSelectable = true
            view.isRichText = false
            view.font = .systemFont(ofSize: 13)
            view.textColor = .textColor
            view.backgroundColor = .textBackgroundColor
            view.textContainerInset = NSSize(width: 20, height: 20)
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            view.setAccessibilityLabel(title)
            view.string = text
            scroll.documentView = view
            window.contentView = scroll
            window.minSize = NSSize(width: 400, height: 300)
            documentWindow = window
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            view.scrollToBeginningOfDocument(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Unable to open bundled documentation.")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func makeWindow(title: String, width: CGFloat, height: CGFloat, resizable: Bool = false) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        return window
    }
}

private struct AboutDiskHogView: View {
    let sourceURL: URL?
    let showLicense: () -> Void
    let showNotices: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 72, height: 72).accessibilityHidden(true)
            Text(verbatim: "Disk Hog").font(.title.bold())
            Text(verbatim: version).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(verbatim: "Copyright © 2026 Utility Belt Software LLC.")
                Link(destination: AboutDocuments.companyWebsiteURL) {
                    Text(verbatim: "utilitybelt.software")
                }
            }
            Text("Includes code adapted from Disk Inventory Z, Disk Inventory X, and the TreeMapView framework, with contributions by Tjark Derlien and Dani Sarfati.")
            Text("Free software under the GNU General Public License, version 3. You may redistribute and modify it under that license. Provided without warranty.")
            HStack {
                Button("License", action: showLicense)
                Button("Third-Party Notices", action: showNotices)
            }
            Button("Source for This Version") {
                if let sourceURL { NSWorkspace.shared.open(sourceURL) }
            }
            .disabled(sourceURL == nil)
            if sourceURL == nil {
                Text("Source download will be available with the public release.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
        .padding(24)
        .frame(width: 510)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var version: String {
        AboutDocuments.versionDescription()
    }
}
