# Éditeur visuel des effets — 9 octobre 2026

## Changements

- Les effets utilisent le même `KeyframeGraph` que les animations : courbe d’intensité issue de l’interpolation existante, sélection des points, déplacement temps/valeur, scrub, zoom temporel jusqu’à 8× et défilement horizontal.
- Aperçu épinglé et synchronisé ; ajouter/enregistrer et supprimer un point restent près de la courbe. Les autres réglages défilent indépendamment.
- Annuler/rétablir dans le brouillon ; un glissement produit une seule entrée d’historique. La coche applique le brouillon au montage ; la croix le ferme sans appliquer ses modifications.
- Barre supérieure compacte pour ne pas tronquer le nom de l’effet sur l’iPhone testé.

L’ancienne liste numérique de points et son slider de déplacement ont été remplacés par le graphique partagé, sans ajouter une seconde couche d’interface.

## Fonctions conservées

Activation de l’effet, intensité, interpolations, navigation précédent/suivant, suppression des points et de l’effet, limites début/fin et application commune aux formats. Le modèle et le moteur de rendu restent utilisés. L’évaluation de la courbe est séparée du masquage hors plage pour pouvoir éditer même un effet désactivé.

Les points conservent leur identité et leurs coordonnées temporelles après une coupe. Une collision est refusée sans effacer un autre point. Les points hors du domaine du segment restent dans le document mais ne sont pas déplacés accidentellement depuis ce segment.

## Validation réellement exécutée

- Compilations iOS et simulateur réussies ; installation sur iPhone 15 Pro physique, viewport logique 393 × 852, interface française.
- CoreTests : 46 tests exécutés, 45 réussis. Nouveau test réussi : identité, valeurs, interpolation, domaines après split, collisions refusées et undo/redo.
- MediaTests : 11 exécutés, 10 réussis, dont catalogue d’effets, transitions, rendu animé et continuité après split.
- Parcours UI réussis sur l’iPhone : édition des points d’effet, zoom, suppression, annulation/rétablissement, défilement vers la plage, activation et affichage de Début/Fin, annulation de cette activation, application/réouverture et abandon d’un brouillon ; non-régression des points d’animation et du panneau de sous-titres.
- Deux parcours UI également réussis sur simulateur iPhone : éditeurs de points d’animation et d’effet.
- Les assertions attendent les mises à jour effectives de l’accessibilité. Le parcours d’effet vérifie la sélection et crée des points distincts par scrub du graphique, sans supposer que le déplacement simulé d’un slider est exact.

Captures : [point déplacé sur iPhone](Evidence/EffectGraph-Final/4232294D-7672-43B9-A4F6-34472A5B505D.png), [zoom sur iPhone](Evidence/EffectGraph-Final/1416625B-14AA-45EB-84DD-8B6E911161FF.png), [plage après défilement](Evidence/EffectGraph-Final/F916703C-C34C-4E48-9F9C-312DD64CF46F.png), [effet rouvert sur iPhone](Evidence/EffectGraph-Final/FE6984A6-D18B-44A1-B10A-ACDEC9164617.png), [courbe sur simulateur](Evidence/EffectGraph-Simulator/9B3F007F-7A8D-4761-AA39-430839BD3874.png). Inspection effectuée sur les quatre états physiques et les vues du simulateur.

Parcours physique de l’éditeur de points : `Test-CutFuze-2026.10.09_07-40-40-+0200.xcresult`, réussi. Les parcours précédents ont été corrigés lorsqu’ils supposaient des contrôles virtualisés déjà présents ou touchaient le parent d’un interrupteur SwiftUI plutôt que l’interrupteur lui-même.

## Regroupement dans « Effets visuels »

Un seul accès « Effets » ouvre le panneau « Effets visuels ». Aucune nouvelle entrée « Visuel » n’est exposée. Transformer, Opacité, Masque, Beauté, Géométrie, Créatif et Lumière se trouvent au même niveau dans une barre horizontalement défilante, avec des zones tactiles de 44 pt.

Les anciennes entrées indépendantes Ajuster, Transformer et Opacité ainsi que leurs doublons du menu Plus ont été remplacés. Ajuster/Remplir, miroir, échelle, position, rotation et réinitialisation restent disponibles dans Transformer. Les réglages défilent sous une barre épinglée. La sélection de clip réinitialise le panneau ; le changement de section réinitialise son défilement vertical.

Masque expose désormais ses réglages dans la timeline, au lieu d’ouvrir seulement Ajuster : forme, largeur, hauteur, position, rotation, contour progressif et inversion. Les réglages communs ou propres au format conservent le modèle existant ; les familles d’effets restent communes aux formats. Le moteur de rendu n’a pas été modifié pour ce regroupement.

Validation physique additionnelle, `Test-CutFuze-2026.10.09_08-23-52-+0200.xcresult` : quatre tests UI réussis (panneau regroupé et masque, éditeur graphique d’effet, Ajuster/Remplir, familles d’effets et animations), ainsi que le test de rendu masque animé/chroma/blends. Le parcours du panneau vérifie aussi le défilement, la persistance du masque entre sections et son undo. Les tests de sélection contextuelle et de déplacement/poignées de preview réussissent également dans le parcours de non-régression suivant.

Captures obtenues et inspectées sur iPhone physique : [Transformer](Evidence/GroupedVisualEffects/F55D260E-8BEE-4AE2-8745-383B31984F86.png), [Opacité](Evidence/GroupedVisualEffects/E8265D53-B4CD-4C2C-B7C2-0537F5D5C646.png), [Masque après défilement](Evidence/GroupedVisualEffects/7665760F-63EC-4D34-A3EB-33FB898F972B.png), [Géométrie](Evidence/GroupedVisualEffects/D2D52E73-34A6-4A31-850C-8F6316E05FD3.png). La hauteur stable du panneau évite un redimensionnement du viewer à chaque changement de section ; les sections courtes laissent donc de l’espace libre.

Trim et accès à Rotation réussis après correction du geste de test : la poignée doit être réellement dans le viewport (zoom réduit), et le défilement démarre sur un libellé plutôt que sur un slider. Deux essais précédents ont échoué avant cette correction ; aucune assertion n’a été retirée. Résultat réussi : `Test-CutFuze-2026.10.09_08-35-08-+0200.xcresult`. [Capture finale](Evidence/GroupedVisualEffects-TrimFinal/4DCF64E6-FB8E-46E3-ABE3-1D4C87876B38.png).

## Limites

Deux tests de transport de projet échouent avec « Chemin hors stockage » : `testPortableProjectSurvivesDeletionOfSourceAndPreservesVariants` et `testPhotosOnlyThreeVariantsAudioPortableReexport`. Le code de transport/stockage n’a pas changé dans cette passe.

Les premières captures physiques étaient partiellement masquées par une vidéo flottante externe ; les captures finales liées ci-dessus ne le sont plus. L’iPad, Dynamic Type et VoiceOver n’ont pas été qualifiés. Un essai en paysage a révélé un manque de place dans l’éditeur principal ; il ne constitue pas une validation paysage. Cette passe n’ajoute pas de nouveaux types d’effets ni un nouveau moteur de lecture.
