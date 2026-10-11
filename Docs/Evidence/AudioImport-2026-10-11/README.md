# Menu Audio — 11 octobre 2026

## Changements

- « Importer un audio » est la première entrée du menu Audio. Elle ouvre directement le sélecteur Fichiers, limité aux types audio, avec sélection multiple.
- « Audios déjà importés » ouvre une liste dédiée aux sons du projet, sans les images ni les vidéos. Une commande d’import reste disponible en tête de cette liste, même lorsqu’elle est vide.
- Les anciennes entrées Musique et Effets sonores ouvraient la même bibliothèque générale ; elles sont remplacées par ces deux actions explicites. L’import de musique et d’effets sonores reste possible, ainsi que Voix off et Synthèse vocale.
- Réutiliser une ressource locale conserve son identifiant et son nom : plus de réimport créant une nouvelle ressource. Cette correction s’applique aussi à la bibliothèque générale.
- Le choix de destination, undo/redo et les fonctions de montage existantes sont conservés. Libellés français/anglais suivant la langue de l’appareil.

## Validation exécutée

- Compilation des tests réussie sur simulateurs iPhone 16 Pro et iPad Pro 13 pouces.
- Premier passage iPhone : 7 tests modèle/localisation réussis, un test UI échoué. Son assertion comptait deux clips visibles après un ajout à la fin du montage, hors viewport. Le test vérifie désormais l’ajout à la scène active pour observer les deux clips ; l’ajout en fin de montage reste couvert par CoreTests.
- Relance UI iPhone : 1/1 réussi. Ouverture et annulation du sélecteur depuis le menu et depuis la liste, filtrage audio, sélection d’un son existant, validation de sa destination, apparition dans la timeline sans alerte.
- iPad : 70/70 réussis (65 CoreTests, 4 LocalizationTests et le même parcours UI).
- Test modèle ajouté : réutilisation sans duplication de ressource, destination en fin de montage, undo/redo et identifiant inconnu.
- `git diff --check` réussi.

Résultats sous `/Users/francois/Library/Developer/XcodeBuildMCP/workspaces/CutFuze-b40d000a0964/result-bundles/` :

- `test_sim_2026-10-11T10-10-37-195Z_pid2186_77502979.xcresult` : passage initial.
- `test_sim_2026-10-11T10-13-41-182Z_pid2186_a65cf5b6.xcresult` : UI iPhone final.
- `test_sim_2026-10-11T10-14-33-040Z_pid2186_0d3748dc.xcresult` : iPad et régressions modèle/localisation.

## Captures et limites

Les dossiers iPhone et iPad contiennent chacun cinq captures réelles : menu Audio, sélecteur Fichiers, liste des audios importés, destination et timeline après réutilisation. Les manifestes associent les noms aux PNG. Menu et liste inspectés visuellement sur les deux appareils simulés, sélecteur également sur iPhone.

- Le sélecteur a été ouvert et annulé ; aucun nouveau fichier audio externe n’a été choisi pendant ce parcours UI. La réutilisation d’un audio du projet a bien été exécutée.
- Après la validation simulateur : compilation iOS signée réussie, installation et lancement sur l’iPhone 15 Pro ZAPHODICUS. Aucun parcours UI supplémentaire exécuté sur cet appareil physique.
- La suite média/export et toute la suite UI n’ont pas été relancées pour cette réorganisation du menu.
- Rapport rédigé avant le commit demandé par l’utilisateur.
