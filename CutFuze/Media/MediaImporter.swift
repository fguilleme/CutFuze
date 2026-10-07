import Foundation
import AVFoundation
import ImageIO
import CoreGraphics

actor MediaImporter {
    static let shared = MediaImporter()

    /// Validates actual image/AV tracks, streams the original into durable storage, then derives caches.
    func importFile(url: URL, to rootURL: URL) async throws -> MediaAsset {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: rootURL.appendingPathComponent("Cache"), withIntermediateDirectories: true)
        let fileSize = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard fileSize > 0 else { throw MediaFailure.unreadable(url.lastPathComponent) }
        try MediaFiles.checkSpace(at: rootURL, bytes: Int64(fileSize) + 16_777_216)
        let digest = try MediaFiles.digest(url)
        let suffix = url.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let relative = "Media/\(digest).\(suffix.isEmpty ? "media" : suffix)"
        let destination = rootURL.appendingPathComponent(relative)
        let newlyCopied = !fm.fileExists(atPath: destination.path)
        if newlyCopied {
            let stage = rootURL.appendingPathComponent("Media/.\(UUID().uuidString).partial")
            defer { try? fm.removeItem(at: stage) }
            fm.createFile(atPath: stage.path, contents: nil)
            let input = try FileHandle(forReadingFrom: url)
            let output = try FileHandle(forWritingTo: stage)
            defer { try? input.close(); try? output.close() }
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: data)
            }
            try output.synchronize()
            try fm.moveItem(at: stage, to: destination)
        }
        do {
            var result = MediaAsset(relativePath: relative, kind: .image, name: url.deletingPathExtension().lastPathComponent, sha256: digest)
            let thumbnail: CGImage?
            if let source = CGImageSourceCreateWithURL(destination as CFURL, nil), CGImageSourceGetCount(source) > 0 {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let rawWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                let rawHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
                let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
                let swaps = (5...8).contains(orientation)
                result.width = swaps ? rawHeight : rawWidth
                result.height = swaps ? rawWidth : rawHeight
                result.duration = .init(seconds: 5)
                thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary)
                guard thumbnail != nil, result.width > 0, result.height > 0 else { throw MediaFailure.unreadable(url.lastPathComponent) }
            } else {
                let asset = AVURLAsset(url: destination)
                guard try await asset.load(.isReadable) else { throw MediaFailure.unsupported(url.lastPathComponent) }
                let duration = try await asset.load(.duration)
                guard duration.isNumeric, duration.seconds > 0 else { throw MediaFailure.unreadable("Durée invalide") }
                result.duration = .init(seconds: duration.seconds)
                let video = try await asset.loadTracks(withMediaType: .video)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                result.hasAudio = !audio.isEmpty
                if let track = video.first {
                    result.kind = .video
                    let naturalSize = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
                    result.width = Int(abs(oriented.width).rounded())
                    result.height = Int(abs(oriented.height).rounded())
                    result.nominalFrameRate = Double(try await track.load(.nominalFrameRate))
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 640, height: 640)
                    generator.dynamicRangePolicy = .forceSDR
                    thumbnail = try await generator.image(at: .zero).image
                } else if !audio.isEmpty {
                    result.kind = .audio
                    thumbnail = nil
                } else { throw MediaFailure.unsupported("Aucune piste vidéo ou audio") }
                if result.hasAudio {
                    let samples = try await waveform(url: destination, bins: 240)
                    try JSONEncoder().encode(samples).write(to: rootURL.appendingPathComponent("Cache/\(result.id.uuidString).waveform.json"), options: .atomic)
                }
            }
            try Task.checkCancellation()
            if let thumbnail { try MediaFiles.writeJPEG(thumbnail, to: rootURL.appendingPathComponent("Cache/\(result.id.uuidString).jpg")) }
            return result
        } catch {
            if newlyCopied { try? fm.removeItem(at: destination) }
            throw error
        }
    }

    /// A bounded sample reader: never holds the audio or movie in memory as one Data value.
    func waveform(url: URL, bins: Int = 240) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaFailure.unreadable("Audio") }
        defer { reader.cancelReading() }
        var peaks = Array(repeating: Float(0), count: max(1, bins))
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(buffer)
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = floats.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { continue }
            let stamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let span = CMSampleBufferGetDuration(sample).seconds
            for (index, value) in floats.enumerated() where value.isFinite {
                let time = stamp + (span.isFinite ? span : 0) * Double(index) / Double(max(floats.count, 1))
                let bin = min(peaks.count - 1, max(0, Int(time / max(duration, 0.001) * Double(peaks.count))))
                peaks[bin] = max(peaks[bin], abs(value))
            }
        }
        if reader.status == .failed { throw reader.error ?? MediaFailure.unreadable("Décodage audio") }
        return peaks
    }
}

extension MediaImporter {
    func thumbnail(asset: MediaAsset, rootURL: URL, maxSize: Int = 320) async throws -> CGImage {
        let url = try MediaFiles.checkedURL(relativePath: asset.relativePath, root: rootURL)
        if asset.kind == .image {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxSize] as CFDictionary) else { throw MediaFailure.unreadable(asset.name) }
            return image
        }
        guard asset.kind == .video else { throw MediaFailure.unsupported("Ce média ne contient pas d’image") }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.dynamicRangePolicy = .forceSDR
        return try await generator.image(at: .zero).image
    }

    /// Produces temporally representative frames for one timeline clip. Sampling is
    /// performed in output time, then mapped back through trims, reverse playback and
    /// speed ramps so the filmstrip matches what the user sees while scrubbing.
    func timelineThumbnails(asset: MediaAsset, clip: Clip, rootURL: URL, sampleCount: Int, maxSize: Int = 180) async throws -> [CGImage] {
        guard asset.kind == .video else {
            return [try await thumbnail(asset: asset, rootURL: rootURL, maxSize: maxSize)]
        }
        let url = try MediaFiles.checkedURL(relativePath: asset.relativePath, root: rootURL)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.dynamicRangePolicy = .forceSDR
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0 / 15.0, preferredTimescale: 60_000)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 15.0, preferredTimescale: 60_000)

        let count = max(1, min(24, sampleCount))
        let outputDuration = max(1.0 / 120.0, TimeMapping.outputDuration(clip: clip).seconds)
        var images: [CGImage] = []
        images.reserveCapacity(count)
        for index in 0..<count {
            try Task.checkCancellation()
            let localSeconds = outputDuration * (Double(index) + 0.5) / Double(count)
            let sourceTime = TimeMapping.sourceTime(for: .init(seconds: localSeconds), clip: clip)
            let safeSeconds = min(max(0, sourceTime.seconds), max(0, asset.duration.seconds - 1.0 / 600.0))
            if let image = try? await generator.image(at: CMTime(seconds: safeSeconds, preferredTimescale: 60_000)).image {
                images.append(image)
            }
        }
        if images.isEmpty { images.append(try await generator.image(at: .zero).image) }
        return images
    }

    func waveform(asset: MediaAsset, rootURL: URL, sampleCount: Int = 240) async throws -> [Float] {
        let url = try MediaFiles.checkedURL(relativePath: asset.relativePath, root: rootURL)
        return try await waveform(url: url, bins: sampleCount)
    }
}
