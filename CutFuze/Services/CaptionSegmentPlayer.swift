import Foundation
import Combine
@preconcurrency import AVFoundation

/// A bounded audition of the existing montage mix; never changes the editor cursor.
@MainActor final class CaptionSegmentPlayer: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var preparing = false
    @Published private(set) var position = 0.0
    @Published private(set) var error: String?
    private var plan: RenderPlan
    private let rootURL: URL
    private var player: AVPlayer?
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var previousSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var sessionOperation: Task<Bool, Error>?
    private var subscriptions: Set<AnyCancellable> = []

    init(plan: RenderPlan, rootURL: URL) {
        self.plan = plan; self.rootURL = rootURL
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).sink { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               AVAudioSession.InterruptionType(rawValue: raw) == .began {
                Task { @MainActor [weak self] in self?.stop() }
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).sink { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                Task { @MainActor [weak self] in self?.stop() }
            }
        }.store(in: &subscriptions)
    }

    static func range(start: MediaTime, end: MediaTime, duration: MediaTime) -> ClosedRange<Double>? {
        let lower = max(0, start.seconds), upper = min(duration.seconds, end.seconds)
        guard start.seconds.isFinite, end.seconds.isFinite, duration.seconds.isFinite, upper > lower else { return nil }
        return lower...upper
    }

    func replacePlan(_ plan: RenderPlan) {
        stop(); player = nil; self.plan = plan; error = nil
    }

    func toggle(id: UUID, start: MediaTime, end: MediaTime) {
        if activeID == id { stop(); return }
        stop(); error = nil
        guard let range = Self.range(start: start, end: end, duration: plan.duration) else {
            error = "Ce segment est en dehors du montage."; return
        }
        let currentRun = UUID(); runID = currentRun
        activeID = id; preparing = true; position = range.lowerBound
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if player == nil {
                    let item = try await AudioComposer.preparePlayerItem(plan: plan, rootURL: rootURL)
                    try Task.checkCancellation()
                    guard runID == currentRun else { return }
                    guard let item else { throw CaptionReviewFailure(message: "Aucun son audible dans ce montage. Vérifiez les pistes et leur volume.") }
                    player = AVPlayer(playerItem: item)
                }
                guard let player else { return }
                player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: range.upperBound, preferredTimescale: 60_000)
                let reached = await player.seek(to: CMTime(seconds: range.lowerBound, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
                try Task.checkCancellation()
                guard runID == currentRun else { return }
                guard reached else { throw CaptionReviewFailure(message: "Impossible de lire le son de ce segment.") }
                _ = try? await sessionOperation?.value
                try Task.checkCancellation()
                guard runID == currentRun else { return }
                let session = AVAudioSession.sharedInstance()
                previousSession = (session.category, session.mode, session.categoryOptions)
                try session.setCategory(.playback, mode: .default)
                let activation = Task { try await Self.activate(session) }
                sessionOperation = activation
                guard try await activation.value else { throw CaptionReviewFailure(message: "Impossible de lire le son de ce segment.") }
                try Task.checkCancellation()
                guard runID == currentRun else { return }
                preparing = false; player.play()
                while !Task.isCancelled, runID == currentRun {
                    if player.currentItem?.status == .failed {
                        throw CaptionReviewFailure(message: "Impossible de lire le son de ce segment.")
                    }
                    let seconds = player.currentTime().seconds
                    if seconds.isFinite { position = min(range.upperBound, max(range.lowerBound, seconds)) }
                    if seconds >= range.upperBound || (player.rate == 0 && seconds >= range.upperBound - 0.01) {
                        position = range.upperBound; stop(); return
                    }
                    try await Task.sleep(for: .milliseconds(30))
                }
            } catch {
                guard !Task.isCancelled, runID == currentRun else { return }
                stop()
                self.error = (error as? CaptionReviewFailure)?.message ?? "Impossible de lire le son de ce segment."
            }
        }
    }

    func stop() {
        runID = UUID(); task?.cancel(); task = nil
        player?.pause(); activeID = nil; preparing = false
        if let previousSession {
            let session = AVAudioSession.sharedInstance()
            self.previousSession = nil
            let previousOperation = sessionOperation
            // Serialize deactivation/restoration before a new audition activates.
            sessionOperation = Task {
                _ = try? await previousOperation?.value
                await Self.deactivate(session)
                try? session.setCategory(previousSession.0, mode: previousSession.1, options: previousSession.2)
                return true
            }
        }
    }

    private static func activate(_ session: AVAudioSession) async throws -> Bool {
        if #available(iOS 27.0, *) {
            return try await session.activate(options: [])
        }
        try session.setActive(true)
        return true
    }

    private static func deactivate(_ session: AVAudioSession) async {
        if #available(iOS 27.0, *) {
            _ = try? await session.deactivate(options: .notifyOthersOnDeactivation)
        } else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
