import XCTest
@testable import CutFuze

final class LocalizationTests: XCTestCase {
    func testEnglishFrenchAndFallbackPreserveUnknownProjectContent() {
        XCTAssertEqual(AppLocalization.text("Sous-titres", languageCode: "en-US"), "Captions")
        XCTAssertEqual(AppLocalization.text("Sous-titres", languageCode: "fr-FR"), "Sous-titres")
        XCTAssertEqual(AppLocalization.text("Sous-titres", languageCode: "de-DE"), "Captions")
        let authored = "Mon sous-titre personnel : niño, été, village maya."
        XCTAssertEqual(AppLocalization.text(authored, languageCode: "en"), authored)
        XCTAssertEqual(L("Sous-titres"), AppLocalization.text("Sous-titres", languageCode: Bundle.main.preferredLocalizations.first ?? "en"))
    }

    @MainActor func testAllTemplatesAndContextualToolsHaveEnglishTranslations() {
        for template in TemplateCatalog.all {
            for key in [template.name, template.subtitle] + template.sceneTitles {
                XCTAssertNotNil(AppLocalization.english(key), key)
            }
        }
        for tool in VisualTool.allCases { XCTAssertNotNil(AppLocalization.english(tool.rawValue), tool.rawValue) }
        for key in ["Vitesse", "Volume", "Fondu", "Animation", "Modifier", "Style", "Police", "Effets visuels", "Écouter le segment", "Arrêter l’écoute", "Redimensionner l’aperçu et la timeline", "Remplacer"] {
            XCTAssertNotNil(AppLocalization.english(key), key)
            XCTAssertEqual(AppLocalization.text(key, languageCode: "fr"), key)
        }
    }

    func testLocalizedErrorsAndFormatPlaceholders() {
        XCTAssertEqual(DocumentError.invalid("Texte ou bornes du sous-titre").localizedDescription,
                       L("Projet invalide") + " : " + L("Texte ou bornes du sous-titre"))
        XCTAssertEqual(MediaFailure.unreadable("Durée invalide").localizedDescription,
                       L("Média illisible") + " : " + L("Durée invalide"))
        XCTAssertEqual(String(format: AppLocalization.text("Version de projet %d non prise en charge.", languageCode: "en"), 42),
                       "Project version 42 is not supported.")
        XCTAssertEqual(String(format: AppLocalization.text("Média %@", languageCode: "en"), "mon-film.mp4"), "Media mon-film.mp4")
        XCTAssertEqual(CaptionReviewFailure(message: "Une correction ne peut pas être vide.").localizedDescription, L("Une correction ne peut pas être vide."))
    }
}
