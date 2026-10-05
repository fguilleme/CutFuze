import SwiftUI

private struct PinnedPreview: ViewModifier {
    var image: CGImage?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: verticalSizeClass == .compact ? 80 : 160)
                    .padding(.vertical, 8).background(DesignTokens.ink)
                    .accessibilityLabel(L("Aperçu du réglage"))
            }
        }
    }
}
extension View {
    func pinnedPreview(_ image: CGImage?) -> some View { modifier(PinnedPreview(image: image)) }
}
