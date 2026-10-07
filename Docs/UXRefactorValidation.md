# Validation UX de l’éditeur timeline

Validation réalisée le 7 octobre 2026 sur les simulateurs iPhone 18 Pro et iPhone SE (3e génération), en français. Une interaction correspond à un tap, une sélection système ou un geste continu. Les comptes ci-dessous partent de l’éditeur ouvert, sans élément sélectionné.

| Tâche | Parcours principal | Interactions | Exécution réelle pendant cette passe |
| --- | --- | ---: | --- |
| Importer une vidéo | Médias → Photos et vidéos → choisir → Ajouter | 4 | Revue d’import atteinte et inspectée avec une ressource locale ; confirmation finale volontairement annulée. |
| Couper un clip | sélectionner → positionner la tête → Diviser | 3 | Oui, puis undo exécuté. |
| Supprimer une portion | sélectionner → début → Diviser → fin → Diviser → sélectionner la portion → Plus → Supprimer | 8 | Non, parcours compté mais pas exécuté de bout en bout. |
| Modifier la vitesse | sélectionner → Vitesse → régler | 3 | Panneau compact ouvert et inspecté ; valeur non modifiée. |
| Ajouter une musique | Audio → Musique → choisir → Ajouter | 4 | Non. |
| Enregistrer une voix off | Audio → Voix off → enregistrer → arrêter → Insérer | 5 | Non. |
| Ajouter du texte | Texte → Ajouter du texte | 2 | Édition d’un texte existant exécutée ; création non exécutée. |
| Générer des sous-titres | Texte → Sous-titres automatiques → Transcrire | 3 | Non. |
| Ajouter une transition | Effets → Transition → choisir → enregistrer | 4 | Non. |
| Modifier le format | Format → choisir un format | 2 | Comparaison multi-format ouverte et inspectée ; changement actif non exécuté. |
| Ajouter un overlay | Overlay → source → choisir → Ajouter | 4 | Non. L’ajout d’une forme demande 2 interactions. |
| Exporter | Export → Lancer l’export | 2 | Écran d’export ouvert et inspecté ; encodage non lancé depuis l’UI pendant cette passe. |

## Interactions automatisées effectivement couvertes

- sélection vidéo, texte, audio et désélection, avec mise à jour immédiate de la barre contextuelle ;
- ouverture du panneau compact Vitesse ;
- lecture, pause, split et undo ;
- édition de texte avec clavier sans déplacement vertical de la timeline ;
- ouverture et fermeture du mode Scénario secondaire ;
- comparaison des formats, écran d’export et revue d’import ;
- plein écran du viewer, lecture et fermeture ;
- mêmes états contextuels sur le viewport compact iPhone SE.

## Preuves visuelles

- `Docs/Evidence/UXRefactor-FullUI` : timeline par défaut, sélections contextuelles, vitesse, Scénario, comparaison, export et plein écran ;
- `Docs/Evidence/UXRefactor-iPhoneSE3` : états vidéo, texte et audio sur petit viewport ;
- `Docs/Evidence/UXRefactor-SanitizedImport` : revue d’import après suppression des identifiants générés visibles.

Les fichiers `manifest.json` associent les noms suggérés des captures aux fichiers PNG exportés depuis les résultats XCTest.
