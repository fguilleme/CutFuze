# Notes App Review — brouillon interne

CutFuze est un atelier de montage local pour iPhone. Un document relie l’organisation par scènes, les réglages temporels sur timeline et les mises en page verticales, carrées et paysage. Les textes et coupes sont communs ; les cadrages peuvent varier par format. Les projets contiennent leurs médias et peuvent être transportés.

Aucun compte n’est requis. Le projet « Trente secondes de lumière » est accessible à tous depuis la bibliothèque et ouvre le même éditeur que les projets utilisateur. Ses trois illustrations et son repère sonore de 30 secondes sont produits localement. Ses sous-titres sont écrits pour l’exemple ; ils ne constituent pas une démonstration de reconnaissance vocale.

## Parcours à reproduire

1. Dans la bibliothèque, ouvrir le projet exemple. Vérifier trois scènes, les textes et le repère sonore.
2. Dans Scénario, déplacer une scène ; vérifier que son image et ses sous-titres suivent et que la piste sonore globale garde sa position.
3. Passer en Timeline et ajuster une coupe. Revenir à Scénario ; annuler puis rétablir.
4. Choisir le format Carré, sélectionner une image et modifier son cadrage avec la portée Format actif. Comparer Vertical et Paysage au même instant.
5. Modifier un titre commun, revenir à la bibliothèque, rouvrir le projet et vérifier les mises en page.
6. Exporter les variantes disponibles puis lire chaque fichier. Partager vers Fichiers sans exiger l’accès global à Photos.
7. Exporter le projet complet ; le réimporter comme copie indépendante, modifier et réexporter. Pour une preuve d’autonomie, utiliser aussi un second sandbox sans accès aux fichiers initiaux.
8. Tester un refus microphone et, sur appareil compatible, la transcription locale. Si les ressources manquent, un message remplace le traitement ; aucun audio n’est envoyé à un moteur cloud.

Il s’agit du parcours de recette à exécuter sur le binaire candidat. Les résultats effectivement exécutés, le matériel et les preuves figurent dans `ValidationReport.md` ; cette liste ne transforme pas un test non exécuté en succès.

## Limites à communiquer

Les possibilités de reconnaissance locale dépendent du matériel, de la langue et des ressources système installées. Les voix disponibles sont celles retournées par iOS. La validation d’un enregistrement, d’une interruption téléphonique, d’un changement de route et de la reconnaissance sur voix réelle nécessite un appareil et un échantillon adapté. Le son synthétique de l’exemple n’est pas une voix de test.

Les fonctions avancées non disponibles sont consignées dans `FeatureMatrix.md` et `KnownLimitations.md` ; aucune appartenance à un catalogue propriétaire ou équivalence exhaustive n’est revendiquée. Aucun changement de comportement selon l’identité du testeur n’est implémenté.

Nom commercial définitif, coordonnées du contact App Review, URL support et politique de confidentialité : **à fournir par l’éditeur**. Ne pas envoyer ce brouillon comme dossier final tant que les éléments bloquants de `StoreSubmissionChecklist.md` subsistent.
