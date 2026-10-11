# Formes : proportions libres — 11 octobre 2026

La poignée de preview utilisait uniquement l’échelle uniforme, verrouillant les proportions. Elle modifie maintenant les deux dimensions indépendamment pour les formes, dans leurs axes locaux même après rotation. Quand une dimension dépasse le canevas source, l’échelle augmente et l’autre axe est compensé pour éviter le rognage du masque. Le centre ne bouge pas.

Dans Effets → Transformer, les formes disposent de Largeur et Hauteur séparées, placées avant Échelle. Les photos et vidéos conservent leur redimensionnement proportionnel. Le moteur de rendu et le format de document existants sont réutilisés.

## Validation

- Compilation réussie lors des tests sur simulateurs iPhone et iPad.
- `testShapeResizeChangesAxesIndependentlyAndSupportsRotationUndo` : dimensions indépendantes, rotation, conservation du centre, sérialisation, validation, undo/redo et canevas vide.
- `testOverlayShapeSelectionFitsBalancedSilhouette` : régression des limites de sélection.
- `testShapeFreeResizeRendersAndExportsWithoutCroppingOrAspectLock` : contrôle des pixels rendus et du MP4 exporté, silhouette élargie sans rognage.
- `testShapePreviewResizesWithoutLockedAspectRatio` : gestes horizontaux/verticaux réels, undo et sliders indépendants ; passé sur les deux simulateurs.
- `testPreviewVideoDragDoesNotShowErrorAndHandlesStayTappable` : régression vidéo, passée sur iPhone.

5 tests distincts validés. La suite complète n’a pas été relancée pour cette correction.

Résultats Xcode :

- iPhone géométrie et premiers gestes : `test_sim_2026-10-11T09-38-11-876Z_pid2186_4a6d154a.xcresult` (3/3).
- iPhone export, gestes + réglages et régression vidéo : `test_sim_2026-10-11T09-39-46-580Z_pid2186_3dffb8ce.xcresult` (3/3).
- iPad gestes + réglages : `test_sim_2026-10-11T09-41-35-263Z_pid2186_f42ae638.xcresult` (1/1).

## Captures

Les dossiers iPhone et iPad contiennent chacun les états largeur libre, hauteur libre et panneau de dimensions. Les fichiers manifest.json associent les noms aux captures. iPhone-first conserve les deux premiers essais réussis.

## Limites

Correction compilée, signée, installée et lancée sur l’iPhone 15 Pro physique le 11 octobre 2026. Les gestes n’ont pas encore été retestés sur appareil physique. Les petits éléments gardent les limites minimales de sélection et les zones tactiles existantes. Les avertissements AVFoundation iOS 27 des tests existants restent présents. Aucun commit effectué.
