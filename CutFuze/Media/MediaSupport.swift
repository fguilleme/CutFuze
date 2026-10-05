import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import CryptoKit

/// Errors cross task boundaries as values; no silent placeholder frame is substituted.
enum MediaFailure: LocalizedError, Sendable {
    case unreadable(String), unsupported(String), missing(String), rendering(String), export(String), diskSpace
    var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "Média illisible : \(s)"
        case .unsupported(let s): return "Format non pris en charge : \(s)"
        case .missing(let s): return "Média manquant : \(s)"
        case .rendering(let s): return "Rendu impossible : \(s)"
        case .export(let s): return "Export impossible : \(s)"
        case .diskSpace: return "Espace disque insuffisant pour ce traitement."
        }
    }
}

enum MediaFiles {
    static func checkedURL(relativePath: String, root: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\"), !components.contains(".."), !components.contains("") else {
            throw MediaFailure.missing("Chemin de média non relatif")
        }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let result = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard result.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: result.path) else {
            throw MediaFailure.missing(relativePath)
        }
        return result
    }

    static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let block = try file.read(upToCount: 1_048_576), !block.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func checkSpace(at url: URL, bytes: Int64) throws {
        let resource = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = resource?.volumeAvailableCapacityForImportantUsage, available < bytes {
            throw MediaFailure.diskSpace
        }
    }

    static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw MediaFailure.rendering("Création de vignette")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaFailure.rendering("Écriture de vignette") }
    }
}
