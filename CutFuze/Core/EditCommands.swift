import Foundation

enum ClipTrimEdge {
    case leading
    case trailing
}

enum DocumentError: LocalizedError, Equatable {
    case invalid(String), missing(String), unsupportedVersion(Int), corrupt(String), cancelled
    var errorDescription: String? {
        switch self {
        case .invalid(let s): return L("Projet invalide") + " : " + L(s)
        case .missing(let s): return L("Élément introuvable") + " : " + L(s)
        case .unsupportedVersion(let v): return String(format: L("Version de projet %d non prise en charge."), v)
        case .corrupt(let s): return L("Fichier endommagé") + " : " + L(s)
        case .cancelled: return L("Opération annulée.")
        }
    }
}

/// One immutable before/after pair per user intention, including continuous gestures.
final class EditHistory {
    private struct Entry { var name: String; var before: ProjectDocument; var after: ProjectDocument }
    private(set) var document: ProjectDocument
    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    private var transaction: (name: String, before: ProjectDocument)?
    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var undoName: String? { undoEntries.last?.name }
    var redoName: String? { redoEntries.last?.name }
    init(document: ProjectDocument) { self.document = document }
    func perform(name: String, _ mutation: (inout ProjectDocument) throws -> Void) throws {
        guard transaction == nil else { throw DocumentError.invalid("Transaction déjà ouverte") }
        let before = document
        var after = before
        try mutation(&after)
        CaptionBindingUpdater.refresh(&after)
        try after.validate()
        guard after != before else { return }
        after.revision = before.revision + 1; after.modifiedAt = Date()
        document = after
        undoEntries.append(.init(name: name, before: before, after: after))
        if undoEntries.count > 100 { undoEntries.removeFirst() }
        redoEntries.removeAll()
    }
    func beginTransaction(name: String) { if transaction == nil { transaction = (name, document) } }
    func updateTransaction(_ mutation: (inout ProjectDocument) throws -> Void) throws {
        guard transaction != nil else { throw DocumentError.invalid("Aucune transaction") }
        var candidate = document
        try mutation(&candidate)
        CaptionBindingUpdater.refresh(&candidate)
        try candidate.validate()
        document = candidate
    }
    func commitTransaction() throws {
        guard let pending = transaction else { return }
        let after = document
        document = pending.before; transaction = nil
        try perform(name: pending.name) { $0 = after }
    }
    func cancelTransaction() { if let pending = transaction { document = pending.before; transaction = nil } }
    func undo() {
        cancelTransaction()
        guard let entry = undoEntries.popLast() else { return }
        let revision = document.revision + 1
        document = entry.before; document.revision = revision; document.modifiedAt = Date()
        redoEntries.append(entry)
    }
    func redo() {
        cancelTransaction()
        guard let entry = redoEntries.popLast() else { return }
        let revision = document.revision + 1
        document = entry.after; document.revision = revision; document.modifiedAt = Date()
        undoEntries.append(entry)
    }
}

enum DocumentEditor {
    /// Constant-speed shortcuts use the visible source interval, never extend the
    /// source beyond its media, and replace any prior variable-speed curve.
    static func setConstantSpeed(_ speed: Double, clipID: UUID, in document: inout ProjectDocument) throws {
        guard speed.isFinite, (0.1...100).contains(speed), let original = document.clip(clipID),
              original.kind == .audio || original.kind == .video else { throw DocumentError.invalid("Vitesse") }
        var updated = original
        let availableOutput = TimeMapping.outputDuration(clip: original)
        if original.duration < availableOutput {
            let boundary = TimeMapping.sourceTime(for: original.duration, clip: original)
            if original.reversed {
                updated.sourceDuration = original.sourceStart + original.sourceDuration - boundary
                updated.sourceStart = boundary
            } else { updated.sourceDuration = boundary - original.sourceStart }
        }
        updated.speed = speed; updated.speedPoints = []
        updated.duration = max(.init(value: 1), TimeMapping.outputDuration(clip: updated))
        updated.fadeIn = min(updated.fadeIn, updated.duration)
        updated.fadeOut = min(updated.fadeOut, updated.duration)
        if let si = document.scenes.firstIndex(where: { $0.clips.contains { $0.id == clipID } }), updated.end > document.scenes[si].duration {
            if updated.kind == .audio {
                // A music/narration segment may grow across a scene boundary without
                // shifting the following pictures or reading nonexistent source audio.
                guard let start = RenderPlan.compile(document: document, variantID: nil).clips.first(where: { $0.id == clipID })?.globalStart else { throw DocumentError.missing("Clip") }
                document.scenes[si].clips.removeAll { $0.id == clipID }
                updated.start = start; document.globalClips.append(updated)
            } else {
                try updateClip(clipID, in: &document) { $0 = updated }
                document.scenes[si].duration = updated.end
            }
        } else { try updateClip(clipID, in: &document) { $0 = updated } }
        CaptionBindingUpdater.refresh(&document)
    }

    static func reorderScene(_ id: UUID, to index: Int, in document: inout ProjectDocument) throws {
        guard let from = document.scenes.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing("Scène") }
        let scene = document.scenes.remove(at: from)
        document.scenes.insert(scene, at: max(0, min(index, document.scenes.count)))
    }
    @discardableResult static func duplicateScene(_ id: UUID, in document: inout ProjectDocument) throws -> UUID {
        guard let index = document.scenes.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing("Scène") }
        var copy = document.scenes[index]; copy.id = UUID(); copy.title += " · copie"
        var copiedIDs: [UUID: UUID] = [:]
        for i in copy.clips.indices {
            let old = copy.clips[i].id; let new = UUID(); copy.clips[i].id = new
            copiedIDs[old] = new
            copy.clips[i].keyframes = copy.clips[i].keyframes.map { var key = $0; key.id = UUID(); return key }
            copy.clips[i].effects = copy.clips[i].effects.map { var effect = $0; effect.id = UUID(); return effect }
            copyOverrides(from: old, to: new, in: &document)
        }
        for i in copy.clips.indices { if let source = copy.clips[i].captionSourceClipID { copy.clips[i].captionSourceClipID = copiedIDs[source] ?? source } }
        document.scenes.insert(copy, at: index + 1)
        return copy.id
    }
    static func removeScene(_ id: UUID, in document: inout ProjectDocument) throws {
        guard let scene = document.scenes.first(where: { $0.id == id }) else { throw DocumentError.missing("Scène") }
        scene.clips.forEach { removeOverrides(for: $0.id, in: &document) }
        document.scenes.removeAll { $0.id == id }
    }
    @discardableResult static func splitScene(_ id: UUID, at time: MediaTime, in document: inout ProjectDocument) throws -> UUID {
        guard let index = document.scenes.firstIndex(where: { $0.id == id }) else { throw DocumentError.missing("Scène") }
        let original = document.scenes[index]
        guard time > .zero && time < original.duration else { throw DocumentError.invalid("Coupe hors de la scène") }
        // Splitting inside a transition changes its incoming/outgoing domain. Reject explicitly.
        let plan = RenderPlan.compile(document: document, variantID: nil)
        let incoming = index > 0 ? plan.scenes[index - 1].transition.duration : .zero
        let outgoing = plan.scenes[index].transition.duration
        guard time >= incoming * 2 && time <= original.duration - outgoing * 2 else { throw DocumentError.invalid("Coupe trop proche d’un chevauchement de transition") }
        var left = original, right = original
        var splitSources: [UUID: UUID] = [:]
        left.duration = time; left.transition = .init(kind: .none, duration: .zero); left.clips = []
        right.id = UUID(); right.title += " · suite"; right.duration = original.duration - time; right.clips = []
        for clip in original.clips {
            if clip.isCaption, let boundID = clip.captionSourceClipID, original.clips.contains(where: { $0.id == boundID && $0.start < time && $0.end > time }) { left.clips.append(clip); continue }
            if clip.end <= time { left.clips.append(clip) }
            else if clip.start >= time { var moved = clip; moved.start = moved.start - time; right.clips.append(moved) }
            else {
                let pair = split(clip, at: time - clip.start)
                left.clips.append(pair.0)
                var second = pair.1; second.start = .zero; right.clips.append(second)
                if clip.kind == .video || clip.kind == .audio { splitSources[clip.id] = second.id }
                copyOverrides(from: clip.id, to: second.id, in: &document)
            }
        }
        document.scenes.replaceSubrange(index...index, with: [left, right])
        for (sourceID, rightID) in splitSources { CaptionBindingUpdater.splitBindings(sourceID: sourceID, rightID: rightID, in: &document) }
        CaptionBindingUpdater.refresh(&document)
        return right.id
    }
    /// Adjacent scenes can be grouped only at hard cuts. A transition is a temporal effect,
    /// not discarded by grouping; grouping through one requires baking it first.
    @discardableResult static func groupScenes(_ ids: [UUID], in document: inout ProjectDocument) throws -> UUID {
        let indices = document.scenes.indices.filter { ids.contains(document.scenes[$0].id) }
        guard indices.count >= 2, indices.count == Set(ids).count, let first = indices.first, let last = indices.last, last - first + 1 == indices.count else { throw DocumentError.invalid("Sélectionnez des scènes voisines") }
        guard document.scenes[first..<last].allSatisfy({ $0.transition.kind == .none }) else { throw DocumentError.invalid("Regroupement avec transition : retirez d’abord le chevauchement") }
        var grouped = document.scenes[first], cursor = MediaTime.zero
        grouped.clips = []; grouped.narration = ""
        for index in indices {
            let scene = document.scenes[index]
            grouped.clips += scene.clips.map { var clip = $0; clip.start = clip.start + cursor; return clip }
            if !scene.narration.isEmpty { grouped.narration += (grouped.narration.isEmpty ? "" : "\n") + scene.narration }
            cursor = cursor + scene.duration
        }
        grouped.duration = cursor; grouped.transition = document.scenes[last].transition
        document.scenes.replaceSubrange(first...last, with: [grouped])
        return grouped.id
    }
    @discardableResult static func splitClip(_ id: UUID, at localTime: MediaTime, in document: inout ProjectDocument) throws -> UUID {
        guard let original = document.clip(id), localTime > .zero, localTime < original.duration else { throw DocumentError.invalid("Coupe hors du clip") }
        var pair = split(original, at: localTime)
        if original.isCaption, let sourceID = original.captionSourceClipID {
            let plan = RenderPlan.compile(document: document, variantID: nil)
            guard let source = plan.clips.first(where: { $0.id == sourceID }), let caption = plan.clips.first(where: { $0.id == id }) else { throw DocumentError.missing("Source du sous-titre") }
            let sourceBoundary = TimeMapping.sourceTime(for: caption.globalStart + localTime - source.globalStart, clip: source.clip)
            if source.clip.reversed { pair.0.captionSourceStart = sourceBoundary; pair.1.captionSourceEnd = sourceBoundary }
            else { pair.0.captionSourceEnd = sourceBoundary; pair.1.captionSourceStart = sourceBoundary }
        }
        try replaceClip(id, in: &document, with: [pair.0, pair.1])
        copyOverrides(from: id, to: pair.1.id, in: &document)
        if original.kind == .video || original.kind == .audio { CaptionBindingUpdater.splitBindings(sourceID: id, rightID: pair.1.id, in: &document); CaptionBindingUpdater.refresh(&document) }
        else if original.isCaption { CaptionBindingUpdater.refresh(&document) }
        return pair.1.id
    }
    @discardableResult static func duplicateClip(_ id: UUID, in document: inout ProjectDocument) throws -> UUID {
        guard let original = document.clip(id) else { throw DocumentError.missing("Clip") }
        var copy = original; copy.id = UUID()
        copy.keyframes = original.keyframes.map { var key = $0; key.id = UUID(); return key }
        copy.effects = original.effects.map { var effect = $0; effect.id = UUID(); return effect }
        // A duplicate is another instance at the same time, one layer above; it never
        // silently expands scene duration or shifts project-anchored music.
        copy.layer = original.layer + 1
        try replaceClip(id, in: &document, with: [original, copy])
        copyOverrides(from: original.id, to: copy.id, in: &document)
        if original.kind == .video || original.kind == .audio { CaptionBindingUpdater.splitBindings(sourceID: id, rightID: copy.id, in: &document); CaptionBindingUpdater.refresh(&document) }
        return copy.id
    }
    static func trimClip(_ id: UUID, from: MediaTime, to: MediaTime, ripple: Bool = false, in document: inout ProjectDocument) throws {
        guard let original = document.clip(id), from >= .zero, to > from, to <= original.duration else { throw DocumentError.invalid("Bornes de trim") }
        var trimmed = original
        if from > .zero { trimmed = split(trimmed, at: from).1; trimmed.id = id }
        if to - from < trimmed.duration { trimmed = split(trimmed, at: to - from).0 }
        let removed = original.duration - trimmed.duration
        if ripple { trimmed.start = original.start }
        try replaceClip(id, in: &document, with: [trimmed])
        if ripple, let si = document.scenes.firstIndex(where: { $0.clips.contains(where: { $0.id == id }) }) {
            for ci in document.scenes[si].clips.indices where document.scenes[si].clips[ci].start >= original.end { document.scenes[si].clips[ci].start = document.scenes[si].clips[ci].start - removed }
            let latest = document.scenes[si].clips.map(\.end).max() ?? .zero
            document.scenes[si].duration = max(latest, document.scenes[si].duration - removed)
        }
        CaptionBindingUpdater.refresh(&document)
    }

    /// Moves one visible timeline boundary. Contrary to `trimClip`, this operation can
    /// re-extend a previously trimmed media clip while source pixels/samples remain.
    static func resizeClip(_ id: UUID, edge: ClipTrimEdge, by delta: MediaTime, in document: inout ProjectDocument) throws {
        guard var clip = document.clip(id) else { throw DocumentError.missing("Clip") }
        let original = clip
        let minimumDuration = 1.0 / 30.0
        var requestedDuration = edge == .leading
            ? original.duration.seconds - delta.seconds
            : original.duration.seconds + delta.seconds
        if edge == .leading { requestedDuration = min(requestedDuration, original.duration.seconds + original.start.seconds) }
        requestedDuration = max(minimumDuration, requestedDuration)

        if (clip.kind == .video || clip.kind == .audio), let asset = document.asset(clip.assetID) {
            let currentLow = clip.sourceStart.seconds
            let currentHigh = currentLow + clip.sourceDuration.seconds
            let assetHigh = max(currentHigh, asset.duration.seconds)
            let changesLowBoundary = (edge == .leading && !clip.reversed) || (edge == .trailing && clip.reversed)
            let lowerBoundary = changesLowBoundary ? 0.0 : currentLow
            let upperBoundary = changesLowBoundary ? currentHigh : assetHigh

            func candidate(_ boundary: Double) -> Clip {
                var value = original
                if changesLowBoundary {
                    value.sourceStart = .init(seconds: boundary)
                    value.sourceDuration = .init(seconds: max(0, currentHigh - boundary))
                } else {
                    value.sourceStart = .init(seconds: currentLow)
                    value.sourceDuration = .init(seconds: max(0, boundary - currentLow))
                }
                return value
            }

            let lowDuration = TimeMapping.outputDuration(clip: candidate(lowerBoundary)).seconds
            let highDuration = TimeMapping.outputDuration(clip: candidate(upperBoundary)).seconds
            let target = min(max(requestedDuration, min(lowDuration, highDuration)), max(lowDuration, highDuration))
            var low = lowerBoundary
            var high = upperBoundary
            for _ in 0..<48 {
                let middle = (low + high) * 0.5
                let duration = TimeMapping.outputDuration(clip: candidate(middle)).seconds
                if lowDuration <= highDuration {
                    if duration < target { low = middle } else { high = middle }
                } else {
                    if duration > target { low = middle } else { high = middle }
                }
            }
            clip = candidate((low + high) * 0.5)
            clip.duration = TimeMapping.outputDuration(clip: clip)
        } else {
            clip.duration = .init(seconds: requestedDuration)
        }

        if edge == .leading {
            clip.start = original.end - clip.duration
            let phaseDelta = clip.start - original.start
            clip.animationOffset = .init(seconds: max(0, original.animationOffset.seconds + phaseDelta.seconds))
        }
        try updateClip(id, in: &document) { $0 = clip }
        if let sceneIndex = document.scenes.firstIndex(where: { $0.clips.contains(where: { $0.id == id }) }) {
            document.scenes[sceneIndex].duration = max(document.scenes[sceneIndex].duration, clip.end)
        }
        CaptionBindingUpdater.refresh(&document)
    }
    static func updateClip(_ id: UUID, in document: inout ProjectDocument, _ update: (inout Clip) -> Void) throws {
        for si in document.scenes.indices {
            if let ci = document.scenes[si].clips.firstIndex(where: { $0.id == id }) { update(&document.scenes[si].clips[ci]); return }
        }
        if let ci = document.globalClips.firstIndex(where: { $0.id == id }) { update(&document.globalClips[ci]); return }
        throw DocumentError.missing("Clip")
    }
    static func moveClip(_ id: UUID, toScene sceneID: UUID?, at start: MediaTime, in document: inout ProjectDocument) throws {
        guard var clip = document.clip(id), start >= .zero else { throw DocumentError.missing("Clip") }
        clip.start = start
        if let sceneID { guard let scene = document.scenes.first(where: { $0.id == sceneID }), clip.end <= scene.duration else { throw DocumentError.invalid("Le clip dépasse la scène destination") } }
        try replaceClip(id, in: &document, with: [])
        if let sceneID, let index = document.scenes.firstIndex(where: { $0.id == sceneID }) { document.scenes[index].clips.append(clip) }
        else { document.globalClips.append(clip) }
    }
    /// Places a clip at a composition time. Scene ownership is an implementation detail:
    /// crossing a scene boundary during a Timeline drag transfers the clip instead of
    /// clamping it to the beginning of its original scene.
    static func moveClip(_ id: UUID, toGlobalStart globalStart: MediaTime, in document: inout ProjectDocument) throws {
        guard var clip = document.clip(id), globalStart >= .zero else { throw DocumentError.missing("Clip") }
        let plan = RenderPlan.compile(document: document, variantID: nil)
        let sourceIsGlobal = document.globalClips.contains { $0.id == id }

        if sourceIsGlobal {
            clip.start = globalStart
            try replaceClip(id, in: &document, with: [clip])
            CaptionBindingUpdater.refresh(&document)
            return
        }

        // In transition overlaps, the later scene is the intuitive destination: its
        // visible content has already begun. Outside the montage, use the nearest edge.
        let destination = plan.scenes.last(where: { $0.start <= globalStart && globalStart < $0.end })
            ?? (globalStart < (plan.scenes.first?.start ?? .zero) ? plan.scenes.first : plan.scenes.last)
        guard let destination, let destinationIndex = document.scenes.firstIndex(where: { $0.id == destination.id }) else {
            clip.start = globalStart
            try replaceClip(id, in: &document, with: [])
            document.globalClips.append(clip)
            CaptionBindingUpdater.refresh(&document)
            return
        }

        clip.start = max(.zero, globalStart - destination.start)
        try replaceClip(id, in: &document, with: [])
        if clip.end <= document.scenes[destinationIndex].duration {
            document.scenes[destinationIndex].clips.append(clip)
        } else {
            // A free Timeline move must not stretch a scene and shift everything that
            // follows. Keep the exact composition time as a project-owned clip.
            clip.start = globalStart
            document.globalClips.append(clip)
        }
        CaptionBindingUpdater.refresh(&document)
    }
    static func setPresentation(_ presentation: Presentation?, clipID: UUID, variantID: UUID?, in document: inout ProjectDocument) throws {
        guard document.clip(clipID) != nil else { throw DocumentError.missing("Clip") }
        if let variantID {
            guard let index = document.variants.firstIndex(where: { $0.id == variantID }) else { throw DocumentError.missing("Format") }
            document.variants[index].overrides[clipID.uuidString] = presentation
        } else { try updateClip(clipID, in: &document) { $0.presentation = presentation ?? .init() } }
    }
    static func removeClip(_ id: UUID, in document: inout ProjectDocument) throws { try replaceClip(id, in: &document, with: []); removeOverrides(for: id, in: &document) }
    private static func split(_ clip: Clip, at offset: MediaTime) -> (Clip, Clip) {
        var left = clip, right = clip
        left.effectSeed = clip.effectSeed ?? clip.id; right.effectSeed = left.effectSeed
        left.duration = offset
        right.id = UUID(); right.start = clip.start + offset; right.duration = clip.duration - offset
        let boundary = TimeMapping.sourceTime(for: offset, clip: clip)
        if clip.kind == .video || clip.kind == .audio {
            if clip.reversed { left.sourceStart = boundary; left.sourceDuration = clip.sourceStart + clip.sourceDuration - boundary; right.sourceDuration = boundary - clip.sourceStart }
            else { left.sourceDuration = boundary - clip.sourceStart; right.sourceStart = boundary; right.sourceDuration = clip.sourceStart + clip.sourceDuration - boundary }
        }
        let animationDuration = clip.animationDuration ?? clip.duration
        left.animationDuration = animationDuration; right.animationDuration = animationDuration
        right.animationOffset = clip.animationOffset + offset
        return (left, right)
    }
    private static func replaceClip(_ id: UUID, in document: inout ProjectDocument, with replacements: [Clip]) throws {
        for si in document.scenes.indices { if let ci = document.scenes[si].clips.firstIndex(where: { $0.id == id }) { document.scenes[si].clips.replaceSubrange(ci...ci, with: replacements); return } }
        if let ci = document.globalClips.firstIndex(where: { $0.id == id }) { document.globalClips.replaceSubrange(ci...ci, with: replacements); return }
        throw DocumentError.missing("Clip")
    }
    private static func copyOverrides(from old: UUID, to new: UUID, in document: inout ProjectDocument) { for index in document.variants.indices { document.variants[index].overrides[new.uuidString] = document.variants[index].overrides[old.uuidString] } }
    private static func removeOverrides(for id: UUID, in document: inout ProjectDocument) { for index in document.variants.indices { document.variants[index].overrides[id.uuidString] = nil } }
}
