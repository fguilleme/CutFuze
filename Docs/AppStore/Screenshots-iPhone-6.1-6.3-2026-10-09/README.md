# CutFuze — iPhone 6,1 / 6,3 pouces — FR / EN

Série dédiée à l’emplacement « écrans iPhone de 6,1 ou 6,3 pouces » montré dans App Store Connect.
12 captures fixes PNG natives, en portrait 1206 × 2622 px : six en français et six en anglais.

## Fichiers à importer

- Français : iPhone-6.3/fr/
- English : iPhone-6.3/en/

Importer les six PNG de la langue correspondante, dans cet ordre :

1. 01-montage.png — montage et timeline / editing timeline.
2. 02-texte.png — sous-titres et polices / captions and fonts.
3. 03-effets.png — catalogue géométrique / geometry effects catalogue.
4. 04-animation.png — courbe des points d’animation / keyframe curve.
5. 05-multiformat.png — formats d’export / export formats.
6. 06-modeles.png — modèle original / original template.

L’ordre reprend la présentation des fonctions principales de la première série, conformément au guide d’optimisation App Store utilisé pour les captures.

## Dimensions et provenance

La capture App Store Connect fournie par l’utilisateur distingue :

- Captures fixes : 1179 × 2556 ou 1206 × 2622 px en portrait (dimensions inversées en paysage).
- Vidéos d’aperçu : 886 × 1920 px en portrait, ou 1920 × 886 px en paysage.

Cette archive contient des captures fixes en 1206 × 2622 px, pas des vidéos.
Elles ont été reprises sur un simulateur iPhone 16 Pro dédié, sous iOS 27, sans redimensionner les images du grand iPhone.
Les médias sont uniquement ceux du projet de démonstration et du catalogue original de CutFuze.
La langue de l’app est réglée via AppleLanguages/AppleLocale. Les PNG sont les originaux XCTest, sans retouche, recadrage, composition ni transparence.

Le manifest.json du dossier iPhone-6.3 enregistre les dimensions, l’absence de transparence, la provenance XCTest et les empreintes SHA-256.
Les captures grand iPhone et iPad déjà livrées restent inchangées et sont conservées séparément.

## Vérification

Les deux parcours AppStoreScreenshotTests ont été exécutés sur ce simulateur pour ouvrir les six états, en français et en anglais. Les dimensions PNG sont contrôlées lors de l’export ; les captures finales sont inspectées visuellement.
Le catalogue d’effets est montré sans prétendre valider tous les effets, et l’écran d’export est ouvert sans lancer l’export. Aucune capture n’est envoyée automatiquement à App Store Connect ; la validation d’import par Apple reste à effectuer.

## Reproduction

Après exécution des tests sur un iPhone 16 Pro en portrait :

```sh
xcrun xcresulttool export attachments --path RESULT.xcresult --output-path ATTACHMENTS --filter '*.png'
node Scripts/export-app-store-screenshots.mjs ATTACHMENTS OUTPUT iPhone-6.3
```
