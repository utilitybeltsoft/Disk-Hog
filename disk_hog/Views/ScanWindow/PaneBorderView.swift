import SwiftUI

struct PaneBorderView: View {
    let isActive: Bool

    var body: some View {
        Rectangle()
            .stroke(
                isActive ? Color(nsColor: .systemBlue) : Color(nsColor: .gridColor),
                lineWidth: isActive ? ScanWindowMetrics.activePaneBorderWidth : ScanWindowMetrics.inactivePaneBorderWidth
            )
            .allowsHitTesting(false)
    }
}
