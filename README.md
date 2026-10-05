# CutFuze

Éditeur vidéo natif iPhone, local et sans compte. Le nom du projet existant est conservé ; sa disponibilité commerciale n’est pas vérifiée. Le cahier actif est [Docs/ProductSpec.md](Docs/ProductSpec.md).

Le même document est édité par scènes dans **Scénario** et par pistes dans **Timeline**. Les sorties 9:16, 1:1 et 16:9 partagent coupes, textes et audio ; leur cadrage peut être local. Un fichier `.cutlabproject` transporte le document et ses médias dans un stockage indépendant.

## Ouvrir et lancer

1. Ouvrir `CutFuze.xcodeproj` avec Xcode 27.0 ou ultérieur.
2. Choisir le schéma partagé **CutFuze**, un simulateur iPhone iOS 27 et Run.
3. Sur iPhone physique, vérifier Signing & Capabilities avec votre équipe et connecter un appareil compatible. L’équipe et le Bundle ID du projet initial ont été conservés ; aucun profil de distribution n’a été créé.
4. Dans la bibliothèque, **Ouvrir le projet exemple** charge une histoire originale de 30 secondes avec trois scènes, des titres, des captions et un son de référence. Aucun accès Photos n’est nécessaire.

Aucune dépendance tierce à télécharger. SwiftUI/UIKit, AVFoundation, Core Image, Core Text, Vision, Speech et CryptoKit sont fournis par Apple. Les API AVAssetReader/Writer existantes compilent sous SDK 27 avec des avertissements de dépréciation.

## Parcours

- Créer un projet, ajouter plusieurs médias via Photos ou Fichiers, réordonner la sélection puis Insérer.
- Réordonner les scènes ; le menu de chaque scène donne accès aux calques, transitions, narration et opérations de structure.
- Dans Timeline, déplacer la règle pour chercher, pincer pour zoomer, tirer les bords du clip sélectionné pour trimmer et faire glisser son centre pour le déplacer. Le bouton de retour remet la lecture et la timeline au début. Le menu de précision temporelle accepte les valeurs exactes et les courbes de vitesse.
- Choisir le format, sélectionner Image et la portée **Format actif** pour un recadrage local. **Commun** affecte la présentation héritée. Une surcharge existante reste explicite jusqu’à sa réinitialisation.
- Exporter ouvre le choix des variantes, dimensions, cadence, codec et débit. Les MP4 terminés sont relus avant d’être proposés au partage ou à l’enregistrement Photos. L’export du projet complet est dans le même espace.
- Importer un projet depuis la bibliothèque installe une copie autonome avec un nouvel identifiant. Le document source n’est pas remplacé.

## Validation reproductible

```sh
Scripts/run-core-tests.sh
xcrun simctl list devices available
Scripts/validate.sh <UUID_DU_SIMULATEUR>
```

Le deuxième script réalise `xcodebuild clean build`, puis `test` avec la parallélisation désactivée, crée un résultat XCTest daté et en extrait les pièces. Les tests de rendu produisent de vrais MP4. Le test Delivery transporte la démonstration, supprime la racine d’origine, rouvre la copie et réexporte ses trois variantes en 1280 pixels.

Validation livrée : clean build puis55tests réussis,0échec,0ignoré sur iPhone18ProMax Simulator. Recettes UI iPhone18Pro et petit écran SE3 également réussies. Aucun iPhone physique qualifié.

Voir [ValidationReport](Docs/ValidationReport.md) pour les exécutions réellement terminées, les échecs trouvés et les mesures. [FeatureMatrix](Docs/FeatureMatrix.md) distingue UI, document, aperçu et export. [KnownLimitations](Docs/KnownLimitations.md) décrit les écarts au cahier : ce dépôt n’est pas une déclaration de conformité intégrale ni de disponibilité App Store.

## Organisation

- `Core/` : document versionné, temps rationnel, historique transactionnel, retiming, sous-titres et conteneur portable.
- `Media/` : copies durables, vignettes/formes d’onde, moteur d’image partagé, mixage et encodeur vérifié.
- `Services/` : voix, transcription locale conditionnelle, corpus synthétique, modèles, suivi et stabilisation.
- `UI/` : bibliothèque, éditeur, timeline à dessin limité au viewport et inspecteurs.
- `CutFuzeTests/`, `CutFuzeUITests/` : invariants, rendu, transport et parcours réels.
- `Docs/` : architecture, choix de produit, preuves, confidentialité et brouillons de publication.

Les ressources d’exemple et l’icône de développement ont été générées localement. Le fichier utilisateur « Neon Film Ribbon Cut Icon.png » est conservé hors du bundle. Aucun compte, analytics publicitaire, serveur ni SDK distant n’est intégré. Les fournisseurs Photos/Fichiers et les ressources de dictée du système peuvent avoir leurs propres besoins réseau.

## Artefacts de démonstration

[Projet portable](Docs/Evidence/Demo/Trente-secondes.cutlabproject) · [Vidéo verticale](Docs/Evidence/Demo/9x16.mp4) · [Vidéo carrée](Docs/Evidence/Demo/1x1.mp4) · [Vidéo paysage](Docs/Evidence/Demo/16x9.mp4). Les images de contrôle voisines sont extraites des MP4 avec AVFoundation.

```sh
swiftc -parse-as-library Scripts/inspect-exports.swift -o build/inspect-exports
build/inspect-exports Docs/Evidence/Demo/9x16.mp4 Docs/Evidence/Demo/1x1.mp4 Docs/Evidence/Demo/16x9.mp4
```
