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
                    ScanPreparationProgressBar(progress: progress)
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

private struct ScanPreparationProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let fillWidth: CGFloat = geometry.size.width * CGFloat(min(max(progress, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.28))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: fillWidth)
            }
        }
        .frame(width: 120, height: 6)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
