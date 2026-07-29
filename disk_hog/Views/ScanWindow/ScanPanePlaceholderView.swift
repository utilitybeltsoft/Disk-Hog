import SwiftUI

struct ScanPanePlaceholderView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var showsProgress: Bool = false
    var progress: Double?

    var body: some View {
        VStack(spacing: ScanWindowMetrics.placeholderSpacing) {
            if showsProgress {
                if let progress {
                    ProgressView(value: progress, total: 1)
                        .frame(width: 120)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text(title)
                .font(.system(size: ScanWindowMetrics.placeholderTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(size: ScanWindowMetrics.placeholderPathFontSize))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(ScanWindowMetrics.placeholderPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .allowsHitTesting(false)
    }
}
