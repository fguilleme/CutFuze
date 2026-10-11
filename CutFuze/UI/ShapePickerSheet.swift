import SwiftUI

struct ShapePickerSheet: View {
    let selected: MaskKind?
    let choose: (MaskKind) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(MaskKind.overlayShapes, id: \.self) { shape in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            choose(shape); dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                ShapeThumbnail(kind: shape).fill(DesignTokens.amber).frame(width: 56, height: 48)
                                Text(effectLabel(shape.rawValue)).font(.caption.weight(.semibold)).lineLimit(2)
                            }.frame(maxWidth: .infinity).frame(height: 100)
                                .background(selected == shape ? DesignTokens.amber.opacity(0.18) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("overlayShape-\(shape.rawValue)")
                            .accessibilityAddTraits(selected == shape ? .isSelected : [])
                    }
                }.frame(maxWidth: 540).padding(16).frame(maxWidth: .infinity)
            }.navigationTitle(L("Forme")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Fermer")) { dismiss() }.accessibilityIdentifier("closeShapePicker") } }
                .background(DesignTokens.ink)
        }.presentationDetents([.height(330), .large]).presentationSizing(.page).preferredColorScheme(.dark)
    }
}

private struct ShapeThumbnail: Shape {
    let kind: MaskKind
    func path(in rect: CGRect) -> Path {
        let path: CGPath
        switch kind {
        case .ellipse: path = CGPath(ellipseIn: rect, transform: nil)
        case .rectangle: path = TextBackgroundShape.rectangle.path(in: rect)
        case .roundedRectangle: path = TextBackgroundShape.rounded.path(in: rect)
        case .cloud: path = TextBackgroundShape.cloud.path(in: rect)
        case .star: path = TextBackgroundShape.star.path(in: rect)
        case .heart: path = TextBackgroundShape.heart.path(in: rect)
        default: path = CGPath(rect: rect, transform: nil)
        }
        return Path(path).applying(CGAffineTransform(translationX: 0, y: rect.minY + rect.maxY).scaledBy(x: 1, y: -1))
    }
}
