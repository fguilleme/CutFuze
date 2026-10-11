import Foundation

enum FadeAnimationPreset: String, CaseIterable, Sendable { case entrance, exit, combination }
enum MotionAnimationZone: String, CaseIterable, Sendable { case entrance, exit, loop }
enum MotionAnimationPreset: String, CaseIterable, Sendable { case fade, zoom, slide, float, pulse, spin, shake }

/// Keyframes remain common to every format. Values entered while viewing a variant are
/// converted back to the common presentation domain before they enter the document.
enum AnimationEditing {
    static func presets(for zone: MotionAnimationZone) -> [MotionAnimationPreset] {
        switch zone {
        case .entrance, .exit: [.fade, .zoom, .slide]
        case .loop: [.float, .pulse, .spin, .shake]
        }
    }

    static func applyPreset(_ preset: MotionAnimationPreset, zone: MotionAnimationZone, clipID: UUID, in document: inout ProjectDocument) throws {
        guard let source = document.clip(clipID) else { throw DocumentError.missing("Clip") }
        guard presets(for: zone).contains(preset) else { throw DocumentError.invalid("Animation incompatible") }
        let start = source.animationOffset
        let end = start + source.duration
        let edgeDuration = MediaTime(seconds: min(0.6, max(0.12, source.duration.seconds / 3)))
        let edgeStart = zone == .exit ? end - edgeDuration : start
        let edgeEnd = zone == .exit ? end : start + edgeDuration
        let property: KeyframeProperty
        switch preset {
        case .fade: property = .opacity
        case .zoom, .pulse: property = .scale
        case .slide, .shake: property = .x
        case .float: property = .y
        case .spin: property = .rotation
        }
        try DocumentEditor.updateClip(clipID, in: &document) { clip in
            if zone == .loop {
                clip.keyframes.removeAll { $0.property == property && $0.time >= start && $0.time <= end }
            } else {
                clip.keyframes.removeAll { $0.property == property && $0.time >= edgeStart && $0.time <= edgeEnd }
            }
            let base = value(property, in: clip.presentation)
            switch (zone, preset) {
            case (.entrance, .fade):
                upsertLocal(property: property, at: start, value: 0, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: edgeEnd, value: base, easing: .easeOut, clip: &clip)
            case (.exit, .fade):
                upsertLocal(property: property, at: edgeStart, value: base, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: end, value: 0, easing: .easeIn, clip: &clip)
            case (.entrance, .zoom):
                upsertLocal(property: property, at: start, value: base * 0.72, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: edgeEnd, value: base, easing: .easeOut, clip: &clip)
            case (.exit, .zoom):
                upsertLocal(property: property, at: edgeStart, value: base, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: end, value: base * 0.72, easing: .easeIn, clip: &clip)
            case (.entrance, .slide):
                upsertLocal(property: property, at: start, value: base - 0.28, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: edgeEnd, value: base, easing: .easeOut, clip: &clip)
            case (.exit, .slide):
                upsertLocal(property: property, at: edgeStart, value: base, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: end, value: base + 0.28, easing: .easeIn, clip: &clip)
            case (.loop, .float):
                addLoop(property: property, base: base, delta: 0.045, period: 1.6, start: start, end: end, clip: &clip)
            case (.loop, .pulse):
                addLoop(property: property, base: base, delta: base * 0.09, period: 1.2, start: start, end: end, clip: &clip)
            case (.loop, .spin):
                upsertLocal(property: property, at: start, value: base, easing: .linear, clip: &clip)
                upsertLocal(property: property, at: end, value: base + 360, easing: .linear, clip: &clip)
            case (.loop, .shake):
                addLoop(property: property, base: base, delta: 0.018, period: 0.24, start: start, end: end, clip: &clip)
            default: break
            }
        }
    }

    private static func addLoop(property: KeyframeProperty, base: Double, delta: Double, period: Double, start: MediaTime, end: MediaTime, clip: inout Clip) {
        let duration = max(0, (end - start).seconds)
        let step = max(0.08, period / 2)
        let count = min(32, Int(ceil(duration / step)))
        for index in 0...count {
            let time = min(end, start + MediaTime(seconds: min(duration, Double(index) * step)))
            let value = index == count ? base : base + (index.isMultiple(of: 2) ? -delta : delta)
            upsertLocal(property: property, at: time, value: value, easing: .easeInOut, clip: &clip)
        }
    }
    static func value(_ property: KeyframeProperty, in presentation: Presentation) -> Double {
        switch property {
        case .x: presentation.x
        case .y: presentation.y
        case .scale: presentation.scale
        case .rotation: presentation.rotation
        case .opacity: presentation.opacity
        case .volume: 1 // Volume belongs to Clip, not to format-specific Presentation.
        case .maskWidth: presentation.maskWidth
        case .maskHeight: presentation.maskHeight
        case .maskX: presentation.maskX
        case .maskY: presentation.maskY
        case .maskRotation: presentation.maskRotation
        case .maskFeather: presentation.maskFeather
        }
    }
    static func commonValue(displayed: Double, property: KeyframeProperty, common: Presentation, variant: Presentation) throws -> Double {
        guard displayed.isFinite else { throw DocumentError.invalid("Valeur de point non finie") }
        switch property {
        case .volume:
            guard (0...8).contains(displayed) else { throw DocumentError.invalid("Volume") }
            return displayed
        case .x: return common.x + displayed - variant.x
        case .y: return common.y + displayed - variant.y
        case .rotation: return common.rotation + displayed - variant.rotation
        case .scale:
            guard displayed > 0, variant.scale > 0 else { throw DocumentError.invalid("Échelle positive requise") }
            return displayed * max(0.000001, common.scale) / variant.scale
        case .opacity:
            guard displayed >= 0, variant.opacity > 0 else { throw DocumentError.invalid("Rétablissez une opacité de format supérieure à zéro avant de créer ce point") }
            return common.opacity > 0.000001 ? displayed * common.opacity / variant.opacity : displayed / variant.opacity
        case .maskWidth, .maskHeight:
            let baseline = value(property, in: variant)
            guard displayed > 0, baseline > 0 else { throw DocumentError.invalid("Dimensions du masque") }
            return displayed * value(property, in: common) / baseline
        case .maskX, .maskY, .maskRotation, .maskFeather:
            return value(property, in: common) + displayed - value(property, in: variant)
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
        let properties = KeyframeProperty.visual + (visible.mask != .none ? KeyframeProperty.mask : [])
        for property in properties {
            // A fully transparent variant cannot define a multiplicative opacity point.
            if property == .opacity && rendered.presentation.opacity == 0 { continue }
            let easing = rendered.clip.keyframes.first { $0.property == property && $0.time == localTime }?.easing ?? .linear
            try upsert(clipID: clipID, property: property, at: globalTime, displayedValue: value(property, in: visible), variantID: variantID, easing: easing, in: &document)
        }
    }
    /// Relocates one point without changing its identity or silently overwriting another.
    static func move(keyframeID: UUID, clipID: UUID, to globalTime: MediaTime, displayedValue: Double, variantID: UUID?, easing: KeyframeEasing, in document: inout ProjectDocument) throws {
        let plan = RenderPlan.compile(document: document, variantID: variantID)
        guard let rendered = plan.clips.first(where: { $0.id == clipID }),
              let key = rendered.clip.keyframes.first(where: { $0.id == keyframeID }),
              globalTime >= rendered.globalStart, globalTime <= rendered.end else { throw DocumentError.invalid("Point en dehors du clip") }
        let time = globalTime - rendered.globalStart + rendered.clip.animationOffset
        guard !rendered.clip.keyframes.contains(where: { $0.id != keyframeID && $0.property == key.property && $0.time == time }) else {
            throw DocumentError.invalid("Un point existe déjà à cet instant")
        }
        let value = try commonValue(displayed: displayedValue, property: key.property, common: rendered.clip.presentation, variant: variantID == nil ? rendered.clip.presentation : rendered.presentation)
        try DocumentEditor.updateClip(clipID, in: &document) { clip in
            if let index = clip.keyframes.firstIndex(where: { $0.id == keyframeID }) {
                clip.keyframes[index].time = time
                clip.keyframes[index].value = value
                clip.keyframes[index].easing = easing
            }
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
