# Sous-titres, polices et points d’animation — 8 octobre 2026

## Changements

- Sélection d’un sous-titre : choix partagé « Ce segment / Toute la piste », visible dans la barre contextuelle et dans la liste des sous-titres.
- Le déplacement en preview de toute la piste conserve les écarts entre segments, les cadrages spécifiques aux formats et les trajectoires animées. Un geste correspond à une commande annulable. Les durées ne changent pas.
- Galerie de polices avec véritables aperçus, catégories Expressives / Manuscrites / Essentiels, sélection visible et retour haptique. Même galerie dans Police et dans l’éditeur de sous-titres ; catalogue étendu dans l’inspecteur.
- Polices natives disponibles sur l’appareil : condensée, craie, feutre, carnet, calligraphie, arrondie, gravure, machine à écrire, éditoriale et monospace. Aucun téléchargement, asset propriétaire ni copie des styles de CapCut.
- « Animation → Éditer les points » remplace l’entrée peu explicite « Avancé ». Le formulaire seul devient un éditeur avec aperçu épinglé, choix de propriété, courbe issue du moteur existant, points sélectionnables, temps local du clip et tête de lecture.
- Glisser un point modifie son instant et sa valeur ; le relâchement valide une seule commande. Zoom temporel jusqu’à 8×, défilement horizontal et suivi du curseur lors du scrub.
- Ajouter/enregistrer et supprimer sont accessibles immédiatement sous le graphique ; les réglages précis et l’interpolation restent défilables. Une collision ne remplace pas silencieusement un autre point.

## Composants remplacés et conservés

Les menus de polices restreints et l’ancienne liste de points comme seule représentation ont été remplacés. Le modèle de document, le rendu, les formats, les presets d’entrée/sortie/boucle, les fondus, les interpolations et l’historique sont réutilisés. Les points gardent leur identité et leur domaine temporel après une coupe.

## Parcours courts

- Sous-titre déjà sélectionné : Toute la piste → glisser dans la preview (un tap, un geste).
- Texte déjà sélectionné : Police → choisir une carte (deux taps ; catégorie facultative).
- Élément déjà sélectionné : Animation → Éditer les points (deux taps). Puis tap pour sélectionner, glisser pour déplacer, ou parcourir le temps et Ajouter un point.
- Les valeurs saisies dans les réglages précis sont prévisualisées ; Enregistrer le point les valide. Le glissement d’un point est validé au relâchement.

## Validation réellement exécutée

Appareil physique : iPhone, viewport logique 393 × 852, interface française. Compilations Xcode et tests exécutés sur cet appareil.

- Suite CoreTests : 45 tests exécutés, 44 réussis. L’échec restant est `testPortableProjectSurvivesDeletionOfSourceAndPreservesVariants`, erreur « Chemin hors stockage ». Les sources du stockage/transport n’ont pas été modifiées dans cette passe.
- Nouveaux tests du modèle réussis : déplacement de toute la piste, écarts préservés, trajets animés, formats et annulation unique ; police appliquée à la piste et aux overrides existants ; déplacement d’un point après split avec conversion de format, identité conservée, collisions et hors-clip rejetés, undo/redo.
- Cinq parcours UI réussis : presets/effets existants ; édition de sous-titres et taille en points ; déplacement de la piste et galerie Police ; galerie depuis la liste des sous-titres ; sélection/déplacement de points, zoom, scrub, ajout, suppression et undo/redo.
- L’édition de texte a réellement été exécutée, mais l’iPhone utilisait un clavier matériel : ce passage ne valide pas le recouvrement par le clavier logiciel.

## Captures et corrections visuelles

- `Evidence/VisualEditor-Final/manifest.json` : panneau Police, polices manuscrites, déplacement de piste, sous-titres, presets et effets.
- `Evidence/VisualEditor-Verified/manifest.json` : galerie dans la liste, sélection/déplacement d’un point, ajout d’un point d’opacité après suivi horizontal du curseur.
- `Evidence/KeyframeEditor-Delivery/manifest.json` : dernière version recompilée, test UI complet et test de déplacement/collision du modèle réussis ; axe des valeurs visible après zoom et défilement. Application relancée sur l’iPhone après les tests.
- Captures ouvertes et inspectées. Corrections effectuées : hauteur réellement réservée au panneau Police ; commandes de points hors du formulaire défilant ; zoom pour points rapprochés ; curseur et point sélectionné ramenés dans le champ ; axe des valeurs fixe pendant le défilement.

## Limites

Les polices sont celles installées sur l’appareil, pas une bibliothèque téléchargeable ni une collection de modèles typographiques complets. L’éditeur animé se parcourt par scrub ; il n’ajoute pas un second moteur de lecture. Cette passe n’a pas validé l’iPad, le paysage, Dynamic Type ni toute la suite UI de l’application. Le test de transport mentionné ci-dessus reste à résoudre séparément.
