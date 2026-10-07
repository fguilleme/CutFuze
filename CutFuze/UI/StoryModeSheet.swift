import SwiftUI

struct StoryModeSheet: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSceneEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(model.document.scenes.enumerated()), id: \.element.id) { index, scene in
                        sceneRow(scene, index: index)
                            .draggable(scene.id.uuidString) { Text(scene.title).padding().background(DesignTokens.panel) }
                            .dropDestination(for: String.self) { items, _ in
                                guard let value = items.first, let id = UUID(uuidString: value) else { return false }
                                model.edit(L("Scénario")) { try DocumentEditor.reorderScene(id, to: index, in: &$0) }
                                return true
                            }
                    }
                    if !model.document.globalClips.isEmpty { globalLayers }
                }.padding(16)
            }
            .background(DesignTokens.ink)
            .navigationTitle(L("Scénario"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(L("Vue secondaire du même montage")).font(.caption).foregroundStyle(DesignTokens.muted)
                }
                ToolbarItem(placement: .confirmationAction) { Button(L("Terminé")) { dismiss() }.accessibilityIdentifier("closeStory") }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSceneEdit) { SceneEditSheet(model: model) }
    }

    private func sceneRow(_ scene: Scene, index: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                model.selectScene(scene)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(model.selectedSceneID == scene.id ? DesignTokens.amber : DesignTokens.muted)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(DesignTokens.ink)
                        if let image = model.thumbnails[scene.id] { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                    }.frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(scene.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(String(format: "%.1f s", scene.duration.seconds))
                            ForEach(Array(Set(scene.clips.map(\.kind))).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { Image(systemName: clipSymbol($0)) }
                        }.font(.caption2).foregroundStyle(DesignTokens.muted)
                        if !scene.narration.isEmpty { Text(scene.narration).font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(.plain)
            Menu { sceneMenu(scene, index: index) } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(L("Propriétés")).accessibilityIdentifier("sceneMenu-\(index)")
        }
        .padding(10)
        .background(model.selectedSceneID == scene.id ? DesignTokens.panel : DesignTokens.panel.opacity(0.48), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(model.selectedSceneID == scene.id ? DesignTokens.amber.opacity(0.65) : .clear, lineWidth: 1) }
    }

    @ViewBuilder private func sceneMenu(_ scene: Scene, index: Int) -> some View {
        Button(L("Propriétés"), systemImage: "slider.horizontal.3") { model.selectScene(scene); showSceneEdit = true }
        Menu(L("Calques")) {
            ForEach(scene.clips) { clip in
                Button(model.displayName(for: clip), systemImage: clipSymbol(clip.kind)) {
                    if let rendered = model.plan.clips.first(where: { $0.id == clip.id }) { model.selectClip(rendered); dismiss() }
                }
            }
        }
        Button(L("Déplacer avant"), systemImage: "arrow.up") { model.moveScene(scene.id, by: -1) }.disabled(index == 0)
        Button(L("Déplacer après"), systemImage: "arrow.down") { model.moveScene(scene.id, by: 1) }.disabled(index == model.document.scenes.count - 1)
        Button(L("Dupliquer"), systemImage: "doc.on.doc") { model.edit(L("Dupliquer")) { _ = try DocumentEditor.duplicateScene(scene.id, in: &$0) } }
        Button(L("Scinder la scène"), systemImage: "scissors") {
            let offset = model.playhead - (model.plan.scenes.first { $0.id == scene.id }?.start.seconds ?? 0)
            model.edit(L("Scinder la scène")) { _ = try DocumentEditor.splitScene(scene.id, at: .init(seconds: offset), in: &$0) }
        }
        if index + 1 < model.document.scenes.count {
            Button(L("Regrouper avec la suivante"), systemImage: "rectangle.3.group") {
                let next = model.document.scenes[index + 1].id
                model.edit(L("Regrouper avec la suivante")) { _ = try DocumentEditor.groupScenes([scene.id, next], in: &$0) }
            }
        }
        Button(L("Supprimer"), systemImage: "trash", role: .destructive) { model.edit(L("Supprimer")) { try DocumentEditor.removeScene(scene.id, in: &$0) } }
    }

    private var globalLayers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Projet entier"), systemImage: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(DesignTokens.teal)
            ForEach(model.document.globalClips) { clip in
                Button {
                    if let rendered = model.plan.clips.first(where: { $0.id == clip.id }) { model.selectClip(rendered); dismiss() }
                } label: {
                    HStack { Image(systemName: clipSymbol(clip.kind)); Text(model.displayName(for: clip)).lineLimit(1); Spacer(); Text(timeLabel(clip.duration.seconds)).monospacedDigit() }
                        .font(.caption).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }.padding(12).background(DesignTokens.panel.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
    }
}
