#if FILE_MATCHING_DIAGNOSTICS
import AppKit

@MainActor
enum ScanSessionDiagnostics {
    static func export(root: DiskItem, settings: DiskScanSettings,
                       completion: @escaping @MainActor @Sendable (DiagnosticsExportState) -> Void) {
        Task.detached(priority: .utility) {
            do {
                let url = try TreemapInputDiagnostics.writeJSONLinesReport(root: root, settings: settings)
                await MainActor.run {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([url as NSURL])
                    pasteboard.setString(url.path, forType: .string)
                    completion(.written(url.path))
                }
            } catch {
                await completion(.failed(String(describing: error)))
            }
        }
    }
}
#endif
