import SwiftUI
import UniformTypeIdentifiers

struct LibraryScreen: View {
    @ObservedObject var workspace: WorkspaceModel
    @State private var query = ""
    @State private var collection = ""
    @State private var showImport = false
    @State private var showSettings = false
    @State private var showTemplates = false
    @State private var editing: ProjectDocument?
    @State private var deleting: ProjectDocument?
    private var filtered: [ProjectDocument] { workspace.projects.filter { (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) && (collection.isEmpty || $0.collection == collection) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    HStack { Image(systemName: "magnifyingglass"); TextField(L("Rechercher un projet"), text: $query).textInputAutocapitalization(.never); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") } } }
                        .foregroundStyle(.secondary).padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 10) {
                        Button(action: workspace.create) { Label(L("Nouveau projet"), systemImage: "plus").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 18) }.buttonStyle(.plain).foregroundStyle(.white).background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("newProject")
                        Button { showImport = true } label: { Image(systemName: "square.and.arrow.down").font(.title3).frame(width: 60, height: 58) }.foregroundStyle(DesignTokens.ink).background(.white, in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel(L("Importer un projet"))
                    }
                    if !workspace.projects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                collectionChip(L("Tous"), value: "")
                                ForEach(Array(Set(workspace.projects.map(\.collection).filter { !$0.isEmpty })).sorted(), id: \.self) { collectionChip($0, value: $0) }
                            }
                        }
                        HStack { Text(L("Projets")).font(.title2.bold()); Spacer(); Text("\(filtered.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 22) {
                            ForEach(filtered) { project in
                                Button { workspace.open(project) } label: { ProjectCard(document: project, rootURL: workspace.rootURL) }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                    .contextMenu { Button(L("Renommer"), systemImage: "pencil") { editing = project }; Button(L("Dupliquer"), systemImage: "doc.on.doc") { workspace.duplicate(project) }; Button(L("Supprimer"), systemImage: "trash", role: .destructive) { deleting = project } }
                            }
                        }
                        if filtered.isEmpty { Text(L("Aucun résultat")).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30) }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Créer votre premier projet")).font(.title2.bold())
                            Text(L("Import local depuis Photos ou Fichiers.")).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    exampleCard
                    HStack(spacing: 8) { Image(systemName: "lock.shield"); Text(L("Vos médias restent sur cet appareil.")) }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 16)
                }.padding(22).frame(maxWidth: 900)
            }.frame(maxWidth: .infinity).background(DesignTokens.paper).foregroundStyle(DesignTokens.ink)
                .toolbar(.hidden, for: .navigationBar)
        }
        .overlay { if workspace.busy { ZStack { Color.black.opacity(0.2).ignoresSafeArea(); ProgressView(L("Préparation…")).padding(26).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } } }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.init(exportedAs: "com.guilleme.cutfuze.project"), .data]) { result in switch result { case .success(let url): workspace.importProject(url); case .failure(let error): workspace.error = error.localizedDescription } }
        .sheet(isPresented: $showSettings) { SettingsScreen() }
        .sheet(isPresented: $showTemplates) { TemplatesScreen(workspace: workspace) }
        .sheet(item: $editing) { doc in RenameProjectSheet(document: doc) { title, collection in workspace.update(doc, title: title, collection: collection) } }
        .confirmationDialog(L("Supprimer ce projet ?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button(L("Supprimer"), role: .destructive) { if let doc = deleting { workspace.delete(doc) }; deleting = nil } } message: { Text(L("Le document sera supprimé. Les originaux partagés sont conservés.")) }
        .preferredColorScheme(.light)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { FrameMark(); Text("CutFuze").font(.system(size: 20, weight: .bold, design: .rounded)); Spacer(); Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel(L("Réglages")) }
            Text(L("Votre atelier de montage.")).font(.system(size: 36, weight: .semibold, design: .serif)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(L("Découvrir les exemples").uppercased()).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(DesignTokens.teal); Spacer(); Image(systemName: "sparkles").foregroundStyle(DesignTokens.amber) }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Des histoires à vous approprier")).font(.system(size: 25, weight: .medium, design: .serif)).foregroundStyle(.white)
                    Text(L("Même instant, trois compositions.")).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    RoundedRectangle(cornerRadius: 8).fill(DesignTokens.amber).frame(width: 34, height: 58)
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 6).fill(DesignTokens.teal).frame(width: 34, height: 34); RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.5), lineWidth: 1).frame(width: 55, height: 34) }
                }.padding(.top, 5).accessibilityHidden(true)
            }
            HStack {
                Button(action: workspace.demo) { Label(L("Ouvrir"), systemImage: "play.fill").font(.subheadline.bold()).padding(.horizontal, 18).frame(height: 44).foregroundStyle(DesignTokens.ink).background(DesignTokens.amber, in: Capsule()) }.accessibilityIdentifier("openDemo")
                Spacer()
                Button { showTemplates = true } label: { Label(L("Modèles"), systemImage: "arrow.up.right").font(.subheadline.weight(.medium)).frame(height: 44).foregroundStyle(.white) }
            }
        }.padding(22).background(DesignTokens.ink, in: RoundedRectangle(cornerRadius: 24))
    }
    private func collectionChip(_ title: String, value: String) -> some View { Button { collection = value } label: { Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 15).frame(height: 40).background(collection == value ? DesignTokens.ink : .white, in: Capsule()).foregroundStyle(collection == value ? .white : DesignTokens.ink) }.accessibilityAddTraits(collection == value ? .isSelected : []) }
}
struct ProjectCard: View {
    let document: ProjectDocument
    let rootURL: URL
    @State private var thumbnail: CGImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 17).fill(DesignTokens.panel)
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                    Text(timeLabel(document.duration.seconds)).font(.caption.monospacedDigit().bold()).foregroundStyle(.white).padding(12)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 17))
            }
            .frame(height: 136)
            Text(document.title).font(.subheadline.bold()).lineLimit(1)
            HStack(spacing: 5) { ForEach(document.variants) { variant in Text("\(Int(variant.widthRatio)):\(Int(variant.heightRatio))").font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.horizontal, 5).padding(.vertical, 3).background(.white, in: RoundedRectangle(cornerRadius: 4)) }; Spacer(minLength: 0) }
            Text(document.modifiedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: document.revision) { thumbnail = try? await FrameRenderer().render(plan: .compile(document: document, variantID: document.variants.last?.id), time: .init(seconds: 0.2), rootURL: rootURL, size: CGSize(width: 320, height: 180)) }
    }
}
struct RenameProjectSheet: View {
    let document: ProjectDocument
    let save: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var collection = ""
    var body: some View { NavigationStack { Form { TextField(L("Titre du projet"), text: $title); TextField(L("Collection"), text: $collection) }.navigationTitle(L("Renommer")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Annuler")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L("Enregistrer")) { save(title, collection); dismiss() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) } }.onAppear { title = document.title; collection = document.collection } } }
}
struct SettingsScreen: View {
    @AppStorage("reversedLayout") private var reversed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { Form {
        Section(L("Propriétés")) { Toggle(L("Disposition inversée"), isOn: $reversed) }
        Section(L("Confidentialité")) { Label(L("Local, sans compte"), systemImage: "lock.shield"); Text(L("Aucun transfert automatique. Le partage est toujours déclenché par vous.")); Text(L("Vos médias restent sur cet appareil.")) }
        Section(L("Informations")) { Text("CutFuze · 1.0"); Text(L("Nom de développement provisoire. Aucune affiliation à un autre éditeur.")).font(.footnote) }
    }.navigationTitle(L("Réglages")).toolbar { Button(L("Fermer")) { dismiss() } } } }
}
