import SwiftUI

// Original CutFuze workspace palette. No external fonts or competitor assets.
enum DesignTokens {
    static let paper = Color(hex: "F6F3EE")
    static let ink = Color(hex: "15191F")
    static let panel = Color(hex: "232A33")
    static let amber = Color(hex: "EBA65A")
    static let muted = Color(hex: "89929F")
    static let teal = Color(hex: "A0C9BD")
}
extension Color {
    init(hex: String) {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
enum Strings {
    static let english: [String: String] = [
        "Votre atelier de montage.": "Your editing workshop.", "Projets": "Projects", "Nouveau projet": "New project", "Rechercher un projet": "Search projects", "Tous": "All", "Récents": "Recent", "Collections": "Collections", "Découvrir les exemples": "Explore examples", "Des histoires à vous approprier": "Stories to make your own", "Commencer avec un exemple": "Start with an example", "Créer votre premier projet": "Create your first project", "Vos médias restent sur cet appareil.": "Your media stay on this device.", "Aucun résultat": "No results", "Renommer": "Rename", "Dupliquer": "Duplicate", "Supprimer": "Delete", "Annuler": "Cancel", "Enregistrer": "Save", "Ouvrir": "Open", "Importer un projet": "Import project", "Réglages": "Settings", "Disposition inversée": "Reverse layout", "Confidentialité": "Privacy", "Fermer": "Close", "Titre du projet": "Project title", "Collection": "Collection", "Sans collection": "Unfiled", "Supprimer ce projet ?": "Delete this project?", "Le document sera supprimé. Les originaux partagés sont conservés.": "The document will be deleted. Shared originals are retained.", "Scénario": "Story", "Timeline": "Timeline", "Exporter": "Export", "Bibliothèque": "Library", "Annuler la modification": "Undo edit", "Rétablir": "Redo", "Sauvegardé": "Saved", "Sauvegarde…": "Saving…", "Image": "Image", "Son": "Sound", "Texte": "Text", "Animation": "Animation", "Ajouter": "Add", "Photos et vidéos": "Photos and videos", "Fichiers": "Files", "Texte libre": "Text layer", "Forme": "Shape", "Voix off": "Voiceover", "Synthétiser la narration": "Speak narration", "Générer les sous-titres": "Generate captions", "Sous-titres SRT": "SRT captions", "Scinder": "Split", "Lire": "Play", "Pause": "Pause", "Format actif": "Active format", "Commun": "Shared", "Portée": "Scope", "Réinitialiser": "Reset", "Ajuster": "Fit", "Remplir": "Fill", "Échelle": "Scale", "Rotation": "Rotation", "Opacité": "Opacity", "Horizontal": "Horizontal", "Vertical": "Vertical", "Miroir": "Mirror", "Masque": "Mask", "Fusion": "Blend", "Effets": "Effects", "Intensité": "Amount", "Volume": "Volume", "Muet": "Mute", "Fondu entrant": "Fade in", "Fondu sortant": "Fade out", "Vitesse": "Speed", "Durée": "Duration", "Début": "Start", "Fin": "End", "Texte du calque": "Layer text", "Taille": "Size", "Gras": "Bold", "Couleur": "Color", "Noir": "Black", "Blanc": "White", "Ambre": "Amber", "Menthe": "Mint", "Ancrage": "Anchor", "Projet entier": "Whole project", "Scène sélectionnée": "Selected scene", "Propriétés": "Properties", "Aucun élément sélectionné": "No layer selected", "Sélectionnez une scène ou un calque pour le modifier.": "Select a scene or layer to edit it.", "Ajouter un média": "Add media", "Construisez votre première scène": "Build your first scene", "Déplacer avant": "Move earlier", "Déplacer après": "Move later", "Scinder la scène": "Split scene", "Regrouper avec la suivante": "Group with next scene", "Narration": "Narration", "Note de narration": "Narration draft", "Transition": "Transition", "Comparer les formats": "Compare formats", "Même instant, trois compositions.": "One moment, three compositions.", "Hériter du cadrage commun": "Use shared framing", "Images clés": "Keyframes", "Ajouter un point": "Add keyframe", "Entrée en fondu": "Fade in animation", "Mouvement doux": "Gentle motion", "Retirer les points": "Remove keyframes", "Fichier vidéo": "Video file", "Projet complet": "Complete project", "Résolution": "Resolution", "Cadence": "Frame rate", "Qualité": "Quality", "Formats à exporter": "Formats to export", "Lancer l’export": "Start export", "Annuler l’export": "Cancel export", "Partager": "Share", "Terminé": "Done", "Échec": "Failed", "Préparation…": "Preparing…", "Import…": "Importing…", "Export…": "Exporting…", "Exporter le projet complet": "Export complete project", "Exporter les sous-titres": "Export captions", "Documents et médias inclus. Réouvrable sur un autre appareil.": "Document and media included. Reopen on another device.", "Rien à exporter": "Nothing to export", "Les trois formats partagent les mêmes coupes et le même son.": "All three formats share the same cuts and sound.", "Ressources locales": "Local resources", "Modèles": "Templates", "Utiliser ce modèle": "Use template", "Exemple de 30 secondes": "30-second example", "Arrêter": "Stop", "Enregistrement": "Recording", "Insérer": "Insert", "Langue": "Language", "Transcrire": "Transcribe", "Veuillez sélectionner une vidéo ou une piste audio.": "Select a video or audio track first.", "Erreur": "Error", "OK": "OK", "Précision temporelle": "Precise timing", "Extraire le son": "Extract audio", "Inverser la vidéo (son coupé)": "Reverse video (muted)", "Arrêt sur image": "Freeze frame", "Ordre des couches": "Layer order", "Au premier plan": "Bring forward", "À l’arrière-plan": "Send backward", "Import local depuis Photos ou Fichiers.": "Import locally from Photos or Files.", "Brouillon éditorial : ne modifie pas les enregistrements.": "Editorial draft: does not alter recordings.", "Sous-titres": "Captions", "Lecture de référence": "Reference playback", "Local, sans compte": "Local, no account", "Nouvelle histoire": "New story", "Mettre à jour": "Update", "Remplacer le média": "Replace media", "Zoom temporel": "Timeline zoom", "Aimantation": "Snapping", "Navigation libre": "Free navigation", "Suivre la lecture": "Follow playback", "Le montage continue dans chaque format.": "Your edit continues in every format.", "Informations": "About", "Conservation des médias": "Media retention", "Aucun transfert automatique. Le partage est toujours déclenché par vous.": "No automatic transfers. Sharing is always initiated by you."
    ]
}
struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color = .white
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle()) }.foregroundStyle(tint).accessibilityLabel(L(label))
    }
}
struct FrameMark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 2).frame(width: 11, height: 24)
            RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 2).frame(width: 17, height: 17)
            RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 2).frame(width: 23, height: 13)
        }.foregroundStyle(DesignTokens.amber).accessibilityHidden(true)
    }
}
func timeLabel(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%02d:%02d", s / 60, s % 60)
}
extension View {
    func panel() -> some View { self.padding(12).background(DesignTokens.panel, in: RoundedRectangle(cornerRadius: 14)) }
}
