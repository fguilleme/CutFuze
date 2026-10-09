import SwiftUI
import UIKit

struct CaptionReviewSheet: View {
    @ObservedObject var model: EditorModel
    @StateObject private var audition: CaptionSegmentPlayer
    let inputs: [CaptionReviewInput]
    let selectedID: UUID?
    var onApplied: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var wholeTrack = true
    @State private var corrections: [CaptionCorrection] = []
    @State private var reviewed = false
    @State private var isReviewing = false
    @State private var completed = 0
    @State private var total = 0
    @State private var availability: String?
    @State private var reviewError: String?
    @State private var errorStart: MediaTime?
    @State private var errorEnd: MediaTime?
    @State private var task: Task<Void, Never>?
    @State private var runID = UUID()

    init(model: EditorModel, inputs: [CaptionReviewInput], selectedID: UUID?, onApplied: @escaping () -> Void) {
        self.model = model; self.inputs = inputs; self.selectedID = selectedID; self.onApplied = onApplied
        _audition = StateObject(wrappedValue: CaptionSegmentPlayer(plan: model.plan, rootURL: model.rootURL))
    }

    private var targets: [CaptionReviewInput] { wholeTrack ? inputs : inputs.filter { $0.id == selectedID } }
    private var acceptedCount: Int { corrections.filter { $0.accepted }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Apple Intelligence", systemImage: "sparkles").font(.headline)
                    Text(L("Relecture locale du texte : orthographe, grammaire et ponctuation. Les temps et le découpage restent inchangés."))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(L("La relecture ne compare pas les sous-titres à l’audio. Vérifiez les propositions avant de les appliquer."))
                        .font(.caption).foregroundStyle(.secondary)
                    if targets.contains(where: { $0.text != $0.original }) {
                        Text(L("Le brouillon courant est inclus. Il sera enregistré uniquement si vous appliquez sa proposition."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !reviewed {
                        Picker(L("Sous-titres concernés"), selection: $wholeTrack) {
                            Text(L("Ce segment")).tag(false)
                            Text(L("Toute la piste")).tag(true)
                        }.pickerStyle(.segmented).disabled(isReviewing || selectedID == nil)
                            .accessibilityIdentifier("captionReviewScope")
                        if wholeTrack {
                            Text(L("Les fragments sont relus comme des phrases, puis répartis sur les segments existants. Les temps restent inchangés."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let availability {
                        Text(L(availability)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("captionReviewUnavailable")
                        Button(L("Réessayer")) { self.availability = CaptionIntelligence.unavailableReason }
                    } else if isReviewing {
                        ProgressView(value: Double(completed), total: Double(max(1, total)))
                        Text("\(completed) / \(total)").font(.caption.monospacedDigit())
                        Button(L("Arrêter")) { cancelReview() }
                            .accessibilityIdentifier("stopCaptionReview")
                    } else if !reviewed {
                        Button(L("Vérifier les sous-titres")) { startReview() }
                            .disabled(targets.isEmpty).frame(minHeight: 44)
                            .accessibilityIdentifier("startCaptionReview")
                    }
                }
                if let reviewError {
                    Section {
                        Text(L(reviewError)).foregroundStyle(.red).accessibilityIdentifier("captionReviewError")
                        if let errorStart, let errorEnd {
                            Text(L("Passage concerné") + " · " + String(format: "%.2f → %.2f s", errorStart.seconds, errorEnd.seconds))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = audition.error {
                    Section { Text(L(error)).foregroundStyle(.red).accessibilityIdentifier("captionAuditionError") }
                }
                if reviewed {
                    if corrections.isEmpty {
                        Section {
                            Label(L("Aucune correction proposée"), systemImage: "checkmark.circle")
                            Text(L("Aucune modification n’a été appliquée. Une relecture automatique peut laisser passer des erreurs."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("captionReviewNoChanges")
                    } else {
                        Section {
                            ForEach($corrections) { $correction in
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(isOn: acceptance(for: correction.id)) {
                                        Text(String(format: "%.2f → %.2f s", correction.start.seconds, correction.end.seconds))
                                            .font(.caption.monospacedDigit())
                                    }.accessibilityIdentifier("acceptCorrection-\(correction.id)")
                                    Button {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        audition.toggle(id: correction.id, start: correction.start, end: correction.end)
                                    } label: {
                                        Label(L(audition.activeID == correction.id ? (audition.preparing ? "Préparation…" : "Arrêter l’écoute") : "Écouter le segment"),
                                              systemImage: audition.activeID == correction.id ? "stop.fill" : "play.fill")
                                            .font(.caption.weight(.semibold)).frame(minHeight: 44)
                                    }.buttonStyle(.borderless)
                                        .accessibilityIdentifier("listenCaption-\(correction.id)")
                                    Text(L("Avant")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(correction.reviewedText).font(.callout)
                                    Text(L("Proposition")).font(.caption.weight(.semibold)).foregroundStyle(DesignTokens.amber)
                                    TextField(L("Proposition"), text: $correction.replacement, axis: .vertical)
                                        .lineLimit(2...6).textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("captionCorrection-\(correction.id)")
                                }.padding(.vertical, 4)
                            }
                        } header: { Text(L("Corrections à valider")) }
                        footer: {
                            Text(L("Seules les propositions cochées seront appliquées. Vous pourrez annuler en une fois."))
                            if wholeTrack { Text(L("Les raccords entre segments d’une même phrase sont validés ensemble.")) }
                        }
                    }
                    Section {
                        Button(L("Nouvelle vérification")) { audition.stop(); reviewed = false; corrections = []; reviewError = nil; availability = CaptionIntelligence.unavailableReason }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Relecture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Fermer")) { audition.stop(); cancelReview(); dismiss() }.accessibilityIdentifier("closeCaptionReview")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Appliquer")) { apply() }
                        .disabled(!reviewed || acceptedCount == 0 || corrections.contains { $0.accepted && $0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        .accessibilityIdentifier("applyCaptionCorrections")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Terminé")) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear { model.stop(); availability = CaptionIntelligence.unavailableReason }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { audition.stop() }
                if phase == .active, !isReviewing { availability = CaptionIntelligence.unavailableReason }
            }
            .onDisappear { audition.stop(); cancelReview() }
        }.preferredColorScheme(.dark)
    }

    private func cancelReview() {
        runID = UUID(); task?.cancel(); task = nil; isReviewing = false
    }

    private func startReview() {
        audition.stop()
        availability = CaptionIntelligence.unavailableReason
        guard availability == nil else { return }
        let snapshot = targets
        let currentRun = UUID(); runID = currentRun
        isReviewing = true; completed = 0; total = snapshot.count; reviewError = nil; errorStart = nil; errorEnd = nil
        task = Task { @MainActor in
            do {
                let result = try await CaptionIntelligence.review(snapshot, wholeTrack: wholeTrack) { count, _ in
                    if runID == currentRun { completed = count }
                }
                guard !Task.isCancelled, runID == currentRun else { return }
                corrections = result; reviewed = true
            } catch {
                guard !Task.isCancelled, runID == currentRun else { return }
                if let reason = CaptionIntelligence.unavailableReason { availability = reason }
                else if let error = error as? CaptionReviewFailure {
                    reviewError = error.localizedDescription; errorStart = error.start; errorEnd = error.end
                }
                else { reviewError = "La relecture a échoué. Réessayez avec un seul segment. Aucun sous-titre n’a été modifié." }
            }
            isReviewing = false; task = nil
        }
    }

    private func apply() {
        audition.stop()
        do {
            var candidate = model.document
            try CaptionProofreading.apply(corrections, in: &candidate)
            try candidate.validate()
            model.edit(L("Corriger les sous-titres")) { $0 = candidate }
            onApplied(); dismiss()
        } catch { reviewError = error.localizedDescription }
    }

    private func acceptance(for id: UUID) -> Binding<Bool> {
        Binding(get: { corrections.first { $0.id == id }?.accepted ?? false }, set: { accepted in
            guard let selected = corrections.first(where: { $0.id == id }) else { return }
            for index in corrections.indices where corrections[index].id == id || (selected.groupID != nil && corrections[index].groupID == selected.groupID) {
                corrections[index].accepted = accepted
            }
        })
    }
}
