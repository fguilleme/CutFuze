import Foundation
import CryptoKit
import Darwin

/// CutFuze package v2: 8-byte magic, big-endian UInt64 JSON-header length, bounded
/// header, then raw file streams in header order. No compression, links, or executable entries.
/// Memory stays bounded to one 1 MiB block plus the <=32 MiB manifest.
enum PortableProject {
    struct Limits: Sendable {
        var maximumBytes: UInt64 = 8 * 1024 * 1024 * 1024
        var maximumFiles: Int = 20_000
        var maximumHeaderBytes: UInt64 = 32 * 1024 * 1024
    }
    private struct Entry: Codable { var path: String; var byteCount: UInt64; var sha256: String }
    private struct Header: Codable { var version: Int; var document: ProjectDocument; var files: [Entry] }
    private static let magic = Data("CFUZPK02".utf8)
    static func export(document: ProjectDocument, rootURL: URL, to destination: URL, cancelled: () -> Bool = { false }) throws {
        try document.validate()
        var snapshot = document
        var entries: [Entry] = [], sourceURLs: [URL] = [], pathsByDigest: [String: String] = [:]
        for index in snapshot.assets.indices {
            if cancelled() { throw DocumentError.cancelled }
            let asset = snapshot.assets[index], source = try SafePath.resolve(asset.relativePath, in: rootURL)
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size >= 0 else { throw DocumentError.invalid("Source média non régulière") }
            let digest = try FileDigest.sha256(of: source, cancelled: cancelled)
            if !asset.sha256.isEmpty && asset.sha256 != digest { throw DocumentError.corrupt(String(format: L("Intégrité du média %@"), asset.name)) }
            let path: String
            if let existing = pathsByDigest[digest] { path = existing }
            else {
                let ext = source.pathExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
                path = "Assets/\(digest)" + (ext.isEmpty ? "" : ".\(ext.prefix(12))")
                entries.append(.init(path: path, byteCount: UInt64(size), sha256: digest)); sourceURLs.append(source); pathsByDigest[digest] = path
            }
            snapshot.assets[index].relativePath = path; snapshot.assets[index].sha256 = digest
        }
        let header = Header(version: 2, document: snapshot, files: entries)
        try validate(header: header, limits: Limits())
        let headerData = try JSONEncoder().encode(header)
        guard headerData.count <= Limits().maximumHeaderBytes else { throw DocumentError.invalid("Manifeste trop volumineux") }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        guard fm.createFile(atPath: temporary.path, contents: nil) else { throw DocumentError.invalid("Création du paquet impossible") }
        defer { try? fm.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        do {
            try output.write(contentsOf: magic)
            var length = UInt64(headerData.count).bigEndian
            try withUnsafeBytes(of: &length) { try output.write(contentsOf: Data($0)) }
            try output.write(contentsOf: headerData)
            for (index, entry) in entries.enumerated() {
                let input = try FileHandle(forReadingFrom: sourceURLs[index]); defer { try? input.close() }
                var remaining = entry.byteCount, digest = SHA256()
                while remaining > 0 {
                    if cancelled() { throw DocumentError.cancelled }
                    let bytes = try readExactly(min(remaining, 1024 * 1024), from: input)
                    remaining -= UInt64(bytes.count); digest.update(data: bytes); try output.write(contentsOf: bytes)
                }
                let sha = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard sha == entry.sha256, (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw DocumentError.corrupt("Média modifié pendant l’export") }
            }
            try output.synchronize(); try output.close()
            if cancelled() { throw DocumentError.cancelled }
            guard rename(temporary.path, destination.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        } catch { try? output.close(); throw error }
    }
    static func importPackage(from source: URL, into store: ProjectStore, cancelled: () -> Bool = { false }, limits: Limits = .init()) throws -> ProjectDocument {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        guard try readExactly(8, from: input) == magic else { throw DocumentError.corrupt("Signature de paquet") }
        let lengthBytes = try readExactly(8, from: input)
        let headerLength = lengthBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard headerLength > 0, headerLength <= limits.maximumHeaderBytes else { throw DocumentError.invalid("Taille de manifeste") }
        let header = try JSONDecoder().decode(Header.self, from: readExactly(headerLength, from: input))
        try validate(header: header, limits: limits)
        let fm = FileManager.default, importID = UUID()
        let staging = store.rootURL.appendingPathComponent(".Import-\(importID.uuidString)", isDirectory: true)
        let installed = store.rootURL.appendingPathComponent("Imports/\(importID.uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var didInstall = false, didSave = false
        defer { try? fm.removeItem(at: staging); if didInstall && !didSave { try? fm.removeItem(at: installed) } }
        var actualBytes: UInt64 = 0
        for entry in header.files {
            if cancelled() { throw DocumentError.cancelled }
            let target = try SafePath.resolve(entry.path, in: staging)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw DocumentError.invalid("Écriture du média") }
            let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
            var remaining = entry.byteCount, digest = SHA256()
            while remaining > 0 {
                if cancelled() { throw DocumentError.cancelled }
                let bytes = try readExactly(min(remaining, 1024 * 1024), from: input)
                remaining -= UInt64(bytes.count); actualBytes += UInt64(bytes.count)
                guard actualBytes <= limits.maximumBytes else { throw DocumentError.invalid("Limite réelle de stockage dépassée") }
                digest.update(data: bytes); try output.write(contentsOf: bytes)
            }
            try output.synchronize(); try output.close()
            guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { throw DocumentError.corrupt("Empreinte média incorrecte") }
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw DocumentError.corrupt("Données supplémentaires non déclarées") }
        if cancelled() { throw DocumentError.cancelled }
        var document = header.document; document.id = UUID(); document.modifiedAt = Date(); document.revision = 0
        for index in document.assets.indices { document.assets[index].relativePath = "Imports/\(importID.uuidString)/" + document.assets[index].relativePath }
        try document.validate()
        try fm.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: installed); didInstall = true
        try store.save(document: document); didSave = true
        return document
    }
    private static func validate(header: Header, limits: Limits) throws {
        guard header.version == 2 else { throw DocumentError.unsupportedVersion(header.version) }
        try header.document.validate()
        guard header.files.count <= limits.maximumFiles, Set(header.files.map(\.path)).count == header.files.count else { throw DocumentError.invalid("Nombre ou doublon de fichiers") }
        var total: UInt64 = 0
        for file in header.files {
            guard SafePath.isRelative(file.path), file.path.hasPrefix("Assets/"), file.sha256.count == 64, file.sha256.allSatisfy({ $0.isHexDigit }), file.byteCount <= limits.maximumBytes else { throw DocumentError.invalid("Entrée de paquet") }
            let sum = total.addingReportingOverflow(file.byteCount)
            guard !sum.overflow, sum.partialValue <= limits.maximumBytes else { throw DocumentError.invalid("Paquet trop volumineux") }; total = sum.partialValue
        }
        let entries = Dictionary(uniqueKeysWithValues: header.files.map { ($0.path, $0) })
        for asset in header.document.assets {
            guard let entry = entries[asset.relativePath], entry.sha256 == asset.sha256 else { throw DocumentError.missing("Média non embarqué ou empreinte différente") }
        }
        guard Set(header.document.assets.map(\.relativePath)) == Set(entries.keys) else { throw DocumentError.invalid("Ressources non référencées") }
    }
    private static func readExactly(_ count: UInt64, from handle: FileHandle) throws -> Data {
        guard count <= 32 * 1024 * 1024 else { throw DocumentError.invalid("Bloc trop volumineux") }
        var result = Data(); result.reserveCapacity(Int(count))
        while result.count < count {
            guard let next = try handle.read(upToCount: Int(count) - result.count), !next.isEmpty else { throw DocumentError.corrupt("Fin de fichier prématurée") }
            result.append(next)
        }
        return result
    }
}
