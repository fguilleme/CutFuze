import AVFoundation
import CoreText
import Foundation

/// Small reproducible fixtures used by integration tests. Generated pixels are the source;
/// measurements in Vision services are always made from the encoded video, never this formula.
enum SyntheticVideoCorpus {
    struct Fixture: Sendable {
        let movieURL: URL
        let audioURL: URL
        let frameCount: Int
        let framesPerSecond: Int
    }

    static func make(in root: URL, rotated: Bool = false, cameraShake: Bool = false) async throws -> Fixture {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let movie = root.appendingPathComponent("\(UUID().uuidString).mp4")
        let audio = root.appendingPathComponent("\(UUID().uuidString).caf")
        let width = 320, height = 180, fps = 30, frames = 60
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_500_000, AVVideoMaxKeyFrameIntervalKey: 15]])
        if rotated { input.transform = .init(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VoiceServiceError.invalidAudio }
        writer.startSession(atSourceTime: .zero)
        do {
            for frame in 0..<frames {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? VoiceServiceError.invalidAudio }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                var optionalBuffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess, let buffer = optionalBuffer else { throw VoiceServiceError.invalidAudio }
                CVPixelBufferLockBaseAddress(buffer, [])
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { CVPixelBufferUnlockBaseAddress(buffer, []); throw VoiceServiceError.invalidAudio }
                context.setFillColor(CGColor(red: 0.07, green: 0.1, blue: 0.15, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.saveGState()
                if cameraShake { context.translateBy(x: CGFloat(sin(Double(frame) * 1.7) * 6), y: CGFloat(cos(Double(frame) * 2.1) * 4)) }
                for column in 0..<10 {
                    for row in 0..<6 {
                        let intensity = CGFloat((column * 31 + row * 19) % 13) / 13
                        context.setFillColor(CGColor(red: 0.15 + intensity * 0.16, green: 0.25 + intensity * 0.13, blue: 0.4, alpha: 1))
                        context.fill(CGRect(x: column * 34 + 3, y: row * 33 + 3, width: 14 + row, height: 11 + column))
                    }
                }
                let x = cameraShake ? 140.0 : 40 + Double(frame) * 2.3
                context.setFillColor(CGColor(red: 1, green: 0.65, blue: 0.12, alpha: 1)); context.fill(CGRect(x: x, y: 68, width: 44, height: 44))
                context.setFillColor(CGColor(gray: 0.06, alpha: 1)); context.fill(CGRect(x: x + 7, y: 75, width: 12, height: 13)); context.fill(CGRect(x: x + 25, y: 91, width: 12, height: 14))
                context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 168, width: 320, height: 12))
                context.restoreGState()
                let text = NSAttributedString(string: String(format: "FRAME %02d  ↑ TOP", frame), attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, 11, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
                context.textPosition = CGPoint(x: 7, y: 8)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
                if frame == 15 || frame == 45 { context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 302, y: 2, width: 16, height: 16)) }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else { throw writer.error ?? VoiceServiceError.invalidAudio }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? VoiceServiceError.invalidAudio }
        } catch { writer.cancelWriting(); try? FileManager.default.removeItem(at: movie); throw error }
        try writeImpulses(to: audio)
        return .init(movieURL: movie, audioURL: audio, frameCount: frames, framesPerSecond: fps)
    }

    private static func writeImpulses(to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096), let channel = buffer.floatChannelData?[0] else { throw VoiceServiceError.invalidAudio }
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        for offset in stride(from: 0, to: 96_000, by: 4096) {
            let count = min(4096, 96_000 - offset)
            buffer.frameLength = AVAudioFrameCount(count)
            for index in 0..<count {
                let sample = offset + index
                let local = sample % 48_000 - 24_000
                channel[index] = (0..<48).contains(local) ? Float(0.75 * sin(2 * Double.pi * Double(local) / 12)) : 0
            }
            try output.write(from: buffer)
        }
    }
}
