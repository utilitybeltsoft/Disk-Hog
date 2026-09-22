import SwiftUI

/// Resize the viewport, not the information document or its column layout.
struct InspectorInformationScrollView<Content: View>: View {
    static var documentWidth: CGFloat { 680 }
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            content
                .frame(width: Self.documentWidth, alignment: .leading)
                .padding(10)
                .containerRelativeFrame(.horizontal, alignment: .leading)
                .frame(minWidth: Self.documentWidth + 20, alignment: .leading)
        }
        .defaultScrollAnchor(.topLeading)
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
