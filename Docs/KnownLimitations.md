# Limites connues

État de développement au 5 octobre 2026. Les résultats exécutés sont séparés des possibilités du code dans ValidationReport.md et FeatureMatrix.md.

## Montage et document

- Regroupement de scènes limité aux coupes franches. Une transition interne ne peut pas encore être encapsulée dans une scène ; l’opération est refusée explicitement. Scission trop proche d’un chevauchement également refusée.
- Les captions possèdent une provenance source ; les autres calques sont ancrés à une scène ou au projet, sans rattachement automatique arbitraire à un clip.
- Les keyframes de transformation sont communes. Le cadrage local est composé avec cette animation ; pas de trajectoire de keyframes distincte par format.
- Les couches globales passent après les groupes de scènes. Pas d’intercalage global entre deux couches internes d’une scène.
- Un document v1 de développement est migré et testé. Aucun format historique réel n’existait dans l’application initiale ; aucun import de projet concurrent n’est revendiqué.
- Les originaux partagés sont conservés après suppression d’un projet. Aucun ramasse-miettes n’est encore exposé pour nettoyer les médias orphelins, caches et anciens exports. La suppression complète des données s’effectue en supprimant l’application.

## Média et performance

- Décodage vidéo par AVAssetImageGenerator. Pas de proxies adaptatifs, de filmstrip complet ni de décodage séquentiel optimisé pour garantir une lecture temps réel sur iPhone.
- Caches bornés, mais mémoire maximale, chauffe, énergie, images perdues et latence de scrub sur appareil physique non mesurées. Les durées de simulateur sont des observations de tests, pas des engagements de performance.
- Texte rendu par CoreText ; pas de karaoké mot à mot. Les horodatages réels fournis par la transcription sont conservés par segments, sans précision mot à mot fabriquée.
- Pas de courbes RGB/HSL. Pas de piste d’effets globaux indépendante ; les effets sont attachés aux clips avec leur propre plage et animation d’intensité.
- Audio inversé explicitement muet. Vitesse audio variable approchée par segments de 20 ms avec conservation de hauteur spectrale. Le ducking repose sur l’ancrage voix/scène et musique/projet ; il ne détecte pas sémantiquement une voix.
- Marge de mixage conservatrice : ce n’est pas un limiteur true-peak universel. Pas de réduction de bruit ou séparation vocale.
- SDR Rec.709, conversion vidéo HDR avec API forceSDR ; aucun corpus HDR réel autorisé fourni pour qualifier le résultat. Pas d’export HDR, 120 fps ou ralenti interpolé annoncé.
- Les réglages 4K/HEVC/60 fps sont transmis au véritable encodeur et ses erreurs sont rapportées. Leur prise en charge et vitesse doivent être qualifiées sur les iPhone cibles.
- Import cloud délégué au sélecteur/fournisseur système ; pas de téléchargement iCloud dédié avec estimation de temps. Refus de permissions et cloud indisponible restent à tester sur appareil.

## Analyses et services

- Segmentation de personnes Vision implémentée dans le renderer ; aucun corpus humain autorisé pour cheveux, occultation, mouvement et faible lumière. Ce n’est pas un détourage universel.
- Suivi de région Vision validé sur une vidéo synthétique. Perte ou faible confiance interrompent l’analyse ; pas de reconnaissance d’identité.
- Stabilisation translationnelle validée sur un corpus encodé tremblant. Pas de correction de rotation, rolling shutter ou rupture de plan ; analyse limitée à 60 secondes et recadrage borné.
- Prise microphone, Bluetooth/interruption téléphonique, voix système intelligible et transcription d’une parole réelle non qualifiées sur appareil. Un moteur ou une langue indisponible produit une erreur explicite ; aucun faux texte n’est généré.
- Traduction automatique/bilingue, génération d’images/vidéos, retouche beauté, effets corporels, séparation vocale et interpolateur optique non implémentés : ni modèle autorisé ni corpus de validation intégré. Aucun bouton ne simule ces traitements.
- Marqueurs rythmiques manuels disponibles ; détection automatique non implémentée.

## Interface et recette

- Les tests UI automatisés ne couvrent pas encore toute la séquence exhaustive de la section 23 (trois vidéos + photo via Photos, refus microphone, fournisseur cloud indisponible). La couverture exacte exécutée figure dans ValidationReport.
- Dans l’inspecteur paysage étroit, Ajuster/Remplir peuvent se répartir sur deux lignes ; leur densité typographique reste à améliorer.
- Actions essentielles annotées pour VoiceOver ; une recette exhaustive avec VoiceOver, texte très agrandi et switch control reste à faire sur appareil.
- Aucun iPhone physique utilisé dans cette session. La compilation, la validation et les captures documentées concernent des simulateurs.

## Publication

Nom commercial définitif, droits sur le nom, identité légale de l’éditeur, contact support et URL publique de confidentialité non fournis. Ils bloquent la publication, pas le montage local. Aucune soumission, publication, achat ou envoi automatique n’a été effectué. L’audit interne ne garantit pas l’acceptation Apple.
