import AppKit
import SwiftUI

struct SourcePaletteView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var sources: [ScanSource] = ScanSourceProvider.mountedVolumes()

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.outerSpacing) {
            header

            List(sources) { source in
                Button {
                    openWindow(value: source)
                } label: {
                    HStack(spacing: Metrics.sourceRowSpacing) {
                        Image(systemName: "externaldrive")
                            .frame(width: Metrics.sourceIconWidth)
                        VStack(alignment: .leading, spacing: Metrics.sourceTextSpacing) {
                            Text(source.displayName)
                                .font(.headline)
                                .lineLimit(Metrics.singleLineLimit)
                            Text(source.path)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(Metrics.singleLineLimit)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, Metrics.sourceRowVerticalPadding)
            }
            .frame(minHeight: Metrics.volumeListMinimumHeight)

            HStack(spacing: Metrics.buttonSpacing) {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder...", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    sources = ScanSourceProvider.mountedVolumes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()
            }
        }
        .padding(Metrics.windowPadding)
        .frame(minWidth: Metrics.windowMinimumWidth, minHeight: Metrics.windowMinimumHeight)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Disk Hog")
                .font(.largeTitle.weight(.semibold))
            Text("Choose a volume or folder to scan.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"

        guard panel.runModal() == .OK, let url: URL = panel.url else {
            return
        }

        let source: ScanSource = ScanSourceProvider.scanSource(for: url)
        openWindow(value: source)
    }
}

private enum SourcePaletteMetrics {
    static let outerSpacing: CGFloat = 16
    static let headerSpacing: CGFloat = 4
    static let sourceRowSpacing: CGFloat = 10
    static let sourceTextSpacing: CGFloat = 2
    static let sourceIconWidth: CGFloat = 22
    static let sourceRowVerticalPadding: CGFloat = 5
    static let buttonSpacing: CGFloat = 10
    static let volumeListMinimumHeight: CGFloat = 220
    static let windowPadding: CGFloat = 20
    static let windowMinimumWidth: CGFloat = 520
    static let windowMinimumHeight: CGFloat = 380
    static let singleLineLimit: Int = 1
}

private typealias Metrics = SourcePaletteMetrics
