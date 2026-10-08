import SwiftUI
import UIKit

struct CaptionScopePicker: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        Picker(L("Sous-titres concernés"), selection: $model.captionWholeTrack) {
            Text(L("Ce segment")).tag(false)
            Text(L("Toute la piste")).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("captionScope")
    }
}

struct EditorFont: Identifiable {
    let id: String
    let title: String
    let sample: String
    let category: String
    var font: Font { id == "system" ? .system(size: 18, weight: .bold) : .custom(id, size: 18) }
}

enum EditorFontCatalog {
    static var available: [EditorFont] {
        [
            EditorFont(id: "system", title: "Système", sample: "Votre histoire", category: "Essentiels"),
            EditorFont(id: "AvenirNextCondensed-Heavy", title: "Impact", sample: "VOTRE HISTOIRE", category: "Expressives"),
            EditorFont(id: "Chalkduster", title: "Craie", sample: "Votre histoire", category: "Expressives"),
            EditorFont(id: "MarkerFelt-Wide", title: "Feutre", sample: "Votre histoire", category: "Manuscrites"),
            EditorFont(id: "Noteworthy-Bold", title: "Carnet", sample: "Votre histoire", category: "Manuscrites"),
            EditorFont(id: "SnellRoundhand-Bold", title: "Calligraphie", sample: "Votre histoire", category: "Manuscrites"),
            EditorFont(id: "ArialRoundedMTBold", title: "Arrondie", sample: "Votre histoire", category: "Expressives"),
            EditorFont(id: "Copperplate-Bold", title: "Gravure", sample: "VOTRE HISTOIRE", category: "Expressives"),
            EditorFont(id: "Papyrus", title: "Papyrus", sample: "Votre histoire", category: "Expressives"),
            EditorFont(id: "AmericanTypewriter-Bold", title: "Machine à écrire", sample: "Votre histoire", category: "Essentiels"),
            EditorFont(id: "Georgia-Bold", title: "Éditoriale", sample: "Votre histoire", category: "Essentiels"),
            EditorFont(id: "Georgia", title: "Georgia", sample: "Votre histoire", category: "Essentiels"),
            EditorFont(id: "Menlo-Regular", title: "Code", sample: "Votre histoire", category: "Essentiels"),
            EditorFont(id: "Menlo-Bold", title: "Code gras", sample: "Votre histoire", category: "Essentiels")
        ].filter { $0.id == "system" || UIFont(name: $0.id, size: 18) != nil }
    }
}

struct TextFontPicker: View {
    @Binding var selectedFont: String
    @State private var category = "Toutes"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["Toutes", "Expressives", "Manuscrites", "Essentiels"], id: \.self) { name in
                        Button { category = name } label: {
                            Text(L(name)).font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).frame(height: 32)
                                .background(category == name ? DesignTokens.amber : Color.white.opacity(0.07), in: Capsule())
                                .foregroundStyle(category == name ? DesignTokens.ink : .white)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fontCategory-\(name)")
                        .accessibilityAddTraits(category == name ? .isSelected : [])
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(64)), GridItem(.fixed(64))], spacing: 8) {
                    ForEach(EditorFontCatalog.available.filter { category == "Toutes" || $0.category == category }) { choice in
                        Button { selectedFont = choice.id; UISelectionFeedbackGenerator().selectionChanged() } label: {
                            VStack(spacing: 4) {
                                Text(choice.sample).font(choice.font).lineLimit(1).minimumScaleFactor(0.65)
                                HStack(spacing: 4) {
                                    Text(L(choice.title)).font(.system(size: 10, weight: .medium))
                                    if selectedFont == choice.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                                }.foregroundStyle(selectedFont == choice.id ? DesignTokens.amber : DesignTokens.muted)
                            }
                            .padding(.horizontal, 8).frame(width: 145, height: 64)
                            .background(Color.white.opacity(selectedFont == choice.id ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 9))
                            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(selectedFont == choice.id ? DesignTokens.amber : .white.opacity(0.12), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L(choice.title))
                        .accessibilityIdentifier("fontChoice-\(choice.id)")
                        .accessibilityAddTraits(selectedFont == choice.id ? .isSelected : [])
                    }
                }.padding(.horizontal, 1)
            }.frame(height: 136)
        }
        .accessibilityIdentifier("textFontGallery")
    }
}
