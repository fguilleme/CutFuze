# Audio, courbes et formes — 11 octobre 2026

## Changements

- Vitesse : les raccourcis utilisent une commande validée et annulable. La durée du segment s’adapte à la vitesse et à sa plage source visible ; les fondus sont bornés. Un audio ralenti peut traverser une scène sans déplacer les images suivantes.
- Le panneau Vitesse dispose de la hauteur nécessaire : le bouton ×2 n’est plus partiellement hors de la zone interactive. Le test vérifie effectivement la vitesse 2×.
- Volume : éditeur de courbe par segment, points, interpolation, undo/redo et écoute bornée du segment. Le mix audio commun à la preview et à l’export évalue la courbe, y compris lorsque le volume de base est nul. Effacer l’animation visuelle ne supprime pas les points de volume.
- Animation et effets : aperçu, courbe et réglages défilent ensemble. Le bloc d’aperçu figé des effets a été remplacé. La poignée de redimensionnement de la preview des animations est un contrôle UIKit qui conserve son geste sans voler le défilement ailleurs.
- Texte : retrait du raccourci manuel « Sous-titres » redondant. Texte libre, génération automatique, import SRT et édition des sous-titres existants sont conservés.
- Overlay → Forme : sélecteur illustré pour ellipse, rectangle, rectangle arrondi, nuage, étoile et cœur. L’action Forme permet ensuite de remplacer la silhouette. Les nouvelles formes démarrent avec des proportions équilibrées ; leur cadre de sélection tient compte des dimensions d’un masque centré. Les tuiles du sélecteur ont une largeur limitée sur iPad.

Le document, les pistes, le moteur de rendu, le mix audio et l’architecture multi-format sont réutilisés. Les formes nuage/étoile/cœur réutilisent les tracés vectoriels des fonds de texte.

## Validation exécutée

Compilation simulateur et compilation signée `generic/platform=iOS` : succès.

105 tests unitaires/média distincts validés sur les différents runs : 104 dans le run complet iPad, puis le nouveau test de géométrie de sélection sur iPhone. Cinq parcours UI ont passé sur chacun des simulateurs iPhone 16 Pro et iPad 13 pouces :

1. vitesse ×2, création d’un point de volume, écoute et défilement complet des effets ;
2. menu Texte simplifié et ajout d’un texte ;
3. agrandissement puis réduction de la preview des courbes ;
4. régression des courbes et réglages Rêve, Balayage lumineux et Déformation liquide ;
5. ajout d’un cœur puis remplacement par un nuage.

Le sélecteur iPad a été retesté après sa réduction de largeur : succès.

Les tests média exécutent réellement la préparation, la lecture bornée et l’export d’un audio de 0,12 s à ×2. Un autre export est décodé pour vérifier la variation de niveau produite par la courbe. Les six silhouettes sont rendues et distinctes ; nuage, étoile et cœur sont exportés en MP4 puis décodés. Codec du projet, source audio, interpolation, split et undo/redo sont également vérifiés.

Les premiers runs UI ont révélé un conflit de redimensionnement, une sélection ambiguë du bouton Fermer et des gestes de test dépassant les réglages. Ces échecs ont été corrigés et les parcours concernés réexécutés. Une erreur de nom du codec dans le nouveau test a été corrigée avant sa validation.

Résultats Xcode sous `/Users/francois/Library/Developer/XcodeBuildMCP/workspaces/CutFuze-b40d000a0964/result-bundles/` :

- suite complète iPad : `test_sim_2026-10-11T09-14-25-893Z_pid2186_b0916861.xcresult` — 109/109 ;
- géométrie et formes finales iPhone : `test_sim_2026-10-11T09-18-00-281Z_pid2186_20589299.xcresult` — 2/2 ;
- sélecteur iPad final : `test_sim_2026-10-11T09-20-02-886Z_pid2186_6d282eaa.xcresult` — 1/1 ;
- audio/défilement iPhone : `test_sim_2026-10-11T09-10-00-749Z_pid2186_5090393e.xcresult` — parcours concerné passé ;
- redimensionnement iPhone corrigé : `test_sim_2026-10-11T09-12-58-109Z_pid2186_2ffe7dc9.xcresult` — 1/1 ;
- régression des effets et menu Texte iPhone : `test_sim_2026-10-11T09-04-40-700Z_pid2186_0eedaf6c.xcresult` — ces deux parcours passés.

## Captures et exports conservés

15 captures UI réelles : 8 dans `iPhone/`, 7 dans `iPad/`. Elles montrent le sélecteur, une forme sélectionnée, la courbe de volume, les réglages après défilement, la preview agrandie/réduite et le menu Texte. Les principaux états ont été inspectés visuellement ; les proportions des formes, le cadre de sélection et la largeur des tuiles iPad ont été corrigés à cette occasion.

`Media/` contient trois rendus de silhouettes et deux MP4 produits par les tests : `volume-curve.mp4` et `short-audio-double-speed.mp4`.

## Limites

- Version installée et lancée sur l’iPhone 15 Pro physique le 11 octobre 2026. Les interactions ont été validées sur simulateurs, mais pas encore retestées sur appareil physique.
- Les tests valident la lecture et le niveau audio, pas une appréciation humaine de la qualité sonore.
- Les fondus Entrée/Sortie et la liste des points restent présents dans l’éditeur visuel. Leur allègement en presets externes et liste repliable a été proposé, mais n’est pas implémenté dans ce lot.
- Des avertissements de dépréciation AVFoundation/Vision sous iOS 27 subsistent.
