import Foundation

enum FadeAnimationPreset: String, CaseIterable, Sendable { case entrance, exit, combination }

/// Keyframes remain common to every format. Values entered while viewing a variant are
/// converted back to the common presentation domain before they enter the document.
enum AnimationEditing {
    static func value(_ property: KeyframeProperty, in presentation: Presentation) -> Double {
        switch property {
        case .x: presentation.x
        case .y: presentation.y
        case .scale: presentation.scale
        case .rotation: presentation.rotation
        case .opacity: presentation.opacity
        }
    }
    static func commonValue(displayed: Double, property: KeyframeProperty, common: Presentation, variant: Presentation) throws -> Double {
        guard displayed.isFinite else { throw DocumentError.invalid("Valeur de point non finie") }
        switch property {
        case .x: return common.x + displayed - variant.x
        case .y: return common.y + displayed - variant.y
        case .rotation: return common.rotation + displayed - variant.rotation
        case .scale:
            guard displayed > 0, variant.scale > 0 else { throw DocumentError.invalid("Échelle positive requise") }
            return displayed * max(0.000001, common.scale) / variant.scale
        case .opacity:
            guard displayed >= 0, variant.opacity > 0 else { throw DocumentError.invalid("Rétablissez une opacité de format supérieure à zéro avant de créer ce point") }
            return common.opacity > 0.000001 ? displayed * common.opacity / variant.opacity : displayed / variant.opacity
        }
    }
    static func upsert(clipID: UUID, property: KeyframeProperty, at globalTime: MediaTime, displayedValue: Double, variantID: UUID?, easing: KeyframeEasing, in document: inout ProjectDocument) throws {
        let plan = RenderPlan.compile(document: document, variantID: variantID)
        guard let rendered = plan.clips.first(where: { $0.id == clipID }), globalTime >= rendered.globalStart, globalTime <= rendered.end else { throw DocumentError.invalid("Point en dehors du clip") }
        let common = rendered.clip.presentation
        let baseline = variantID == nil ? common : rendered.presentation
        let value = try commonValue(displayed: displayedValue, property: property, common: common, variant: baseline)
        let time = globalTime - rendered.globalStart + rendered.clip.animationOffset
        try DocumentEditor.updateClip(clipID, in: &document) { clip in upsertLocal(property: property, at: time, value: value, easing: easing, clip: &clip) }
    }
    static func upsertCurrentPose(clipID: UUID, at globalTime: MediaTime, variantID: UUID?, in document: inout ProjectDocument) throws {
        let plan = RenderPlan.compile(document: document, variantID: variantID)
        guard var rendered = plan.clips.first(where: { $0.id == clipID }) else { throw DocumentError.missing("Clip") }
        if variantID == nil { rendered.presentation = rendered.clip.presentation }
        let visible = rendered.evaluatedPresentation(at: globalTime)
        let localTime = globalTime - rendered.globalStart + rendered.clip.animationOffset
        for property in KeyframeProperty.allCases {
            // A fully transparent variant cannot define a multiplicative opacity point.
            if property == .opacity && rendered.presentation.opacity == 0 { continue }
            let easing = rendered.clip.keyframes.first { $0.property == property && $0.time == localTime }?.easing ?? .linear
            try upsert(clipID: clipID, property: property, at: globalTime, displayedValue: value(property, in: visible), variantID: variantID, easing: easing, in: &document)
        }
    }
    static func neighbor(in clip: RenderClip, from globalTime: MediaTime, forward: Bool) -> MediaTime? {
        let times = Set(clip.clip.keyframes.map { clip.globalStart + $0.time - clip.clip.animationOffset }).filter { $0 >= clip.globalStart && $0 <= clip.end }.sorted()
        return forward ? times.first { $0 > globalTime } : times.last { $0 < globalTime }
    }
    static func setEasing(_ easing: KeyframeEasing, keyframeID: UUID, clipID: UUID, in document: inout ProjectDocument) throws {
        guard document.clip(clipID)?.keyframes.contains(where: { $0.id == keyframeID }) == true else { throw DocumentError.missing("Point d’animation") }
        try DocumentEditor.updateClip(clipID, in: &document) { clip in if let index = clip.keyframes.firstIndex(where: { $0.id == keyframeID }) { clip.keyframes[index].easing = easing } }
    }
    static func applyFade(_ preset: FadeAnimationPreset, duration: MediaTime, clipID: UUID, in document: inout ProjectDocument) throws {
        guard let clip = document.clip(clipID), duration > .zero, duration <= clip.duration, preset != .combination || duration <= clip.duration / 2 else { throw DocumentError.invalid("Durée de fondu incompatible avec ce clip") }
        let start = clip.animationOffset, end = start + clip.duration
        let opacity = clip.presentation.opacity > 0.000001 ? clip.presentation.opacity : 1
        try DocumentEditor.updateClip(clipID, in: &document) { target in
            if preset == .entrance || preset == .combination {
                upsertLocal(property: .opacity, at: start, value: 0, easing: .linear, clip: &target)
                upsertLocal(property: .opacity, at: start + duration, value: opacity, easing: .easeOut, clip: &target)
            }
            if preset == .exit || preset == .combination {
                upsertLocal(property: .opacity, at: end - duration, value: opacity, easing: .linear, clip: &target)
                upsertLocal(property: .opacity, at: end, value: 0, easing: .easeIn, clip: &target)
            }
        }
    }
    private static func upsertLocal(property: KeyframeProperty, at time: MediaTime, value: Double, easing: KeyframeEasing, clip: inout Clip) {
        let existing = clip.keyframes.first { $0.property == property && $0.time == time }
        clip.keyframes.removeAll { $0.property == property && $0.time == time }
        clip.keyframes.append(.init(id: existing?.id ?? UUID(), time: time, property: property, value: value, easing: easing))
    }
}
