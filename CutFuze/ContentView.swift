import SwiftUI

struct ContentView: View {
    @StateObject private var workspace = WorkspaceModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let editor = workspace.editor { EditorScreen(model: editor, close: workspace.close) }
            else { LibraryScreen(workspace: workspace) }
        }
        .tint(DesignTokens.amber)
        .onChange(of: scenePhase) { _, phase in if phase != .active { workspace.editor?.stop(); workspace.editor?.save() } }
        .onOpenURL { workspace.importProject($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in workspace.editor?.releaseDerivedCaches() }
        .alert(L("Erreur"), isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) { Button(L("OK")) { workspace.error = nil } } message: { Text(workspace.error ?? "") }
        .task { if ProcessInfo.processInfo.arguments.contains("--demo") { workspace.demo() } }
    }
}
