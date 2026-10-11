# Courbes pour les outils visuels — 11 octobre 2026

## Changements

- Les 32 effets photo utilisaient déjà `EffectEditorSheet` et leur courbe d’intensité. Ajout d’un test exhaustif des points, déplacements, interpolation et sérialisation pour chaque effet, ainsi que de la couverture de leur catalogue contextuel.
- Bouton visible **Courbes** dans Transformer, Opacité et Masque, ouvrant le même graphe avec les propriétés pertinentes. Pas de passage obligatoire par Animation.
- Six paramètres de masque animables : largeur, hauteur, positions X/Y, rotation, contour progressif. Les courbes utilisent les points du document existant ; preview, export, découpe, undo/redo et variantes de cadrage sont conservés.
- Transformer propose aussi largeur/hauteur pour les formes. Une pose enregistrée inclut les paramètres d’un masque actif.
- Preview redimensionnable dans l’éditeur d’effets, avec la même poignée UIKit que l’éditeur d’animation. Preview, graphe et réglages défilent ensemble.
- Les raccourcis de fondu ne s’affichent que lorsque l’opacité figure parmi les propriétés éditables.

Le moteur de montage n’est pas réécrit. Aucun effet ou réglage existant n’est supprimé. L’ancien accès indirect aux courbes de présentation et la preview d’effets à hauteur fixe sont remplacés.

## Validation

- Compilation simulateur réussie après les modifications.
- Première compilation arrêtée par la portée `private` de la poignée : le composant est maintenant partagé entre les deux éditeurs ; compilation suivante réussie.
- Suite unitaires/média complète + trois parcours UI sur iPhone : **112/113 réussis**. Le nouveau test de masque exporté échouait lors de l’extraction d’image du MP4 avec la tolérance temporelle par défaut.
- Extraction corrigée pour demander exactement 1 seconde et vérifier également l’instant réel retourné. Relance sur iPad : **66/66 réussis**, comprenant tous les CoreTests, le test de masque rendu/exporté et le parcours des outils visuels.
- Les parcours UI couvrent Transformer, Opacité, Masque, Lissage peau, Bombement, Exposition, ajout de points et redimensionnement de preview. Les régressions Animation et effets créatifs ont également passé sur iPhone. Les 32 effets ne sont pas tous cliqués individuellement en UI : leur support de courbe est testé exhaustivement au niveau modèle, et le test média existant rend tout le catalogue.

110 tests unitaires/média distincts et trois parcours UI validés au fil des exécutions. La suite complète n’a pas été relancée en un seul bloc après la correction du test d’extraction.

Résultats dans `/Users/francois/Library/Developer/XcodeBuildMCP/workspaces/CutFuze-b40d000a0964/result-bundles/` :

- `test_sim_2026-10-11T09-57-39-747Z_pid2186_136c9c8e.xcresult` : exécution complète initiale, incluant l’échec du test d’extraction.
- `test_sim_2026-10-11T10-02-40-801Z_pid2186_c05f3001.xcresult` : relance réussie sur iPad.
- `test_sim_2026-10-11T10-04-43-694Z_pid2186_8989cae0.xcresult` : dernier parcours UI iPhone, 1/1 réussi sur la version finale.

## Captures et limites

Les dossiers iPhone et iPad contiennent les captures réelles des courbes de transformation, opacité, masque, lissage, bombement et exposition. iPhone-final ajoute la version finale et les trois raccourcis Courbes. Les manifestes associent les noms aux PNG. États masque et effet à preview agrandie inspectés visuellement sur les deux tailles.

- Pas de nouvelle installation ni de test sur appareil physique pour ces changements.
- Pour les effets photo, la courbe anime l’intensité. Les paramètres complémentaires comme la couleur ou l’étendue du halo restent des réglages constants.
- Les courbes de masque animent la géométrie, pas le choix discret du type de masque ni son inversion.
- Les avertissements de dépréciation AVFoundation/Vision existants restent présents.
- Aucun commit effectué.
