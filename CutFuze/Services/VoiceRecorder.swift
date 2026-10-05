import AVFoundation
import Combine
import Foundation
import UIKit

/// Records a durable AAC file. Never monitors the microphone through the speaker.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle, countdown(Int), recording, interrupted(String), finished, failed(String)
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var completedURL: URL?
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var operation = UUID()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func start(at url: URL, countdown: Int = 3) async throws {
        guard recorder == nil, !isCountingDown else { throw VoiceServiceError.busy }
        let currentOperation = UUID()
        operation = currentOperation
        completedURL = nil
        state = .countdown(max(0, min(10, countdown)))
        elapsed = 0
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw VoiceServiceError.microphoneDenied }
            guard operation == currentOperation else { throw CancellationError() }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw VoiceServiceError.destinationExists }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            guard session.isInputAvailable else { throw VoiceServiceError.noMicrophone }
            if countdown > 0 {
                for value in stride(from: min(countdown, 10), through: 1, by: -1) {
                    guard operation == currentOperation else { throw CancellationError() }
                    state = .countdown(value)
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            try Task.checkCancellation()
            guard operation == currentOperation else { throw CancellationError() }
            let newRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ])
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else { throw VoiceServiceError.recordingFailed }
            recorder = newRecorder
            state = .recording
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    self.level = max(0, min(1, pow(10, recorder.averagePower(forChannel: 0) / 20)))
                    self.elapsed = recorder.currentTime
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
        } catch {
            if operation == currentOperation {
                state = error is CancellationError ? .idle : .failed(error.localizedDescription)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            throw error
        }
    }

    private var isCountingDown: Bool {
        if case .countdown = state { return true }
        return false
    }

    @discardableResult
    func stop() -> URL? {
        operation = UUID()
        meterTask?.cancel()
        meterTask = nil
        guard let recorder else {
            if isCountingDown { state = .idle }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return completedURL
        }
        elapsed = max(elapsed, recorder.currentTime)
        let url = recorder.url
        recorder.stop()
        if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 {
            elapsed = max(elapsed, Double(file.length) / file.processingFormat.sampleRate)
        }
        self.recorder = nil
        level = 0
        if elapsed > 0.05 {
            completedURL = url
            state = .finished
        } else {
            try? FileManager.default.removeItem(at: url)
            state = .failed(VoiceServiceError.emptyAudio.localizedDescription)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return completedURL
    }

    func cancel() {
        let url = recorder?.url
        completedURL = nil
        _ = stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        completedURL = nil
        state = .idle
    }

    @objc private func interruption(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .began,
              recorder != nil || isCountingDown else { return }
        _ = stop()
        state = .interrupted(L("Enregistrement interrompu. La prise déjà enregistrée est conservée ; démarrez une nouvelle prise pour continuer."))
    }

    @objc private func enteredBackground() {
        guard recorder != nil || isCountingDown else { return }
        _ = stop()
        state = .interrupted(L("Enregistrement interrompu. La prise déjà enregistrée est conservée ; démarrez une nouvelle prise pour continuer."))
    }

    @objc private func routeChanged(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable,
              recorder != nil else { return }
        _ = stop()
        state = .interrupted(L("Le microphone a été déconnecté. La prise enregistrée est conservée."))
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.recorder?.url == url else { return }
            _ = self.stop()
            if !flag { self.state = .failed(VoiceServiceError.recordingFailed.localizedDescription) }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = self.stop()
            self.state = .failed(error?.localizedDescription ?? VoiceServiceError.recordingFailed.localizedDescription)
        }
    }
}

enum VoiceServiceError: LocalizedError {
    case busy, microphoneDenied, noMicrophone, recordingFailed, emptyAudio, destinationExists
    case noVoice, emptyText, transcriptionUnavailable, transcriptionModelUnavailable, speechDenied, invalidAudio, timedOut
    var errorDescription: String? {
        switch self {
        case .busy: return L("Un traitement audio est déjà en cours.")
        case .microphoneDenied: return L("L’accès au microphone est refusé. Vous pouvez l’autoriser dans Réglages > Confidentialité et sécurité > Microphone.")
        case .noMicrophone: return L("Aucun microphone n’est disponible.")
        case .recordingFailed: return L("L’enregistrement audio n’a pas pu démarrer ou a échoué.")
        case .emptyAudio: return L("Aucun échantillon audio utilisable n’a été produit.")
        case .destinationExists: return L("Un fichier existe déjà à cet emplacement.")
        case .noVoice: return L("Cette voix système n’est pas disponible sur cet appareil.")
        case .emptyText: return L("Saisissez un texte de narration avant de le synthétiser.")
        case .transcriptionUnavailable: return L("La transcription locale n’est pas disponible pour cette langue ou cet appareil. Aucun audio n’a été envoyé à un serveur.")
        case .transcriptionModelUnavailable: return L("Le modèle de langue n’a pas pu être installé. Vérifiez la connexion Internet et l’espace disponible, puis réessayez. L’audio reste sur cet appareil.")
        case .speechDenied: return L("L’autorisation de reconnaissance vocale est refusée. Vous pouvez importer un fichier SRT ou saisir les sous-titres manuellement.")
        case .invalidAudio: return L("Le fichier audio ne contient pas d’échantillons décodables.")
        case .timedOut: return L("Le moteur audio local n’a pas répondu à temps. Réessayez avec un extrait plus court.")
        }
    }
}
