import Foundation

struct CaptionReviewFailure: LocalizedError {
    let message: String
    var start: MediaTime? = nil
    var end: MediaTime? = nil
    var errorDescription: String? { L(message) }
}

struct CaptionReviewInput: Identifiable, Sendable {
    let id: UUID
    let original: String
    let text: String
    let start: MediaTime
    let end: MediaTime
    var layer: Int = 0
}

struct CaptionCorrection: Identifiable, Sendable {
    let id: UUID
    let original: String
    let reviewedText: String
    var replacement: String
    let start: MediaTime
    let end: MediaTime
    var accepted = true
    var groupID: UUID? = nil
}

enum CaptionProofreading {
    private static func responseObject(_ response: String) throws -> [String: Any] {
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some model versions wrap valid JSON in a single markdown block. Only
        // unwrap that complete block; never fish a JSON fragment out of other prose.
        for prefix in ["```json\n", "```\n"] where json.hasPrefix(prefix) && json.hasSuffix("```") {
            json = String(json.dropFirst(prefix.count).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard json.utf8.count <= 16384, let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CaptionReviewFailure(message: "Apple Intelligence n’a pas renvoyé de corrections exploitables. Aucun sous-titre n’a été modifié.")
        }
        return root
    }

    /// The model corrects a complete phrase; CutFuze controls its redistribution.
    /// Original word-count proportions anchor every cut. Each output token appears
    /// exactly once, no segment becomes empty, and no timeline timing is changed.
    static func decodePhraseResponse(_ response: String, for inputs: [CaptionReviewInput]) throws -> [CaptionCorrection] {
        let root = try responseObject(response)
        guard Set(root.keys) == ["text"], let text = root["text"] as? String, !inputs.isEmpty else {
            throw CaptionReviewFailure(message: "Apple Intelligence n’a pas renvoyé de corrections exploitables. Aucun sous-titre n’a été modifié.")
        }
        let words = text.split(whereSeparator: \.isWhitespace)
        let originalCounts = inputs.map { $0.text.split(whereSeparator: \.isWhitespace).count }
        guard originalCounts.allSatisfy({ $0 > 0 }), words.count >= inputs.count, text.utf8.count <= 3600 else {
            throw CaptionReviewFailure(message: "La phrase corrigée ne peut pas être répartie sur les segments existants. Aucun sous-titre n’a été modifié.")
        }
        let originalTotal = originalCounts.reduce(0, +)
        var cursor = 0
        var originalCursor = 0
        var indexedTexts: [(Int, String)] = []
        for index in inputs.indices {
            originalCursor += originalCounts[index]
            let desiredEnd = Int((Double(words.count) * Double(originalCursor) / Double(originalTotal)).rounded())
            let remainingSegments = inputs.count - index - 1
            let end = min(words.count - remainingSegments, max(cursor + 1, desiredEnd))
            indexedTexts.append((index, words[cursor..<end].joined(separator: " ")))
            cursor = end
        }
        var result = try corrections(for: inputs, indexedTexts: indexedTexts)
        for index in result.indices { result[index].groupID = inputs[0].id }
        return result
    }

    /// A snapshot, including an optional unsaved text draft. No document writes.
    static func inputs(in document: ProjectDocument, draftID: UUID? = nil, draft: String? = nil) -> [CaptionReviewInput] {
        CaptionEditing.captions(in: document).map {
            CaptionReviewInput(id: $0.id, original: $0.clip.text,
                               text: $0.id == draftID ? (draft ?? $0.clip.text) : $0.clip.text,
                               start: $0.globalStart, end: $0.end, layer: $0.clip.layer)
        }
    }

    /// Bound each fresh model session by both text size and number of cues.
    static func batches(_ inputs: [CaptionReviewInput]) throws -> [[CaptionReviewInput]] {
        var result: [[CaptionReviewInput]] = []
        var current: [CaptionReviewInput] = []
        var count = 0
        for input in inputs {
            guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  input.text.utf8.count <= 1800 else {
                throw CaptionReviewFailure(message: "Un sous-titre est vide ou trop long pour la relecture. Scindez-le avant de réessayer.")
            }
            if current.count == 8 || count + input.text.utf8.count > 1800 {
                result.append(current); current = []; count = 0
            }
            current.append(input); count += input.text.utf8.count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Prefer complete spoken phrases, without joining overlapping caption layers or
    /// distant speech. Long/unpunctuated phrases retain the same bounded sessions.
    static func phraseBatches(_ inputs: [CaptionReviewInput]) throws -> [[CaptionReviewInput]] {
        _ = try batches(inputs) // Validate the same per-cue text limits up front.
        var result: [[CaptionReviewInput]] = []
        var current: [CaptionReviewInput] = []
        var bytes = 0
        for input in inputs {
            let isSeparate: Bool
            if let previous = current.last {
                let gap = input.start.seconds - previous.end.seconds
                isSeparate = input.layer != previous.layer || gap < -0.1 || gap > 1.2
            } else { isSeparate = false }
            if !current.isEmpty && (isSeparate || current.count == 8 || bytes + input.text.utf8.count > 1800) {
                result.append(current); current = []; bytes = 0
            }
            current.append(input); bytes += input.text.utf8.count
            let ending = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'»”’)]}"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = ending.last, ".!?…".contains(last) {
                result.append(current); current = []; bytes = 0
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Reject missing, duplicate, invented or empty model output before displaying it.
    static func corrections(for inputs: [CaptionReviewInput], indexedTexts: [(Int, String)]) throws -> [CaptionCorrection] {
        guard indexedTexts.count == inputs.count,
              Set(indexedTexts.map { $0.0 }) == Set(inputs.indices) else {
            throw CaptionReviewFailure(message: "Réponse de relecture incomplète. Aucun sous-titre n’a été modifié.")
        }
        return try indexedTexts.sorted { $0.0 < $1.0 }.compactMap { index, value in
            let input = inputs[index]
            let replacement = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !replacement.isEmpty, replacement.utf8.count <= 3600 else {
                throw CaptionReviewFailure(message: "Correction invalide. Aucun sous-titre n’a été modifié.")
            }
            guard replacement != input.original else { return nil }
            return CaptionCorrection(id: input.id, original: input.original, reviewedText: input.text, replacement: replacement, start: input.start, end: input.end)
        }
    }

    /// Validate every accepted correction first, then apply atomically. Only text changes;
    /// timing, source links, presentation, effects and per-format overrides stay intact.
    static func apply(_ corrections: [CaptionCorrection], in document: inout ProjectDocument) throws {
        let groups = Dictionary(grouping: corrections.filter { $0.groupID != nil }, by: { $0.groupID! })
        guard groups.values.allSatisfy({ Set($0.map(\.accepted)).count <= 1 }) else {
            throw CaptionReviewFailure(message: "Validez ou refusez ensemble les corrections d’une même phrase.")
        }
        let accepted = corrections.filter(\.accepted)
        guard Set(accepted.map(\.id)).count == accepted.count else { throw CaptionReviewFailure(message: "Corrections en double") }
        for correction in accepted {
            guard let clip = document.clip(correction.id), clip.isCaption, clip.text == correction.original else {
                throw CaptionReviewFailure(message: "Les sous-titres ont changé depuis la vérification. Relancez la relecture.")
            }
            guard !correction.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CaptionReviewFailure(message: "Une correction ne peut pas être vide.")
            }
        }
        var candidate = document
        for correction in accepted {
            try DocumentEditor.updateClip(correction.id, in: &candidate) { $0.text = correction.replacement }
        }
        document = candidate
    }
}
