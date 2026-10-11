import Foundation
@preconcurrency import AVFoundation

extension MediaTime {
    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
}

struct PreparedAudio: @unchecked Sendable {
    let composition: AVMutableComposition
    let mix: AVMutableAudioMix
    let hasAudio: Bool
}

enum AudioComposer {
    /// Exactly this composition/mix is used by the preview player and the export reader.
    @MainActor static func preparePlayerItem(plan: RenderPlan, rootURL: URL) async throws -> AVPlayerItem? {
        let prepared = try await prepare(plan: plan, rootURL: rootURL)
        guard prepared.hasAudio else { return nil }
        let item = AVPlayerItem(asset: prepared.composition)
        item.audioMix = prepared.mix
        item.audioTimePitchAlgorithm = .spectral
        return item
    }

    private static func preparedDurationIsShorter(_ duration: CMTime, than target: CMTime) -> Bool { duration.isNumeric && CMTimeCompare(duration, target) < 0 }

    @concurrent static func prepare(plan: RenderPlan, rootURL: URL) async throws -> PreparedAudio {
        let composition = AVMutableComposition()
        var entries: [(RenderClip, AVMutableAudioMixInputParameters)] = []
        let candidates = plan.clips.filter { ($0.clip.kind == .audio || $0.clip.kind == .video) && !$0.clip.muted && !$0.clip.reversed && ($0.clip.volume > 0 || $0.clip.keyframes.contains { $0.property == .volume && $0.value > 0 }) }
        for item in candidates {
            try Task.checkCancellation()
            guard let asset = plan.assets.first(where: { $0.id == item.clip.assetID }), asset.hasAudio else { continue }
            let url = try MediaFiles.checkedURL(relativePath: asset.relativePath, root: rootURL)
            let source = AVURLAsset(url: url)
            guard let sourceTrack = try await source.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let available = try await sourceTrack.load(.timeRange)
            let clip = item.clip
            // Linear source-speed curves are integrated by the model. 20 ms segments bound
            // audio retiming approximation; constant speed is a single exact time-scale operation.
            let slice = clip.speedPoints.isEmpty ? max(0.001, item.duration.seconds) : 0.020
            let count = max(1, Int(ceil(item.duration.seconds / slice)))
            var inserted = false
            for index in 0..<count {
                try Task.checkCancellation()
                let start = min(item.duration.seconds, Double(index) * slice)
                let end = min(item.duration.seconds, Double(index + 1) * slice)
                var s0 = TimeMapping.sourceTime(for: .init(seconds: start), clip: clip).cmTime
                var s1 = TimeMapping.sourceTime(for: .init(seconds: end), clip: clip).cmTime
                s0 = CMTimeMaximum(available.start, s0)
                s1 = CMTimeMinimum(CMTimeRangeGetEnd(available), s1)
                guard CMTimeCompare(s1, s0) > 0, end > start else { continue }
                let destination = item.globalStart + MediaTime(seconds: start)
                let sourceRange = CMTimeRange(start: s0, end: s1)
                try track.insertTimeRange(sourceRange, of: sourceTrack, at: destination.cmTime)
                track.scaleTimeRange(CMTimeRange(start: destination.cmTime, duration: sourceRange.duration), toDuration: MediaTime(seconds: end - start).cmTime)
                inserted = true
            }
            guard inserted else { composition.removeTrack(track); continue }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTimePitchAlgorithm = .spectral
            entries.append((item, parameters))
        }
        // A conservative shared gain envelope prevents the sum of full-scale sources
        // exceeding 0.80. It is not advertised as a noise reducer or vocal separation.
        func gain(_ item: RenderClip, _ seconds: Double) -> Double {
            let local = seconds - item.globalStart.seconds
            guard local >= 0, local <= item.duration.seconds else { return 0 }
            let clip = item.clip
            let animationLocal = local + clip.animationOffset.seconds
            let duration = clip.animationDuration?.seconds ?? item.duration.seconds
            var value = item.evaluatedVolume(at: .init(seconds: seconds))
            if clip.fadeIn.seconds > 0 { value *= min(1, max(0, animationLocal / clip.fadeIn.seconds)) }
            if clip.fadeOut.seconds > 0 { value *= min(1, max(0, (duration - animationLocal) / clip.fadeOut.seconds)) }
            // Project audio is treated as music. Scene audio is narration; the shared
            // 100 ms attack / 250 ms release envelope lowers music by 12 dB under it.
            if item.sceneID == nil, clip.kind == .audio {
                var activity = 0.0
                for voice in candidates where voice.sceneID != nil && voice.clip.kind == .audio {
                    let attack = min(1, max(0, (seconds - voice.globalStart.seconds + 0.1) / 0.1))
                    let release = min(1, max(0, (voice.end.seconds + 0.25 - seconds) / 0.25))
                    activity = max(activity, min(attack, release))
                }
                value *= 1 - activity * 0.75
            }
            // Scene crossfades use the same overlap interval as the pictures.
            if let span = plan.scenes.first(where: { $0.id == item.sceneID }), let i = plan.scenes.firstIndex(where: { $0.id == span.id }) {
                if i > 0 {
                    let overlap = plan.scenes[i - 1].transition.duration.seconds
                    if overlap > 0 { value *= min(1, max(0, (seconds - span.start.seconds) / overlap)) }
                }
                if span.transition.duration.seconds > 0 { value *= min(1, max(0, (span.end.seconds - seconds) / span.transition.duration.seconds)) }
            }
            return value
        }
        for (item, parameters) in entries {
            let interval = 0.05
            let count = max(1, Int(ceil(item.duration.seconds / interval)))
            var times = (0...count).map { min(item.end.seconds, item.globalStart.seconds + Double($0) * interval) }
            times += item.clip.keyframes.filter { $0.property == .volume }.map { (item.globalStart + $0.time - item.clip.animationOffset).seconds }
                .filter { $0 >= item.globalStart.seconds && $0 <= item.end.seconds }
            times = Array(Set(times)).sorted()
            func normalized(_ seconds: Double) -> Float {
                let total = entries.reduce(0.0) { $0 + gain($1.0, seconds) }
                return Float(gain(item, seconds) * min(1, 0.80 / max(0.80, total)))
            }
            for index in 1..<times.count {
                let start = times[index - 1], end = times[index]
                let range = CMTimeRange(start: MediaTime(seconds: start).cmTime, end: MediaTime(seconds: end).cmTime)
                parameters.setVolumeRamp(fromStartVolume: normalized(start), toEndVolume: normalized(end), timeRange: range)
            }
        }
        let currentDuration = try await composition.load(.duration)
        if preparedDurationIsShorter(currentDuration, than: plan.duration.cmTime), !entries.isEmpty {
            composition.insertEmptyTimeRange(CMTimeRange(start: currentDuration, end: plan.duration.cmTime))
        }
        let mix = AVMutableAudioMix(); mix.inputParameters = entries.map(\.1)
        return PreparedAudio(composition: composition, mix: mix, hasAudio: !entries.isEmpty)
    }
}
