import Foundation
import AVFoundation
import ImageIO

@main struct InspectExports {
    static func main() async throws {
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let video = tracks.first else { fatalError("Missing video: \(path)") }
            let duration = try await asset.load(.duration).seconds
            let size = try await video.load(.naturalSize), fps = try await video.load(.nominalFrameRate)
            let audio = try await asset.loadTracks(withMediaType: .audio).count
            print("\(url.lastPathComponent): \(Int(size.width))x\(Int(size.height)), \(fps) fps, \(duration) s, \(audio) audio track")
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            for second in [1.5, 14.0, 28.0] {
                let image = try await generator.image(at: CMTime(seconds: min(second, duration / 30 * second), preferredTimescale: 60000)).image
                let output = url.deletingPathExtension().appendingPathExtension("\(second)s.png")
                let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write control image") }
            }
        }
    }
}
