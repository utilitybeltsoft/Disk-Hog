import SwiftUI

struct ScanPanePlaceholderView: View {
    let title: String
    let message: String
    var showsProgress: Bool = false

    var body: some View {
        VStack(spacing: ScanWindowMetrics.placeholderSpacing) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
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
