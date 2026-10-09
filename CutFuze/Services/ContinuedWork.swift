import BackgroundTasks
import UIKit
import Combine

/// User-initiated work only. iOS can reject or expire a request; never promise unlimited runtime.
@MainActor final class ContinuedWork: ObservableObject {
    @Published private(set) var notice: String?
    private var identifier: String?
    private var continued: BGContinuedProcessingTask?
    private var fallback = UIBackgroundTaskIdentifier.invalid
    private var finished = false
    private var fraction = 0.0
    private var onExpiration: (() -> Void)?
    private static var awakeJobs: Set<String> = []

    func begin(title: String, onExpiration: @escaping () -> Void) async {
        finish(success: false)
        finished = false; fraction = 0; notice = nil
        self.onExpiration = onExpiration
        let id = "\(Bundle.main.bundleIdentifier ?? "com.guilleme.CutFuze").continuedProcessing.\(UUID().uuidString)"
        identifier = id
        Self.awakeJobs.insert(id)
        UIApplication.shared.isIdleTimerDisabled = true
        fallback = UIApplication.shared.beginBackgroundTask(withName: title) { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in
                guard let self, self.identifier == id, !self.finished else { task.setTaskCompleted(success: false); return }
                self.continued = task
                task.progress.totalUnitCount = 1_000
                task.progress.completedUnitCount = Int64(self.fraction * 1_000)
                task.expirationHandler = { [weak self] in Task { @MainActor in self?.expire() } }
                self.endFallback()
            }
        }
        guard registered else { unavailable(); return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: AppLocalization.bilingual("Traitement en cours", "Processing"))
        // No GPU entitlement required: exports use the CPU Core Image renderer.
        request.strategy = .fail
        do { try await BGTaskScheduler.shared.submitTaskRequest(request) }
        catch { if identifier == id, !finished { unavailable() } }
    }

    func update(_ value: Double) {
        fraction = max(fraction, min(0.99, max(0, value)))
        continued?.progress.completedUnitCount = Int64(fraction * 1_000)
    }
    func finish(success: Bool) {
        finished = true
        if success { notice = nil }
        if let continued {
            if success { continued.progress.completedUnitCount = continued.progress.totalUnitCount }
            continued.setTaskCompleted(success: success)
        }
        continued = nil
        if let identifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            Self.awakeJobs.remove(identifier)
        }
        identifier = nil
        UIApplication.shared.isIdleTimerDisabled = !Self.awakeJobs.isEmpty
        onExpiration = nil
        endFallback()
    }
    private func unavailable() {
        notice = AppLocalization.bilingual("iOS n’a pas autorisé le traitement prolongé. Gardez CutFuze ouvert ; l’écran restera allumé pendant l’opération.", "iOS did not allow extended processing. Keep CutFuze open; the screen will stay awake during the operation.")
    }
    private func expire() {
        guard !finished else { return }
        notice = AppLocalization.bilingual("iOS a interrompu le traitement en arrière-plan. Revenez dans CutFuze pour le relancer.", "iOS interrupted background processing. Return to CutFuze to restart it.")
        let cancel = onExpiration
        finish(success: false)
        cancel?()
    }
    private func endFallback() {
        if fallback != .invalid { UIApplication.shared.endBackgroundTask(fallback); fallback = .invalid }
    }
}
