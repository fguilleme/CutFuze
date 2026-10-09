import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechFileSynthesizer: ObservableObject {
    @Published private(set) var isWorking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: CheckedContinuation<URL, Error>?
    private var writer: SpeechBufferWriter?
    private var timeout: Task<Void, Never>?
    private var temporaryURL: URL?
    private var destinationURL: URL?
    private var operation = UUID()

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    func synthesize(text: String, voiceIdentifier: String?, rate: Float = AVSpeechUtteranceDefaultSpeechRate, to destination: URL) async throws -> URL {
        guard !isWorking else { throw VoiceServiceError.busy }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceServiceError.emptyText }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw VoiceServiceError.destinationExists }
        let selectedVoice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        guard let selectedVoice, voiceIdentifier == nil || selectedVoice.identifier == voiceIdentifier else { throw VoiceServiceError.noVoice }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".speech-\(UUID().uuidString).caf")
        let currentOperation = UUID()
        operation = currentOperation
        let audioWriter = SpeechBufferWriter(url: temporary)
        writer = audioWriter
        temporaryURL = temporary
        destinationURL = destination
        isWorking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(min(300, max(30, text.count))) * 1_000_000_000)
                    guard !Task.isCancelled, self?.operation == currentOperation else { return }
                    self?.finish(.failure(VoiceServiceError.timedOut))
                }
                synthesizer.write(utterance) { [weak self] buffer in
                    let result = audioWriter.consume(buffer)
                    if let result {
                        Task { @MainActor in
                            guard let self, self.operation == currentOperation else { return }
                            switch result {
                            case .success: self.finish(.success(destination))
                            case .failure(let error): self.finish(.failure(error))
                            }
                        }
                    }
                }
                if Task.isCancelled { cancel() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation = pending else { return }
        pending = nil
        timeout?.cancel()
        timeout = nil
        writer?.close()
        writer = nil
        synthesizer.stopSpeaking(at: .immediate)
        isWorking = false
        var finalResult = result
        if case .success = result, let temporaryURL, let destinationURL {
            do {
                let check = try AVAudioFile(forReading: temporaryURL)
                guard check.length > 0 else { throw VoiceServiceError.emptyAudio }
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            } catch { finalResult = .failure(error) }
        }
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
        destinationURL = nil
        continuation.resume(with: finalResult)
    }
}

/// Serializes writes because speech callbacks are not guaranteed to execute on the main actor.
private final class SpeechBufferWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var file: AVAudioFile?
    private var closed = false
    init(url: URL) { self.url = url }
    func consume(_ buffer: AVAudioBuffer) -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            closed = true
            return .failure(VoiceServiceError.invalidAudio)
        }
        if pcm.frameLength == 0 {
            let hasFrames = (file?.length ?? 0) > 0
            closed = true
            file = nil
            return hasFrames ? .success(()) : .failure(VoiceServiceError.emptyAudio)
        }
        do {
            if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved) }
            try file?.write(from: pcm)
            return nil
        } catch {
            closed = true
            file = nil
            return .failure(error)
        }
    }
    func close() {
        lock.lock()
        closed = true
        file = nil
        lock.unlock()
    }
}

/// Uses only on-device recognition. Unavailable resources cause an error, never a cloud fallback.
@MainActor
final class LocalTranscriber: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double = 0 {
        didSet { progressHandler?(progress, statusMessage == L("Téléchargement du modèle de langue…")) }
    }
    // Report directly rather than relying on SwiftUI updates while the app is backgrounded.
    var progressHandler: ((Double, Bool) -> Void)?
    @Published private(set) var statusMessage: String?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[TranscribedWord], Error>?
    private var timeout: Task<Void, Never>?
    private var cancelled = false
    private var analyzerCancellation: (() -> Void)?
    private var assetInstallationProgress: Progress?
    private var recognitionID = UUID()

    static func supports(locale: Locale) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.supportsOnDeviceRecognition && recognizer.isAvailable
    }

    func transcribe(url: URL, locale: Locale) async throws -> [TranscribedWord] {
        guard !isWorking else { throw VoiceServiceError.busy }
        isWorking = true
        cancelled = false
        progress = 0
        statusMessage = nil
        defer {
            isWorking = false
            progressHandler = nil
            analyzerCancellation = nil
            assetInstallationProgress = nil
            statusMessage = nil
        }
        if #available(iOS 26.0, *), SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let module = SpeechTranscriber(
                locale: supported,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence]
            )
            try await installAssetsIfNeeded(for: module)
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            statusMessage = L("Transcription en cours…")
            progress = 0
            return try await transcribeWithAnalyzer(url: url, transcriber: module)
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw VoiceServiceError.transcriptionUnavailable }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else { throw VoiceServiceError.speechDenied }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CutFuze-Transcription-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await withTaskCancellationHandler {
            let source = try AVAudioFile(forReading: url)
            let format = source.processingFormat
            guard source.length > 0, format.sampleRate > 0 else { throw VoiceServiceError.invalidAudio }
            let total = Double(source.length) / format.sampleRate
            let blockDuration: Double = 45
            let strideDuration: Double = 44
            var start: Double = 0
            var words: [TranscribedWord] = []
            while start < total {
                try Task.checkCancellation()
                if cancelled { throw CancellationError() }
                let end = min(total, start + blockDuration)
                let chunk = folder.appendingPathComponent("block-\(Int(start)).caf")
                let sourceURL = url
                let rangeStart = start
                let rangeEnd = end
                try await Task.detached(priority: .userInitiated) {
                    try Self.copyAudio(source: sourceURL, start: rangeStart, end: rangeEnd, to: chunk)
                }.value
                let found = try await recognize(chunk, using: recognizer)
                // Use half of the one-second overlap from each block. Keep actual recognizer times.
                let acceptedStart = start == 0 ? 0 : start + 0.5
                let acceptedEnd = end == total ? total : end - 0.5
                for var word in found {
                    word.start += start
                    let midpoint = word.start + word.duration / 2
                    if midpoint >= acceptedStart && midpoint < acceptedEnd { words.append(word) }
                }
                try? FileManager.default.removeItem(at: chunk)
                progress = end / total
                if end == total { break }
                start += strideDuration
            }
            return words.sorted { $0.start < $1.start }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        cancelled = true
        assetInstallationProgress?.cancel()
        analyzerCancellation?()
        resolve(.failure(CancellationError()))
    }

    @available(iOS 26.0, *)
    private func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        let modules: [any SpeechModule] = [transcriber]
        let initialStatus = await AssetInventory.status(forModules: modules)
        guard initialStatus != .unsupported else { throw VoiceServiceError.transcriptionUnavailable }
        guard initialStatus != .installed else { return }

        statusMessage = L("Téléchargement du modèle de langue…")
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
                guard await AssetInventory.status(forModules: modules) == .installed else {
                    throw VoiceServiceError.transcriptionModelUnavailable
                }
                return
            }
            assetInstallationProgress = request.progress
            let progressMonitor = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, !self.cancelled else { return }
                    self.progress = min(1, max(0, request.progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            defer { progressMonitor.cancel() }
            try await request.downloadAndInstall()
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw VoiceServiceError.transcriptionModelUnavailable
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VoiceServiceError {
            throw error
        } catch {
            throw VoiceServiceError.transcriptionModelUnavailable
        }
    }


    @available(iOS 26.0, *)
    private func transcribeWithAnalyzer(url: URL, transcriber: SpeechTranscriber) async throws -> [TranscribedWord] {
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw VoiceServiceError.transcriptionUnavailable }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw VoiceServiceError.invalidAudio }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        analyzerCancellation = { Task { await analyzer.cancelAndFinishNow() } }
        let results = Task { @MainActor in
            var words: [TranscribedWord] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                guard !self.cancelled else { throw CancellationError() }
                for run in result.text.runs {
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, let range = run.audioTimeRange else { continue }
                    words.append(.init(text: text, start: range.start.seconds, duration: range.duration.seconds, confidence: Float(run.transcriptionConfidence ?? 0)))
                }
                self.progress = min(1, result.range.end.seconds / duration)
            }
            return words
        }
        var watchdogFired = false
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(90, duration * 3)) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            watchdogFired = true
            results.cancel()
            await analyzer.cancelAndFinishNow()
        }
        defer { watchdog.cancel() }
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                guard !cancelled else { throw CancellationError() }
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                let words = try await results.value
                if watchdogFired { throw VoiceServiceError.timedOut }
                guard !cancelled else { throw CancellationError() }
                progress = 1
                return words
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                if watchdogFired { throw VoiceServiceError.timedOut }
                throw error
            }
        } onCancel: {
            results.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func recognize(_ url: URL, using recognizer: SFSpeechRecognizer) async throws -> [TranscribedWord] {
        guard recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw VoiceServiceError.transcriptionUnavailable }
        let requestID = UUID()
        recognitionID = requestID
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            request.addsPunctuation = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard self?.recognitionID == requestID else { return }
                    if let error { self?.resolve(.failure(error)); return }
                    guard let result, result.isFinal else { return }
                    self?.resolve(.success(result.bestTranscription.segments.map {
                        TranscribedWord(text: $0.substring, start: $0.timestamp, duration: $0.duration, confidence: $0.confidence)
                    }))
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard !Task.isCancelled, self?.recognitionID == requestID else { return }
                self?.resolve(.failure(VoiceServiceError.timedOut))
            }
            if cancelled || Task.isCancelled { cancel() }
        }
    }

    private func resolve(_ result: Result<[TranscribedWord], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        continuation.resume(with: result)
    }

    nonisolated private static func copyAudio(source: URL, start: Double, end: Double, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        input.framePosition = AVAudioFramePosition(start * format.sampleRate)
        let target = min(input.length, AVAudioFramePosition(end * format.sampleRate))
        let output = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { throw VoiceServiceError.invalidAudio }
        while input.framePosition < target {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(Int64(buffer.frameCapacity), target - input.framePosition))
            try input.read(into: buffer, frameCount: count)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }
}
