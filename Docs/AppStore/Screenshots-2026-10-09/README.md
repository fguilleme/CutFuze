# CutFuze — Captures App Store / App Store screenshots

24 captures natives : six écrans pour chaque combinaison appareil/langue.
Les PNG sont les originaux XCTest, sans recadrage, redimensionnement, retouche ni fausse interface.

## Séries

| Appareil | Français | English | Taille native portrait |
| --- | --- | --- | --- |
| iPhone 18 Pro Max (simulateur) | [iPhone/fr](iPhone/fr) | [iPhone/en](iPhone/en) | 1320 × 2868 px |
| iPad Pro 13 pouces M5 (simulateur dédié) | [iPad/fr](iPad/fr) | [iPad/en](iPad/en) | 2064 × 2752 px |

Chaque série contient les mêmes six fonctions, numérotées dans l’ordre de présentation conseillé :

| Fichier | Français | English |
| --- | --- | --- |
| 01-montage.png | Montage et timeline multipiste | Multitrack timeline editing |
| 02-texte.png | Sous-titres et polices expressives | Captions and expressive fonts |
| 03-effets.png | Catalogue des effets géométriques | Geometry effects catalogue |
| 04-animation.png | Éditeur des points d’animation | Visual keyframe editor |
| 05-multiformat.png | Export vertical, carré et paysage | Portrait, square and landscape export |
| 06-modeles.png | Prévisualisation d’un modèle original | Original template preview |

Le guide d’optimisation App Store a orienté l’ordre vers les fonctions principales : montage, texte et effets en premier. Aucun classement commercial, résultat de performance ou bénéfice non vérifié n’est ajouté aux images.

## Provenance et contrôles

- Captures réalisées le 9 octobre 2026 sur simulateurs iOS 27, avec CutFuze 1.0.
- Langue de l’application réglée via les arguments système AppleLanguages/AppleLocale, sans sélecteur propre à CutFuze.
- Uniquement les médias originaux du projet de démonstration et du catalogue de modèles CutFuze. Aucun projet personnel ni asset d’une autre application.
- Sur iPad, la preview est agrandie en déplaçant réellement le séparateur existant. Ce réglage d’interface ne modifie pas les médias.
- Heure et batterie uniformisées avec la barre d’état du simulateur. Les éléments système restent ceux du simulateur.
- Dimensions et absence de transparence vérifiées pour chaque PNG. Les deux manifest.json contiennent la provenance XCTest et l’empreinte SHA-256 de chaque image.
- Inspection visuelle des séries livrées : aperçu rendu, langue, sélection, panneaux et courbe d’animation.
- Les formats correspondent aux dimensions portrait listées dans les [spécifications Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- Aucune capture n’a été envoyée à App Store Connect. L’acceptation par Apple n’a pas été testée.

## Tests exécutés

- iPhone : testEnglishAppStoreScreenshots et testFrenchAppStoreScreenshots, réussis.
- iPad : mêmes deux parcours, réussis ; le parcours final vérifie également le redimensionnement de la preview.
- LocalizationTests : quatre tests réussis, dont le nouveau contrôle des exemples de polices et de la catégorie « Toutes / All ».
- Audit de traduction : aucune clé L statique sans traduction anglaise.
- Compilation simulateur réussie. Les premières captures ont permis de corriger des libellés dynamiques non traduits ; les captures livrées sont reprises après correction.

Ces parcours vérifient les interactions nécessaires aux captures. Ils ne remplacent pas une recette complète de toutes les opérations de montage. Le catalogue d’effets est montré sans prétendre avoir validé chaque effet ; l’écran d’export est ouvert sans déclencher l’export. Aucun résultat de relecture Apple Intelligence n’a été inventé pour les simulateurs.

## Reproduire

Les parcours se trouvent dans CutFuzeUITests/AppStoreScreenshotTests.swift. Exécuter cette classe sur le simulateur iPhone ou iPad choisi, sans parallélisation. Ils créent des projets de démonstration : utiliser des simulateurs dédiés, pas un appareil contenant des projets de travail.

Exporter les pièces jointes du résultat Xcode puis copier les PNG sans les modifier :

```sh
xcrun xcresulttool export attachments --path RESULT.xcresult --output-path ATTACHMENTS --filter '*.png'
node Scripts/export-app-store-screenshots.mjs ATTACHMENTS OUTPUT iPhone
# ou : node Scripts/export-app-store-screenshots.mjs ATTACHMENTS OUTPUT iPad
```

## English summary

Six genuine screenshots per device and language, captured from the running app on iOS 27 simulators. Original PNGs are preserved without resizing, cropping or compositing. Only CutFuze's own demo media and templates are used. Dimensions and absence of transparency are validated, and each device manifest records screenshot hashes. UI capture journeys and four localization tests passed. Screenshots have not been uploaded to App Store Connect.
