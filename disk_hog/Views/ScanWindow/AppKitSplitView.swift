import AppKit
import SwiftUI

struct AppKitSplitView<First: View, Second: View>: NSViewRepresentable {
    let isVertical: Bool
    let firstMinimumSize: CGFloat
    let secondMinimumSize: CGFloat
    let firstPreferredFraction: CGFloat
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isVertical: isVertical,
            firstMinimumSize: firstMinimumSize,
            secondMinimumSize: secondMinimumSize,
            firstPreferredFraction: firstPreferredFraction
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView: NSSplitView = NSSplitView()
        splitView.isVertical = isVertical
        splitView.dividerStyle = .paneSplitter
        splitView.delegate = context.coordinator
        splitView.autosaveName = nil

        let firstHostingView: NSHostingView<First> = NSHostingView(rootView: first())
        let secondHostingView: NSHostingView<Second> = NSHostingView(rootView: second())
        firstHostingView.translatesAutoresizingMaskIntoConstraints = false
        secondHostingView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(firstHostingView)
        splitView.addArrangedSubview(secondHostingView)
        context.coordinator.firstHostingView = firstHostingView
        context.coordinator.secondHostingView = secondHostingView
        context.coordinator.scheduleDividerPosition(in: splitView)
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.firstMinimumSize = firstMinimumSize
        context.coordinator.secondMinimumSize = secondMinimumSize
        context.coordinator.firstPreferredFraction = firstPreferredFraction
        context.coordinator.isVertical = isVertical
        context.coordinator.scheduleDividerPosition(in: splitView)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var isVertical: Bool
        var firstMinimumSize: CGFloat
        var secondMinimumSize: CGFloat
        var firstPreferredFraction: CGFloat
        weak var firstHostingView: NSHostingView<First>?
        weak var secondHostingView: NSHostingView<Second>?
        private var didSetInitialDividerPosition: Bool = false

        init(
            isVertical: Bool,
            firstMinimumSize: CGFloat,
            secondMinimumSize: CGFloat,
            firstPreferredFraction: CGFloat
        ) {
            self.isVertical = isVertical
            self.firstMinimumSize = firstMinimumSize
            self.secondMinimumSize = secondMinimumSize
            self.firstPreferredFraction = firstPreferredFraction
        }

        func scheduleDividerPosition(in splitView: NSSplitView) {
            guard !didSetInitialDividerPosition else {
                return
            }

            DispatchQueue.main.async { [weak self, weak splitView] in
                guard let self: Coordinator = self,
                      let splitView: NSSplitView = splitView,
                      !self.didSetInitialDividerPosition else {
                    return
                }

                let availableSize: CGFloat = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
                guard availableSize > self.firstMinimumSize + self.secondMinimumSize else {
                    return
                }

                let proposedPosition: CGFloat = availableSize * self.firstPreferredFraction
                let minimumPosition: CGFloat = self.firstMinimumSize
                let maximumPosition: CGFloat = availableSize - self.secondMinimumSize
                let position: CGFloat = min(max(proposedPosition, minimumPosition), maximumPosition)
                splitView.setPosition(position, ofDividerAt: 0)
                self.didSetInitialDividerPosition = true
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            firstMinimumSize
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let availableSize: CGFloat = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            return max(firstMinimumSize, availableSize - secondMinimumSize)
        }
    }
}
