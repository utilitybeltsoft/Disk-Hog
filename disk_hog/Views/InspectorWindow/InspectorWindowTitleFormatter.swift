import Foundation

enum InspectorWindowTitleFormatter {
    static func title(context: InspectorWindowContext?, source: ScanSource?) -> String {
        if let context {
            return String(localized: "Inspector - \(context.session.source.scanWindowTitle)")
        }
        if let source {
            return String(localized: "Inspector - \(source.scanWindowTitle)")
        }
        return String(localized: "Inspector")
    }
}
