import Foundation

struct CaptionSegment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var start: MediaTime
    var end: MediaTime
    var text: String
    var sourceAssetID: UUID? = nil
    var analyzedRevision: Int? = nil
    var duration: MediaTime { end - start }
    func asClip() -> Clip { Clip(kind: .text, start: start, duration: duration, text: text, presentation: Presentation(y: 0.82, scale: 0.9, textSize: 0.055, textBackgroundOpacity: 0.55), layer: 100, isCaption: true, captionSourceAssetID: sourceAssetID, captionSourceStart: sourceAssetID == nil ? nil : start, captionSourceEnd: sourceAssetID == nil ? nil : end, captionAnalyzedRevision: analyzedRevision) }
}

enum CaptionSegmenter {
    /// Turns speech-engine tokens into readable caption cards. A card ends at sentence
    /// punctuation, a natural pause, or before it becomes too long to read on a phone.
    static func segments(
        from words: [TranscribedWord],
        sourceAssetID: UUID,
        analyzedRevision: Int,
        maximumWords: Int = 9,
        maximumCharacters: Int = 54,
        maximumDuration: Double = 4,
        pauseThreshold: Double = 0.65
    ) -> [CaptionSegment] {
        let tokens = words
            .filter { $0.duration > 0 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        guard !tokens.isEmpty else { return [] }

        var result: [CaptionSegment] = []
        var text = ""
        var start = 0.0
        var end = 0.0
        var wordCount = 0

        func joined(_ current: String, _ token: String) -> String {
            guard !current.isEmpty else { return token }
            let noSpaceBefore = CharacterSet(charactersIn: ".,;:!?…)]}»")
            let noSpaceAfter = CharacterSet(charactersIn: "([{«'’-")
            if token.unicodeScalars.first.map(noSpaceBefore.contains) == true || current.unicodeScalars.last.map(noSpaceAfter.contains) == true { return current + token }
            return current + " " + token
        }
        func isSentenceEnd(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?…".contains($0) } ?? false
        }
        func emit() {
            guard !text.isEmpty, end > start else { return }
            result.append(.init(start: .init(seconds: start), end: .init(seconds: end), text: text, sourceAssetID: sourceAssetID, analyzedRevision: analyzedRevision))
            text = ""; wordCount = 0
        }

        for token in tokens {
            let clean = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenWords = max(1, clean.split(whereSeparator: { $0.isWhitespace }).count)
            let candidate = joined(text, clean)
            let gap = token.start - end
            let projectedDuration = token.start + token.duration - start
            if !text.isEmpty && (gap > pauseThreshold || wordCount + tokenWords > maximumWords || candidate.count > maximumCharacters || projectedDuration > maximumDuration) {
                emit()
            }
            if text.isEmpty { start = token.start }
            text = joined(text, clean)
            end = max(token.start + token.duration, start + 1.0 / 60.0)
            wordCount += tokenWords
            if isSentenceEnd(clean) { emit() }
        }
        emit()
        return result
    }
}

/// Captions bound to media instances retain source timestamps. Their scene-local positions
/// are derived after edits; imported SRT captions without a binding keep composition timing.
enum CaptionBindingUpdater {
    static func refresh(_ document: inout ProjectDocument) {
        let plan = RenderPlan.compile(document: document, variantID: nil)
        let sources = Dictionary(plan.clips.filter { !$0.clip.isCaption }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let captions = document.allClips.filter { $0.isCaption && $0.captionSourceClipID != nil }
        let ids = Set(captions.map(\.id))
        for index in document.scenes.indices { document.scenes[index].clips.removeAll { ids.contains($0.id) } }
        document.globalClips.removeAll { ids.contains($0.id) }
        for var caption in captions {
            guard let sourceID = caption.captionSourceClipID, let source = sources[sourceID], let originalStart = caption.captionSourceStart, let originalEnd = caption.captionSourceEnd else {
                for index in document.variants.indices { document.variants[index].overrides[caption.id.uuidString] = nil }
                continue
            }
            let lower = max(originalStart, source.clip.sourceStart)
            let upper = min(originalEnd, source.clip.sourceStart + source.clip.sourceDuration)
            guard upper > lower else {
                for index in document.variants.indices { document.variants[index].overrides[caption.id.uuidString] = nil }
                continue
            }
            let a = TimeMapping.localTime(forSource: lower, clip: source.clip), b = TimeMapping.localTime(forSource: upper, clip: source.clip)
            let start = min(a,b), end = min(max(a,b), source.clip.duration)
            guard end > start else { for index in document.variants.indices { document.variants[index].overrides[caption.id.uuidString] = nil }; continue }
            caption.duration = end - start
            if let sceneID = source.sceneID, let index = document.scenes.firstIndex(where: { $0.id == sceneID }) { caption.start = source.clip.start + start; document.scenes[index].clips.append(caption) }
            else { caption.start = source.globalStart + start; document.globalClips.append(caption) }
        }
    }
    static func splitBindings(sourceID: UUID, rightID: UUID, in document: inout ProjectDocument) {
        let captions = document.allClips.filter { $0.captionSourceClipID == sourceID }
        for caption in captions {
            var right = caption; right.id = UUID(); right.captionSourceClipID = rightID
            // Refresh places both intersections alongside their explicit owning media instance.
            document.globalClips.append(right)
            for index in document.variants.indices { document.variants[index].overrides[right.id.uuidString] = document.variants[index].overrides[caption.id.uuidString] }
        }
    }
}

enum CaptionCodec {
    static func importSRT(_ text: String) throws -> [CaptionSegment] {
        let normalized = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [CaptionSegment] = []
        for block in normalized.components(separatedBy: "\n\n") where !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = block.components(separatedBy: "\n")
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }), timing <= 1 else { throw DocumentError.corrupt("Timecode SRT absent") }
            let times = lines[timing].components(separatedBy: "-->")
            guard times.count == 2 else { throw DocumentError.corrupt("Timecode SRT") }
            let start = try parseTime(times[0]), end = try parseTime(times[1])
            let body = lines.dropFirst(timing + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
            guard start < end, !body.isEmpty else { throw DocumentError.corrupt("Sous-titre vide ou durée invalide") }
            result.append(.init(start: start, end: end, text: body))
        }
        return result.sorted { $0.start < $1.start }
    }
    static func exportSRT(_ segments: [CaptionSegment]) -> String {
        segments.sorted { $0.start < $1.start }.enumerated().map { "\($0.offset + 1)\n\(timestamp($0.element.start, separator: ",")) --> \(timestamp($0.element.end, separator: ","))\n\($0.element.text)" }.joined(separator: "\n\n") + "\n"
    }
    static func exportVTT(_ segments: [CaptionSegment]) -> String {
        "WEBVTT\n\n" + segments.sorted { $0.start < $1.start }.map { "\(timestamp($0.start, separator: ".")) --> \(timestamp($0.end, separator: "."))\n\($0.text)" }.joined(separator: "\n\n") + "\n"
    }
    static func segments(document: ProjectDocument) -> [CaptionSegment] {
        RenderPlan.compile(document: document, variantID: nil).clips.filter { $0.clip.isCaption }.map { .init(id: $0.id, start: $0.globalStart, end: $0.end, text: $0.clip.text) }
    }
    /// Source captions are clipped and remapped to a rendered media instance. Source timestamps
    /// remain on the input segments; the returned segments describe composition time only.
    static func remap(_ segments: [CaptionSegment], through clip: RenderClip) -> [CaptionSegment] {
        let low = clip.clip.sourceStart, high = low + clip.clip.sourceDuration
        return segments.compactMap { segment in
            guard segment.sourceAssetID == nil || segment.sourceAssetID == clip.clip.assetID else { return nil }
            let start = max(low, segment.start), end = min(high, segment.end)
            guard end > start else { return nil }
            let first = TimeMapping.localTime(forSource: start, clip: clip.clip), last = TimeMapping.localTime(forSource: end, clip: clip.clip)
            return CaptionSegment(start: clip.globalStart + min(first, last), end: clip.globalStart + max(first, last), text: segment.text)
        }
    }
    private static func parseTime(_ value: String) throws -> MediaTime {
        let pieces = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard pieces.count == 3, let hours = Int(pieces[0]), let minutes = Int(pieces[1]), let seconds = Double(pieces[2]), hours >= 0, hours < 168, (0..<60).contains(minutes), (0..<60).contains(seconds) else { throw DocumentError.corrupt("Timecode SRT invalide") }
        return .init(seconds: Double(hours * 3600 + minutes * 60) + seconds)
    }
    private static func timestamp(_ time: MediaTime, separator: String) -> String {
        let milliseconds = Int64((max(0, time.seconds) * 1000).rounded())
        return String(format: "%02lld:%02lld:%02lld%@%03lld", milliseconds / 3_600_000, (milliseconds / 60_000) % 60, (milliseconds / 1000) % 60, separator, milliseconds % 1000)
    }
}
