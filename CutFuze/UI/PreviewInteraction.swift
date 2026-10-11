import SwiftUI
import UIKit

struct PreviewElementLayout: Identifiable, Equatable {
    let id: UUID
    let center: CGPoint
    let size: CGSize
    let rotation: Double
    let layer: Int

    func contains(_ point: CGPoint, hitSlop: CGFloat = 10) -> Bool {
        let radians = CGFloat(rotation * .pi / 180)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let localX = dx * cos(radians) + dy * sin(radians)
        let localY = -dx * sin(radians) + dy * cos(radians)
        return abs(localX) <= size.width / 2 + hitSlop && abs(localY) <= size.height / 2 + hitSlop
    }
}

enum PreviewInteractionGeometry {
    static let handleTouchSize: CGFloat = 44

    static func layouts(plan: RenderPlan, time: MediaTime, canvasSize: CGSize) -> [PreviewElementLayout] {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return [] }
        return plan.clips.compactMap { item in
            guard item.clip.kind != .audio, item.isActive(at: time) else { return nil }
            let presentation = item.evaluatedPresentation(at: time)
            guard presentation.opacity > 0.001 else { return nil }
            return PreviewElementLayout(
                id: item.id,
                center: CGPoint(x: canvasSize.width * presentation.x, y: canvasSize.height * presentation.y),
                size: elementSize(item: item, presentation: presentation, plan: plan, canvasSize: canvasSize),
                rotation: presentation.rotation,
                layer: item.clip.layer
            )
        }
    }

    static func hitTest(_ point: CGPoint, layouts: [PreviewElementLayout]) -> UUID? {
        layouts.reversed().first { $0.contains(point) }?.id
    }

    static func movedPresentation(
        from origin: Presentation,
        translation: CGSize,
        canvasSize: CGSize,
        snapDistance: CGFloat = 8
    ) -> (presentation: Presentation, snappedX: Bool, snappedY: Bool) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return (origin, false, false) }
        var result = origin
        result.x = min(1.5, max(-0.5, origin.x + translation.width / canvasSize.width))
        result.y = min(1.5, max(-0.5, origin.y + translation.height / canvasSize.height))
        let snapX = abs(result.x - 0.5) * canvasSize.width <= snapDistance
        let snapY = abs(result.y - 0.5) * canvasSize.height <= snapDistance
        if snapX { result.x = 0.5 }
        if snapY { result.y = 0.5 }
        return (result, snapX, snapY)
    }

    static func containedHandlePosition(_ position: CGPoint, canvasSize: CGSize) -> CGPoint {
        let inset = handleTouchSize / 2
        guard canvasSize.width >= handleTouchSize, canvasSize.height >= handleTouchSize else {
            return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }
        return CGPoint(
            x: min(canvasSize.width - inset, max(inset, position.x)),
            y: min(canvasSize.height - inset, max(inset, position.y))
        )
    }

    // Shapes have no source aspect ratio to preserve. Resize in their local axes.
    // Grow the source canvas scale when necessary so the mask is never clipped;
    // compensate the other axis to keep its visible dimension unchanged.
    static func resizedShapePresentation(from origin: Presentation, translation: CGSize, canvasSize: CGSize) -> Presentation {
        guard canvasSize.width > 0, canvasSize.height > 0, origin.scale > 0 else { return origin }
        let radians = origin.rotation * .pi / 180
        let dx = translation.width * cos(radians) + translation.height * sin(radians)
        let dy = -translation.width * sin(radians) + translation.height * cos(radians)
        var result = origin
        let width = min(4, max(origin.scale * 0.05, origin.scale * origin.maskWidth + 2 * dx / canvasSize.width))
        let height = min(4, max(origin.scale * 0.05, origin.scale * origin.maskHeight + 2 * dy / canvasSize.height))
        result.scale = max(origin.scale, max(width, height))
        result.maskWidth = width / result.scale
        result.maskHeight = height / result.scale
        return result
    }

    private static func elementSize(item: RenderClip, presentation: Presentation, plan: RenderPlan, canvasSize: CGSize) -> CGSize {
        if item.clip.kind == .text {
            return textSize(item.clip.text, presentation: presentation, canvasSize: canvasSize)
        }
        if item.clip.kind == .shape {
            if MaskKind.overlayShapes.contains(presentation.mask), !presentation.maskInverted,
               presentation.maskX == 0.5, presentation.maskY == 0.5, presentation.maskRotation == 0 {
                return CGSize(width: max(44, canvasSize.width * presentation.scale * presentation.maskWidth), height: max(44, canvasSize.height * presentation.scale * presentation.maskHeight))
            }
            return CGSize(width: max(44, canvasSize.width * presentation.scale), height: max(44, canvasSize.height * presentation.scale))
        }
        let asset = plan.assets.first { $0.id == item.clip.assetID }
        let sourceWidth = CGFloat(max(1, asset?.width ?? 1))
        let sourceHeight = CGFloat(max(1, asset?.height ?? 1))
        let fitting = presentation.fill
            ? max(canvasSize.width / sourceWidth, canvasSize.height / sourceHeight)
            : min(canvasSize.width / sourceWidth, canvasSize.height / sourceHeight)
        return CGSize(width: max(44, sourceWidth * fitting * presentation.scale), height: max(44, sourceHeight * fitting * presentation.scale))
    }

    private static func textSize(_ text: String, presentation: Presentation, canvasSize: CGSize) -> CGSize {
        let fontSize = max(8, presentation.textSize * min(canvasSize.width, canvasSize.height))
        let fontName = presentation.textFont == "system" ? (presentation.textBold ? "HelveticaNeue-Bold" : "HelveticaNeue") : presentation.textFont
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: presentation.textBold ? .bold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = presentation.textAlignment == "left" ? .left : presentation.textAlignment == "right" ? .right : .center
        paragraph.lineSpacing = presentation.textLineSpacing * fontSize
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: presentation.textLetterSpacing * fontSize, .paragraphStyle: paragraph]
        let measured = (text.isEmpty ? " " : text).boundingRect(
            with: CGSize(width: canvasSize.width * (presentation.textBackgroundOpacity > 0 ? presentation.textBackgroundShape.widthLimit : 0.86), height: canvasSize.height * 0.9),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral.size
        let padding: CGFloat = presentation.textBackgroundOpacity > 0 ? 20 : 8
        let expansion = presentation.textBackgroundOpacity > 0 ? presentation.textBackgroundShape.expansion : 1
        return CGSize(
            width: min(canvasSize.width * 0.98, max(52, (measured.width + padding) * expansion * presentation.scale)),
            height: min(canvasSize.height * 0.98, max(36, (measured.height + padding * 0.7) * expansion * presentation.scale))
        )
    }
}

struct PreviewCanvasEditor: View {
    @ObservedObject var model: EditorModel
    let image: CGImage
    let edit: (Clip) -> Void

    @State private var pointerTracking = false
    @State private var pointerCandidateID: UUID?
    @State private var dragOrigin: Presentation?
    @State private var transformOrigin: Presentation?
    @State private var handleOrigin: Presentation?
    @State private var handleStartValue: CGFloat?
    @State private var snappedX = false
    @State private var snappedY = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let layouts = PreviewInteractionGeometry.layouts(plan: model.plan, time: .init(seconds: model.playhead), canvasSize: size)
            let selected = layouts.first { $0.id == model.selectedClipID }
            ZStack {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(moveGesture(layouts: layouts, canvasSize: size))
                    .simultaneousGesture(transformGesture(layouts: layouts))

                if snappedX { Rectangle().fill(DesignTokens.amber.opacity(0.85)).frame(width: 1, height: size.height) }
                if snappedY { Rectangle().fill(DesignTokens.amber.opacity(0.85)).frame(width: size.width, height: 1) }

                if let selected, let clip = model.selectedClip { selectionOverlay(selected, clip: clip, canvasSize: size) }
            }
            .coordinateSpace(name: "previewCanvasSpace")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("previewCanvas")
        }
    }

    @ViewBuilder
    private func selectionOverlay(_ layout: PreviewElementLayout, clip: Clip, canvasSize: CGSize) -> some View {
        let displayedSize = CGSize(
            width: min(max(44, layout.size.width), max(44, canvasSize.width - 12)),
            height: min(max(52, layout.size.height), max(52, canvasSize.height - 12))
        )
        let topLeft = rotatedCorner(center: layout.center, size: displayedSize, rotation: layout.rotation, x: -0.5, y: -0.5)
        let topRight = rotatedCorner(center: layout.center, size: displayedSize, rotation: layout.rotation, x: 0.5, y: -0.5)
        let bottomLeft = rotatedCorner(center: layout.center, size: displayedSize, rotation: layout.rotation, x: -0.5, y: 0.5)
        let bottomRight = rotatedCorner(center: layout.center, size: displayedSize, rotation: layout.rotation, x: 0.5, y: 0.5)

        RoundedRectangle(cornerRadius: 3)
            .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: displayedSize.width, height: displayedSize.height)
            .rotationEffect(.degrees(layout.rotation))
            .position(layout.center)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.displayName(for: clip))
            .accessibilityValue(L("Élément sélectionné"))
            .accessibilityIdentifier("previewSelectionFrame")

        previewHandle(symbol: "trash.fill", label: L("Supprimer"), position: PreviewInteractionGeometry.containedHandlePosition(topLeft, canvasSize: canvasSize), destructive: true) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.deleteClip(clip.id)
        }
        previewHandle(symbol: "pencil", label: L("Modifier"), position: PreviewInteractionGeometry.containedHandlePosition(topRight, canvasSize: canvasSize)) {
            UISelectionFeedbackGenerator().selectionChanged()
            edit(clip)
        }
        previewGestureHandle(symbol: "arrow.clockwise", label: L("Faire pivoter"), position: PreviewInteractionGeometry.containedHandlePosition(bottomLeft, canvasSize: canvasSize), gesture: rotationHandleGesture(center: layout.center))
        previewGestureHandle(symbol: "arrow.up.left.and.arrow.down.right", label: L("Redimensionner"), position: PreviewInteractionGeometry.containedHandlePosition(bottomRight, canvasSize: canvasSize), gesture: scaleHandleGesture(center: layout.center, canvasSize: canvasSize, isShape: clip.kind == .shape))
            .accessibilityIdentifier("previewResizeHandle")
    }

    private func previewHandle(symbol: String, label: String, position: CGPoint, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(destructive ? Color.red.opacity(0.92) : DesignTokens.ink.opacity(0.94), in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.72), lineWidth: 1) }
                .frame(width: PreviewInteractionGeometry.handleTouchSize, height: PreviewInteractionGeometry.handleTouchSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(position)
        .accessibilityLabel(label)
    }

    private func previewGestureHandle<G: Gesture>(symbol: String, label: String, position: CGPoint, gesture: G) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 24, height: 24)
            .background(DesignTokens.ink.opacity(0.94), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.72), lineWidth: 1) }
            .frame(width: PreviewInteractionGeometry.handleTouchSize, height: PreviewInteractionGeometry.handleTouchSize)
            .contentShape(Circle())
            .position(position)
            .gesture(gesture)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func scaleHandleGesture(center: CGPoint, canvasSize: CGSize, isShape: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("previewCanvasSpace"))
            .onChanged { value in
                let distance = max(1, hypot(value.location.x - center.x, value.location.y - center.y))
                if handleOrigin == nil {
                    guard model.beginGesture(L("Redimensionner")) else { return }
                    handleOrigin = model.presentation
                    handleStartValue = max(1, hypot(value.startLocation.x - center.x, value.startLocation.y - center.y))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                guard let origin = handleOrigin, let start = handleStartValue else { return }
                if isShape {
                    let resized = PreviewInteractionGeometry.resizedShapePresentation(from: origin, translation: value.translation, canvasSize: canvasSize)
                    model.changePresentation { $0.scale = resized.scale; $0.maskWidth = resized.maskWidth; $0.maskHeight = resized.maskHeight }
                } else {
                    model.changePresentation { $0.scale = min(4, max(0.1, origin.scale * distance / start)) }
                }
            }
            .onEnded { _ in endHandleGesture() }
    }

    private func rotationHandleGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("previewCanvasSpace"))
            .onChanged { value in
                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                if handleOrigin == nil {
                    guard model.beginGesture(L("Faire pivoter")) else { return }
                    handleOrigin = model.presentation
                    handleStartValue = atan2(value.startLocation.y - center.y, value.startLocation.x - center.x)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                guard let origin = handleOrigin, let start = handleStartValue else { return }
                model.changePresentation { $0.rotation = origin.rotation + Double((angle - start) * 180 / .pi) }
            }
            .onEnded { _ in endHandleGesture() }
    }

    private func endHandleGesture() {
        if handleOrigin != nil {
            model.endGesture()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        handleOrigin = nil
        handleStartValue = nil
    }

    private func moveGesture(layouts: [PreviewElementLayout], canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard transformOrigin == nil, handleOrigin == nil else { return }
                if !pointerTracking {
                    pointerTracking = true
                    pointerCandidateID = PreviewInteractionGeometry.hitTest(value.startLocation, layouts: layouts)
                    if let id = pointerCandidateID {
                        if model.selectedClipID != id { UISelectionFeedbackGenerator().selectionChanged() }
                        model.selectClipFromPreview(id)
                    } else { model.clearSelection() }
                }
                guard let id = pointerCandidateID, model.selectedClipID == id, hypot(value.translation.width, value.translation.height) >= 4 else { return }
                if dragOrigin == nil {
                    guard model.beginGesture(L("Déplacer")) else { return }
                    dragOrigin = model.presentation
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                guard let origin = dragOrigin else { return }
                let moved = PreviewInteractionGeometry.movedPresentation(from: origin, translation: value.translation, canvasSize: canvasSize)
                if moved.snappedX != snappedX || moved.snappedY != snappedY, moved.snappedX || moved.snappedY {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                snappedX = moved.snappedX
                snappedY = moved.snappedY
                model.movePreviewElement(toX: moved.presentation.x, y: moved.presentation.y)
            }
            .onEnded { _ in
                if dragOrigin != nil {
                    model.endGesture()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                resetPointerState()
            }
    }

    private func transformGesture(layouts: [PreviewElementLayout]) -> some Gesture {
        SimultaneousGesture(MagnificationGesture(), RotationGesture())
            .onChanged { value in
                guard let id = model.selectedClipID, layouts.contains(where: { $0.id == id }) else { return }
                if transformOrigin == nil {
                    if dragOrigin != nil { model.endGesture(); dragOrigin = nil }
                    guard model.beginGesture(L("Transformer")) else { return }
                    transformOrigin = model.presentation
                    pointerTracking = false
                    pointerCandidateID = nil
                }
                guard var presentation = transformOrigin else { return }
                presentation.scale = min(4, max(0.1, presentation.scale * (value.first ?? 1)))
                presentation.rotation += value.second?.degrees ?? 0
                model.changePresentation {
                    $0.scale = presentation.scale
                    $0.rotation = presentation.rotation
                }
            }
            .onEnded { _ in
                if transformOrigin != nil { model.endGesture() }
                transformOrigin = nil
                resetPointerState()
            }
    }

    private func resetPointerState() {
        pointerTracking = false
        pointerCandidateID = nil
        dragOrigin = nil
        snappedX = false
        snappedY = false
    }

    private func rotatedCorner(center: CGPoint, size: CGSize, rotation: Double, x: CGFloat, y: CGFloat) -> CGPoint {
        let radians = CGFloat(rotation * .pi / 180)
        let dx = size.width * x
        let dy = size.height * y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians), y: center.y + dx * sin(radians) + dy * cos(radians))
    }
}
