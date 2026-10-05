# Parcours utilisateur

1. Bibliothèque → Nouveau projet → Ajouter → Photos et vidéos ou Fichiers → ordre des médias → Insérer. L’import copie les originaux dans le stockage durable avant toute insertion. Chaque visuel principal crée une scène. L’audio importé est global par défaut.
2. Scénario → menu d’une scène : propriétés, titre/narration, transition, enfants/calques, déplacer, dupliquer, scinder ou regrouper. Une voix n’est jamais régénérée par modification du brouillon narratif. Regrouper des scènes avec transition interne est refusé explicitement.
3. Timeline → sélection d’un clip → poignées pour raccourcir, tête de lecture par geste sur règle, pincement/slider de zoom, appui long pour déplacer. Les couches gardent leur ancrage ; le changement de scène/projet s’effectue dans Image ou Son. Le menu secondaire ouvre Précision temporelle, vitesse constante/courbe, split, extraction audio, inversion muette, arrêt sur image, suivi/stabilisation selon la sélection.
4. Image → portée Format actif → modifier position/échelle/masque. L’autre format conserve sa présentation. Commun modifie la base sans effacer les surcharges. Réinitialiser en portée locale rétablit l’héritage. Animation commune composée relativement au cadrage local.
5. Texte → corriger le contenu → Mettre à jour. Les mots et les dates restent communs ; taille et placement peuvent être locaux. Import SRT/export SRT-VTT décrivent le temps du montage. La transcription locale nécessite une ressource Speech réellement installée.
6. Son/voix : enregistrement avec compte à rebours, niveau et gestion des interruptions ; écoute référence seulement au casque. Une voix dépassant la scène demande sa prolongation explicite. Audio de scène traité comme narration et musique globale atténuée sous la voix. TTS produit un fichier CAF durable.
7. Exporter → formats, dimensions, cadence, codec et débit → lancer. Tous les fichiers partagent une révision figée. Après relecture technique : lecture du fichier, partage, ajout Photos sur demande. Refus Photos conserve les fichiers. Annulation laisse les fichiers déjà terminés disponibles.
8. Exporter le projet complet → partager le fichier .cutlabproject → Bibliothèque/Importer un projet sur l’appareil destination. Import préparé, intégrité vérifiée, nouvelle identité, sans écraser le projet source. Toutes les présentations sont transportées.
9. Réglages → Disposition inversée pour échanger aperçu/inspecteur en paysage. Retour ferme d’abord le panneau ; une seconde action retourne à la bibliothèque et force la sauvegarde.

Les exemples utilisent exactement ces parcours et ce moteur ; aucun mode évaluateur ou service distant simulé.

## Réglages ajoutés et intégrés

- Ajouter → Canevas : choisir fond uni/image/copie floutée, puis Appliquer. Le réglage appartient au format actif. Le même panneau ajoute4:5 ou le ratio du média original.
- Ajouter → Repères rythmiques : poser un repère au temps courant, le nommer et ajuster son temps. Les repères suivent le projet ; Timeline peut s’y aimanter.
- Texte → Modifier les sous-titres : choisir un segment, corriger texte et temps, scinder en deux textes ou fusionner avec le voisin compatible ; style commun ou par variante.
- Image → icône horloge de l’effet : régler plage et points d’intensité. L’aperçu provient d’un snapshot brouillon ; Appliquer forme une seule commande.
- Animation → Modifier les images clés : parcourir précédent/suivant, choisir propriété/valeur/interpolation, ajouter ou mettre à jour le point ; fondus d’entrée/sortie à durée réglable. Les autres points manuels sont conservés.
