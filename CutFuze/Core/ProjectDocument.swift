import Foundation

/// Integer ticks at 60 kHz. All composition intervals are half-open [start, end).
struct MediaTime: Codable, Hashable, Comparable, Sendable {
    var value: Int64
    var timescale: Int32
    init(value: Int64, timescale: Int32 = 60_000) { self.value = value; self.timescale = timescale }
    init(seconds: Double) { value = seconds.isFinite ? Int64((max(-1e10, min(1e10, seconds)) * 60_000).rounded()) : 0; timescale = 60_000 }
    var seconds: Double { Double(value) / Double(timescale) }
    static let zero = MediaTime(value: 0)
    private var normalized: (Int64, Int64) {
        guard timescale > 0 else { return (value, Int64(timescale)) }
        var a = value.magnitude, b = UInt64(timescale)
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        let divisor = Int64(max(1, a))
        return (value / divisor, Int64(timescale) / divisor)
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.normalized == rhs.normalized }
    func hash(into hasher: inout Hasher) { hasher.combine(normalized.0); hasher.combine(normalized.1) }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.seconds < rhs.seconds }
    static func + (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, subtract: false) }
    static func - (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, subtract: true) }
    private static func combine(_ lhs: Self, _ rhs: Self, subtract: Bool) -> Self {
        guard lhs.timescale > 0, rhs.timescale > 0 else { return .init(value: Int64.max) }
        var a = Int64(lhs.timescale), b = Int64(rhs.timescale)
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        let common = Int64(lhs.timescale) / a * Int64(rhs.timescale)
        if common <= Int64(Int32.max) {
            let left = lhs.value.multipliedReportingOverflow(by: common / Int64(lhs.timescale))
            let right = rhs.value.multipliedReportingOverflow(by: common / Int64(rhs.timescale))
            if !left.overflow && !right.overflow {
                let result = subtract ? left.partialValue.subtractingReportingOverflow(right.partialValue) : left.partialValue.addingReportingOverflow(right.partialValue)
                if !result.overflow { return .init(value: result.partialValue, timescale: Int32(common)) }
            }
        }
        return .init(seconds: subtract ? lhs.seconds - rhs.seconds : lhs.seconds + rhs.seconds)
    }
    static func * (lhs: Self, rhs: Double) -> Self { .init(seconds: lhs.seconds * rhs) }
    static func / (lhs: Self, rhs: Double) -> Self { .init(seconds: lhs.seconds / rhs) }
}

enum ClipKind: String, Codable, CaseIterable, Sendable { case video, image, audio, text, shape }
enum BlendMode: String, Codable, CaseIterable, Sendable { case normal, multiply, screen, overlay, lighten, darken }
enum MaskKind: String, Codable, CaseIterable, Sendable { case none, ellipse, rectangle, roundedRectangle, linear, band }
enum TransitionKind: String, Codable, CaseIterable, Sendable { case none, dissolve, black, white, slide, wipe, zoom, blur, glitch }
enum EffectKind: String, Codable, CaseIterable, Sendable {
    case exposure, brightness, contrast, saturation, temperature, tint, highlights, shadows, sharpness
    case vignette, grain, fade, blur, glow, rgbSplit, pixelate, shake, retro
    case skinSmooth, skinGlow
    case bulge, pinch, twirl, kaleidoscope
    case comic, crystallize
}
enum KeyframeProperty: String, Codable, CaseIterable, Sendable { case x, y, scale, rotation, opacity }
enum KeyframeEasing: String, Codable, CaseIterable, Sendable { case linear, easeIn, easeOut, easeInOut }

struct Presentation: Codable, Equatable, Sendable {
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 1
    var rotation: Double = 0
    var opacity: Double = 1
    var fill: Bool = true
    var mirror: Bool = false
    var textSize: Double = 0.065
    var color: String = "#FFFFFF"
    var background: String = "#000000"
    var mask: MaskKind = .none
    var blend: BlendMode = .normal
    var maskX: Double = 0.5
    var maskY: Double = 0.5
    var maskWidth: Double = 1
    var maskHeight: Double = 1
    var maskRotation: Double = 0
    var maskFeather: Double = 0
    var maskInverted: Bool = false
    var textAlignment: String = "center"
    var textFont: String = "system"
    var textBold: Bool = true
    var textOutline: Double = 0
    var textShadow: Double = 0
    var textBackgroundOpacity: Double = 0
    var textBackgroundShape: TextBackgroundShape = .rounded
    /// Additional tracking and line spacing in em, independent of output resolution.
    var textLetterSpacing: Double = 0
    var textLineSpacing: Double = 0
    var chromaKeyColor: String? = nil
    var chromaKeyTolerance: Double = 0.2
    var chromaKeySoftness: Double = 0.1
    var removePersonBackground: Bool = false
}

enum TextBackgroundShape: String, Codable, CaseIterable, Sendable {
    case rounded, rectangle, capsule, cloud, star, heart

    var widthLimit: Double {
        switch self { case .star: 0.4; case .heart: 0.42; case .cloud: 0.7; default: 0.86 }
    }
    var expansion: Double {
        switch self { case .star, .heart: 2.2; case .cloud: 1.3; default: 1 }
    }
}

struct Transition: Codable, Equatable, Sendable {
    var kind: TransitionKind = .none
    var duration: MediaTime = .init(seconds: 0.5)
}

struct EffectInstance: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var kind: EffectKind
    var amount: Double = 0
    var enabled: Bool = true
    /// Half-open interval in animation time (clip local time + animationOffset).
    var start: MediaTime? = nil
    var duration: MediaTime? = nil
    var amountKeyframes: [EffectAmountKeyframe]? = nil
}

struct Keyframe: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var time: MediaTime
    var property: KeyframeProperty
    var value: Double
    var easing: KeyframeEasing = .linear
}

struct SpeedPoint: Codable, Equatable, Sendable {
    /// Absolute source seconds, positive speed, linearly interpolated in source domain.
    var sourceTime: MediaTime
    var speed: Double
}

struct MediaAsset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var relativePath: String
    var kind: ClipKind
    var name: String
    var duration: MediaTime = .zero
    var width: Int = 0
    var height: Int = 0
    var sha256: String = ""
    var hasAudio: Bool = false
    var nominalFrameRate: Double = 0
}

struct Clip: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var assetID: UUID? = nil
    var kind: ClipKind
    /// Scene-local for scene children; absolute composition time for global clips.
    var start: MediaTime = .zero
    var duration: MediaTime = .init(seconds: 5)
    var sourceStart: MediaTime = .zero
    var sourceDuration: MediaTime = .init(seconds: 5)
    var speed: Double = 1
    var reversed: Bool = false
    var text: String = ""
    var presentation: Presentation = .init()
    var effects: [EffectInstance] = []
    var keyframes: [Keyframe] = []
    var volume: Double = 1
    var fadeIn: MediaTime = .zero
    var fadeOut: MediaTime = .zero
    /// Preserve animation phase and its original envelope when splitting an instance.
    var animationOffset: MediaTime = .zero
    var animationDuration: MediaTime? = nil
    var speedPoints: [SpeedPoint] = []
    var layer: Int = 0
    var isCaption: Bool = false
    var muted: Bool = false
    var captionSourceAssetID: UUID? = nil
    var captionSourceClipID: UUID? = nil
    var captionSourceStart: MediaTime? = nil
    var captionSourceEnd: MediaTime? = nil
    var captionAnalyzedRevision: Int? = nil
    /// Splits retain this seed so deterministic grain/shake do not restart at the cut.
    var effectSeed: UUID? = nil
    var end: MediaTime { start + duration }
}

struct Scene: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = "Scène"
    var narration: String = ""
    var duration: MediaTime = .init(seconds: 5)
    var clips: [Clip] = []
    /// Outgoing overlap with the next scene; .none for a simple cut.
    var transition: Transition = .init()
}

struct OutputVariant: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var widthRatio: Double
    var heightRatio: Double
    /// Presentation only. All temporal and textual edits remain common.
    var overrides: [String: Presentation] = [:]
    var safeMargin: Double = 0.05
    var canvas: CanvasSettings? = nil
    var ratio: Double { widthRatio / heightRatio }
    static var standard: [Self] { [.init(name: "Vertical", widthRatio: 9, heightRatio: 16), .init(name: "Carré", widthRatio: 1, heightRatio: 1), .init(name: "Paysage", widthRatio: 16, heightRatio: 9)] }
}

struct ProjectDocument: Codable, Identifiable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    var id: UUID = UUID()
    var schemaVersion: Int = currentSchemaVersion
    var revision: Int = 0
    var title: String = "Nouveau projet"
    var collection: String = ""
    var modifiedAt: Date = Date()
    var assets: [MediaAsset] = []
    var scenes: [Scene] = []
    var globalClips: [Clip] = []
    var beatMarkers: [BeatMarker]? = nil
    var variants: [OutputVariant] = OutputVariant.standard
    var allClips: [Clip] { scenes.flatMap(\.clips) + globalClips }
    var duration: MediaTime { RenderPlan.compile(document: self, variantID: variants.first?.id).duration }
    func asset(_ id: UUID?) -> MediaAsset? { assets.first { $0.id == id } }
    func clip(_ id: UUID?) -> Clip? { allClips.first { $0.id == id } }
}

struct RenderClip: Identifiable, Equatable, Sendable {
    var clip: Clip
    var globalStart: MediaTime
    var duration: MediaTime
    var presentation: Presentation
    var sceneID: UUID?
    var id: UUID { clip.id }
    var end: MediaTime { globalStart + duration }
    func isActive(at time: MediaTime) -> Bool { globalStart <= time && time < end }
}

struct SceneSpan: Identifiable, Equatable, Sendable {
    var id: UUID
    var start: MediaTime
    var duration: MediaTime
    var transition: Transition
    var end: MediaTime { start + duration }
}

struct RenderPlan: Equatable, Sendable {
    var projectID: UUID
    var revision: Int
    var variant: OutputVariant
    var duration: MediaTime
    var clips: [RenderClip]
    var scenes: [SceneSpan]
    var assets: [MediaAsset]
    static func compile(document: ProjectDocument, variantID: UUID?) -> Self {
        let variant = document.variants.first { $0.id == variantID } ?? document.variants.first ?? .init(name: "Vertical", widthRatio: 9, heightRatio: 16)
        var cursor = MediaTime.zero
        var clips: [RenderClip] = []
        var spans: [SceneSpan] = []
        for (index, scene) in document.scenes.enumerated() {
            var transition = scene.transition
            if transition.kind == .none || index + 1 == document.scenes.count { transition.duration = .zero }
            else { transition.duration = min(max(.zero, transition.duration), min(scene.duration / 2, document.scenes[index + 1].duration / 2)) }
            spans.append(.init(id: scene.id, start: cursor, duration: scene.duration, transition: transition))
            clips += scene.clips.map { .init(clip: $0, globalStart: cursor + $0.start, duration: $0.duration, presentation: variant.overrides[$0.id.uuidString] ?? $0.presentation, sceneID: scene.id) }
            cursor = cursor + scene.duration - transition.duration
        }
        clips += document.globalClips.map { .init(clip: $0, globalStart: $0.start, duration: $0.duration, presentation: variant.overrides[$0.id.uuidString] ?? $0.presentation, sceneID: nil) }
        clips = clips.enumerated().sorted { $0.element.clip.layer == $1.element.clip.layer ? $0.offset < $1.offset : $0.element.clip.layer < $1.element.clip.layer }.map(\.element)
        return .init(projectID: document.id, revision: document.revision, variant: variant, duration: max(cursor, clips.map(\.end).max() ?? .zero), clips: clips, scenes: spans, assets: document.assets)
    }
}

extension Presentation {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? x
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? y
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? rotation
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        fill = try container.decodeIfPresent(Bool.self, forKey: .fill) ?? fill
        mirror = try container.decodeIfPresent(Bool.self, forKey: .mirror) ?? mirror
        textSize = try container.decodeIfPresent(Double.self, forKey: .textSize) ?? textSize
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? color
        background = try container.decodeIfPresent(String.self, forKey: .background) ?? background
        mask = try container.decodeIfPresent(MaskKind.self, forKey: .mask) ?? mask
        blend = try container.decodeIfPresent(BlendMode.self, forKey: .blend) ?? blend
        maskX = try container.decodeIfPresent(Double.self, forKey: .maskX) ?? maskX
        maskY = try container.decodeIfPresent(Double.self, forKey: .maskY) ?? maskY
        maskWidth = try container.decodeIfPresent(Double.self, forKey: .maskWidth) ?? maskWidth
        maskHeight = try container.decodeIfPresent(Double.self, forKey: .maskHeight) ?? maskHeight
        maskRotation = try container.decodeIfPresent(Double.self, forKey: .maskRotation) ?? maskRotation
        maskFeather = try container.decodeIfPresent(Double.self, forKey: .maskFeather) ?? maskFeather
        maskInverted = try container.decodeIfPresent(Bool.self, forKey: .maskInverted) ?? maskInverted
        textAlignment = try container.decodeIfPresent(String.self, forKey: .textAlignment) ?? textAlignment
        textFont = try container.decodeIfPresent(String.self, forKey: .textFont) ?? textFont
        textBold = try container.decodeIfPresent(Bool.self, forKey: .textBold) ?? textBold
        textOutline = try container.decodeIfPresent(Double.self, forKey: .textOutline) ?? textOutline
        textShadow = try container.decodeIfPresent(Double.self, forKey: .textShadow) ?? textShadow
        textBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .textBackgroundOpacity) ?? textBackgroundOpacity
        textBackgroundShape = try container.decodeIfPresent(TextBackgroundShape.self, forKey: .textBackgroundShape) ?? textBackgroundShape
        textLetterSpacing = try container.decodeIfPresent(Double.self, forKey: .textLetterSpacing) ?? textLetterSpacing
        textLineSpacing = try container.decodeIfPresent(Double.self, forKey: .textLineSpacing) ?? textLineSpacing
        chromaKeyColor = try container.decodeIfPresent(String.self, forKey: .chromaKeyColor)
        chromaKeyTolerance = try container.decodeIfPresent(Double.self, forKey: .chromaKeyTolerance) ?? chromaKeyTolerance
        chromaKeySoftness = try container.decodeIfPresent(Double.self, forKey: .chromaKeySoftness) ?? chromaKeySoftness
        removePersonBackground = try container.decodeIfPresent(Bool.self, forKey: .removePersonBackground) ?? removePersonBackground
    }
}
