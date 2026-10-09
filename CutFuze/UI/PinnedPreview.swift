import SwiftUI

private struct PinnedPreview: ViewModifier {
    var image: CGImage?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let image {
                GeometryReader { geometry in
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }.frame(height: verticalSizeClass == .compact ? 80 : 160).clipped()
                    .padding(.vertical, 8).background(DesignTokens.ink)
                    .accessibilityLabel(L("Aperçu du réglage"))
            }
        }
    }
}
extension View {
    func pinnedPreview(_ image: CGImage?) -> some View { modifier(PinnedPreview(image: image)) }
}
