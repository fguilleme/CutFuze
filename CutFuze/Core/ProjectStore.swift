import Foundation
import CryptoKit

extension ProjectDocument {
    func validate() throws {
        try validateBeatMarkers()
        guard schemaVersion == Self.currentSchemaVersion else { throw DocumentError.unsupportedVersion(schemaVersion) }
        guard revision >= 0, !title.isEmpty, title.count <= 4096, scenes.count <= 10_000, assets.count <= 20_000, allClips.count <= 100_000, !variants.isEmpty, variants.count <= 100 else { throw DocumentError.invalid("Limites du document") }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard unique(scenes.map(\.id)), unique(assets.map(\.id)), unique(allClips.map(\.id)), unique(variants.map(\.id)) else { throw DocumentError.invalid("Identifiants dupliqués") }
        func validTime(_ time: MediaTime) -> Bool { time.timescale > 0 && time.timescale <= 1_000_000 && time.value >= 0 && time.seconds <= 604_800 }
        let assetIDs = Set(assets.map(\.id)), clipIDs = Set(allClips.map { $0.id.uuidString })
        for asset in assets {
            guard SafePath.isRelative(asset.relativePath), validTime(asset.duration), asset.width >= 0, asset.height >= 0, asset.width <= 65_536, asset.height <= 65_536, asset.nominalFrameRate.isFinite else { throw DocumentError.invalid(String(format: L("Média %@"), asset.name)) }
        }
        for scene in scenes {
            guard validTime(scene.duration), scene.duration > .zero, validTime(scene.transition.duration) else { throw DocumentError.invalid("Durée de scène") }
            for clip in scene.clips where clip.end > scene.duration { throw DocumentError.invalid(L("Un segment dépasse sa scène")) }
        }
        for clip in allClips {
            guard validTime(clip.start), validTime(clip.duration), clip.duration > .zero, validTime(clip.sourceStart), validTime(clip.sourceDuration), validTime(clip.animationOffset), validTime(clip.fadeIn), validTime(clip.fadeOut), clip.speed.isFinite, (0.1...100).contains(clip.speed), clip.volume.isFinite, (0...8).contains(clip.volume) else { throw DocumentError.invalid("Paramètres du clip") }
            if let id = clip.assetID { guard assetIDs.contains(id) else { throw DocumentError.missing("Référence média") } }
            if clip.kind == .video || clip.kind == .audio || clip.kind == .image { guard clip.assetID != nil else { throw DocumentError.missing("Source du clip") } }
            if let asset = asset(clip.assetID), (clip.kind == .video || clip.kind == .audio), asset.duration > .zero {
                guard clip.sourceStart + clip.sourceDuration <= asset.duration + MediaTime(value: 2) else { throw DocumentError.invalid("Plage source hors média") }
            }
            try validatePresentation(clip.presentation)
            for effect in clip.effects { try effect.validateAnimation() }
            guard clip.effects.allSatisfy({ $0.amount.isFinite }), clip.keyframes.allSatisfy({ validTime($0.time) && $0.value.isFinite }), clip.speedPoints.allSatisfy({ validTime($0.sourceTime) && $0.speed.isFinite && (0.1...100).contains($0.speed) }) else { throw DocumentError.invalid("Animation ou effet") }
            guard Set(clip.speedPoints.map(\.sourceTime)).count == clip.speedPoints.count else { throw DocumentError.invalid("Points de vitesse superposés") }
            guard clip.keyframes.filter({ $0.property == .volume }).allSatisfy({ (0...8).contains($0.value) }) else { throw DocumentError.invalid("Volume") }
            guard clip.keyframes.filter({ $0.property == .maskWidth || $0.property == .maskHeight }).allSatisfy({ $0.value > 0 }) else { throw DocumentError.invalid("Dimensions du masque") }
            if let sourceID = clip.captionSourceClipID {
                guard clip.isCaption, let source = self.clip(sourceID), !source.isCaption, source.assetID == clip.captionSourceAssetID, let start = clip.captionSourceStart, let end = clip.captionSourceEnd, validTime(start), validTime(end), end > start else { throw DocumentError.invalid("Rattachement du sous-titre") }
            }
        }
        for variant in variants {
            if let canvas = variant.canvas {
                guard canvas.blur.isFinite, (0...0.2).contains(canvas.blur) else { throw DocumentError.invalid("Fond du canevas") }
                if let id = canvas.imageAssetID { guard assets.contains(where: { $0.id == id && $0.kind == .image }) else { throw DocumentError.missing("Image de fond") } }
            }
            guard variant.widthRatio.isFinite, variant.heightRatio.isFinite, variant.widthRatio > 0, variant.heightRatio > 0, (0.05...20).contains(variant.ratio), variant.safeMargin.isFinite, (0...0.45).contains(variant.safeMargin) else { throw DocumentError.invalid("Format de sortie") }
            for (id, presentation) in variant.overrides { guard clipIDs.contains(id) else { throw DocumentError.missing("Surcharge orpheline") }; try validatePresentation(presentation) }
        }
        guard duration.seconds <= 604_800 else { throw DocumentError.invalid("Durée totale supérieure à sept jours") }
    }
    private func validatePresentation(_ p: Presentation) throws {
        let values = [p.x,p.y,p.scale,p.rotation,p.opacity,p.textSize,p.maskX,p.maskY,p.maskWidth,p.maskHeight,p.maskRotation,p.maskFeather,p.textOutline,p.textShadow,p.textBackgroundOpacity,p.chromaKeyTolerance,p.chromaKeySoftness]
        guard values.allSatisfy(\.isFinite), p.scale > 0, p.scale <= 100, (0...1).contains(p.opacity), p.textSize > 0, p.maskWidth > 0, p.maskHeight > 0 else { throw DocumentError.invalid("Présentation") }
        guard p.textLetterSpacing.isFinite, (-0.15...2).contains(p.textLetterSpacing), p.textLineSpacing.isFinite, (0...3).contains(p.textLineSpacing) else { throw DocumentError.invalid("Espacement de texte") }
    }
}

enum SafePath {
    static func isRelative(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix("~") }
    }
    static func resolve(_ path: String, in root: URL) throws -> URL {
        guard isRelative(path) else { throw DocumentError.invalid("Chemin non relatif ou dangereux") }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        var cursor = root
        for component in path.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            if let values = try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw DocumentError.invalid("Lien symbolique interdit") }
        }
        let resolved = cursor.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(base.path + "/") else { throw DocumentError.invalid("Chemin hors stockage") }
        return resolved
    }
}

enum DocumentCodec {
    static func encode(_ document: ProjectDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 32 * 1024 * 1024 else { throw DocumentError.invalid("Manifeste trop volumineux") }
        return data
    }
    static func decode(_ data: Data) throws -> ProjectDocument {
        guard data.count <= 32 * 1024 * 1024 else { throw DocumentError.invalid("Manifeste trop volumineux") }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["schemaVersion"] as? Int else { throw DocumentError.corrupt("Version absente") }
        guard version == 1 || version == ProjectDocument.currentSchemaVersion else { throw DocumentError.unsupportedVersion(version) }
        if version == 1 {
            // Defined development v1: same scene graph without revision/collection/variants.
            // The original Hello World application never had a persisted document format.
            object["schemaVersion"] = ProjectDocument.currentSchemaVersion
            object["revision"] = object["revision"] ?? 0
            object["collection"] = object["collection"] ?? ""
            object["globalClips"] = object["globalClips"] ?? []
            if object["variants"] == nil { object["variants"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(OutputVariant.standard)) }
        }
        let normalized = try JSONSerialization.data(withJSONObject: object)
        let document = try JSONDecoder().decode(ProjectDocument.self, from: normalized)
        try document.validate()
        return document
    }
}

final class ProjectStore: @unchecked Sendable {
    let rootURL: URL
    private let lock = NSRecursiveLock()
    init(rootURL: URL) { self.rootURL = rootURL }
    private func directory(_ id: UUID) -> URL { rootURL.appendingPathComponent("Projects", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }
    private func readManifest(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= 32 * 1024 * 1024 else { throw DocumentError.invalid("Manifeste trop volumineux") }
        return try Data(contentsOf: url)
    }
    func save(document: ProjectDocument) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try DocumentCodec.encode(document)
        let folder = directory(document.id), target = folder.appendingPathComponent("manifest.json"), backup = folder.appendingPathComponent("previous.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let prior = try? readManifest(target), (try? DocumentCodec.decode(prior)) != nil { try prior.write(to: backup, options: .atomic) }
        try data.write(to: target, options: .atomic)
    }
    func load(id: UUID) throws -> ProjectDocument {
        lock.lock(); defer { lock.unlock() }
        let folder = directory(id), manifest = folder.appendingPathComponent("manifest.json")
        do { let document = try DocumentCodec.decode(readManifest(manifest)); guard document.id == id else { throw DocumentError.corrupt("Identité de manifeste") }; return document }
        catch DocumentError.unsupportedVersion(let version) { throw DocumentError.unsupportedVersion(version) }
        catch {
            guard let backup = try? readManifest(folder.appendingPathComponent("previous.json")), let recovered = try? DocumentCodec.decode(backup), recovered.id == id else { throw error }
            try backup.write(to: manifest, options: .atomic)
            return recovered
        }
    }
    func list() throws -> [ProjectDocument] {
        lock.lock(); defer { lock.unlock() }
        let projects = rootURL.appendingPathComponent("Projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projects.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: [.isDirectoryKey]).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try load(id: id)
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }
    func delete(id: UUID) throws { lock.lock(); defer { lock.unlock() }; try FileManager.default.removeItem(at: directory(id)) }
    func duplicate(document: ProjectDocument) throws -> ProjectDocument {
        var duplicate = document; duplicate.id = UUID(); duplicate.title += " · copie"; duplicate.modifiedAt = Date(); duplicate.revision = 0
        try save(document: duplicate)
        return duplicate
    }
}

enum FileDigest {
    static func sha256(of url: URL, cancelled: () -> Bool = { false }) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            if cancelled() { throw DocumentError.cancelled }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
