import Foundation

/// Caption edits operate on the same clip graph as Timeline. All callers wrap an operation
/// in EditHistory, which validates once and remaps source-bound captions before publication.
enum CaptionEditing {
    static func captions(in document: ProjectDocument) -> [RenderClip] {
        RenderPlan.compile(document: document, variantID: nil).clips.filter { $0.clip.isCaption }.sorted {
            $0.globalStart == $1.globalStart ? $0.id.uuidString < $1.id.uuidString : $0.globalStart < $1.globalStart
        }
    }

    static func update(_ id: UUID, text: String, from start: MediaTime, to end: MediaTime, in document: inout ProjectDocument) throws {
        guard let caption = captions(in: document).first(where: { $0.id == id }), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, start >= .zero, end > start else { throw DocumentError.invalid("Texte ou bornes du sous-titre") }
        let plan = RenderPlan.compile(document: document, variantID: nil)
        if let sourceID = caption.clip.captionSourceClipID {
            guard let source = plan.clips.first(where: { $0.id == sourceID }), start >= source.globalStart, end <= source.end else { throw DocumentError.invalid("Le sous-titre lié doit rester dans son clip source") }
            let a = TimeMapping.sourceTime(for: start - source.globalStart, clip: source.clip)
            let b = TimeMapping.sourceTime(for: end - source.globalStart, clip: source.clip)
            try DocumentEditor.updateClip(id, in: &document) {
                $0.text = text; $0.captionSourceStart = min(a, b); $0.captionSourceEnd = max(a, b)
            }
            CaptionBindingUpdater.refresh(&document)
        } else {
            let origin = caption.sceneID.flatMap { sceneID in plan.scenes.first { $0.id == sceneID }?.start } ?? .zero
            if let sceneID = caption.sceneID, let span = plan.scenes.first(where: { $0.id == sceneID }) {
                guard start >= span.start, end <= span.end else { throw DocumentError.invalid("Le sous-titre doit rester dans sa scène") }
            }
            try DocumentEditor.updateClip(id, in: &document) { $0.text = text; $0.start = start - origin; $0.duration = end - start }
        }
    }

    @discardableResult static func split(_ id: UUID, at time: MediaTime, firstText: String, secondText: String, in document: inout ProjectDocument) throws -> UUID {
        guard let rendered = captions(in: document).first(where: { $0.id == id }), time > rendered.globalStart, time < rendered.end, !firstText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !secondText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentError.invalid("Temps ou textes de scission") }
        let rightID = try DocumentEditor.splitClip(id, at: time - rendered.globalStart, in: &document)
        try DocumentEditor.updateClip(id, in: &document) { $0.text = firstText }
        try DocumentEditor.updateClip(rightID, in: &document) { $0.text = secondText }
        CaptionBindingUpdater.refresh(&document)
        return rightID
    }

    /// Merging is explicit about ownership: no implicit reassignment of scene or source.
    /// The first cue keeps its UUID, presentation and per-format overrides.
    @discardableResult static func merge(_ firstID: UUID, with secondID: UUID, in document: inout ProjectDocument) throws -> UUID {
        let all = captions(in: document)
        guard let index = all.firstIndex(where: { $0.id == firstID }), index + 1 < all.count, all[index + 1].id == secondID else { throw DocumentError.invalid("Fusionnez des sous-titres voisins dans le montage") }
        let first = all[index], second = all[index + 1]
        guard first.sceneID == second.sceneID else { throw DocumentError.invalid("Fusion impossible entre deux scènes : déplacez explicitement les segments vers le projet") }
        guard first.clip.captionSourceClipID == second.clip.captionSourceClipID, first.clip.captionSourceAssetID == second.clip.captionSourceAssetID else { throw DocumentError.invalid("Les sous-titres doivent partager la même source ou être détachés explicitement") }
        let mergedText = first.clip.text + "\n" + second.clip.text
        let mergedEnd = max(first.end, second.end)
        try DocumentEditor.updateClip(firstID, in: &document) { clip in
            clip.text = mergedText; clip.duration = mergedEnd - first.globalStart
            if let a = first.clip.captionSourceStart, let b = second.clip.captionSourceStart, let c = first.clip.captionSourceEnd, let d = second.clip.captionSourceEnd {
                clip.captionSourceStart = min(a, b); clip.captionSourceEnd = max(c, d)
                clip.captionAnalyzedRevision = first.clip.captionAnalyzedRevision == second.clip.captionAnalyzedRevision ? first.clip.captionAnalyzedRevision : nil
            }
        }
        try DocumentEditor.removeClip(secondID, in: &document)
        CaptionBindingUpdater.refresh(&document)
        return firstID
    }

    static func applyStyle(from id: UUID, variantID: UUID?, in document: inout ProjectDocument) throws {
        guard let source = document.clip(id), source.isCaption else { throw DocumentError.missing("Sous-titre de référence") }
        let presentation: Presentation
        if let variantID {
            guard let variant = document.variants.first(where: { $0.id == variantID }) else { throw DocumentError.missing("Format") }
            presentation = variant.overrides[id.uuidString] ?? source.presentation
        } else { presentation = source.presentation }
        for caption in document.allClips where caption.isCaption { try DocumentEditor.setPresentation(presentation, clipID: caption.id, variantID: variantID, in: &document) }
    }

    static func detachSource(_ id: UUID, in document: inout ProjectDocument) throws {
        guard document.clip(id)?.isCaption == true else { throw DocumentError.missing("Sous-titre") }
        try DocumentEditor.updateClip(id, in: &document) {
            $0.captionSourceAssetID = nil; $0.captionSourceClipID = nil; $0.captionSourceStart = nil; $0.captionSourceEnd = nil; $0.captionAnalyzedRevision = nil
        }
    }
}
