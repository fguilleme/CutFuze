# Rapport de validation

Exécutions réelles du 5 octobre 2026, Xcode27.0 (27A266a), SDK/runtime iOS27.0, arm64 sur simulateur. Aucun appareil physique utilisé. Les résultats XCTest locaux sont sous `build/` (ignoré par Git) ; les résumés, pièces, captures et exports sélectionnés sont sous `Docs/Evidence/`.

## État final

**Clean build réussi, puis55tests PASS,0FAIL,0SKIP**, en140,462s, sur iPhone18ProMax Simulator, iOS27. Résultat : `build/ReleaseCandidateValidation.xcresult`. Résumé exporté : `Evidence/release-summary.json`. Derniers journaux : `Evidence/latest-clean-build.log` et `Evidence/latest-tests.log`.

Répartition :29CoreTests,11MediaTests,6VisionTests,3BeatMarkerTests,2ServiceTests,1CanvasTests,1TextRenderingTests,1DeliveryTests et1WorkspaceUITests. La dernière suite inclut l’aperçu fixé dans les panneaux d’édition. Aucun code produit changé depuis cette passe.

Les captures SE3 et18Pro proviennent des passes UI précédentes ; le ProMax porte la dernière UI.22avertissements de compilation liés aux API dépréciées SDK27 subsistent. La dernière suite signale aussi une inversion QoS lors du test d’orientation AVFoundation : test passé, optimisation des priorités restant à examiner ; aucune erreur masquée.

## Exécutions intermédiaires

| Résultat | Périmètre | Résultat réel |
|---|---|---|
| FirstValidation.xcresult | Noyau/média/services initiaux | 28 PASS,0FAIL |
| SecondValidation.xcresult | Noyau23/média8/services2/Vision2 | 35 PASS,0FAIL,31,3s |
| VisionFinalValidation.xcresult | Corpus,tracking,stabilisation et variantes | 5 PASS,0FAIL,29,1s |
| DeliveryValidation.xcresult | Démonstration longue + UI | UI PASS,export FAIL |
| DeliveryValidation3.xcresult | Marqueurs/canevas/export30s | 3 PASS,2FAIL |
| DeliveryValidation4.xcresult | Canevas,transport+3exports30s,UI élargie | 3 PASS,0FAIL,138,0s |
| CompactUIValidation.xcresult | Même parcours UI sur iPhone SE3 dédié | 1 PASS,0FAIL,151,1s (inclut démarrage du simulateur) |
| FinalValidation.xcresult | Suite globale sur code final | 54 PASS,1FAIL UI,136,9s ; échec explicité ci-dessous |
| FinalUIValidation.xcresult | UI finale avec défilement captions | 1 PASS,0FAIL,83,1s |
| LargeUIValidation.xcresult | UI précédente sur iPhone18ProMax | 1 PASS,0FAIL,68,3s |
| ReleaseCandidateValidation.xcresult | Clean build puis toutes les suites finales | **55 PASS,0FAIL,0SKIP,140,462s** |
| Scripts/run-core-tests.sh | Noyau Foundation sur macOS | 29 PASS,0FAIL ; journal conservé |

Une suite passée ne prouve pas une fonction non exercée. Les tests natifs macOS ne remplacent pas les tests iOS.

## Trois signatures

1. **Scénario et Timeline** : CoreTests vérifie que le réordre transporte les enfants, laisse la musique globale à son temps, conserve les surcharges, et qu’undo/redo restaure la transaction entière. Les splits, regroupements à coupe franche, vitesse, captions et migrations sont testés. Le test UI réordonne une scène par son menu, annule, bascule Timeline, recadre, annule/rétablit, pivote et rouvre le projet.
2. **Variantes** : le noyau teste l’isolation de la présentation carrée et la propagation du contenu/temps communs. Les tests média encodent et relisent9:16,1:1,16:9. L’animation commune est composée sur les cadrages locaux. Comparateur réel capturé. Pas de keyframes locales distinctes.
3. **Transport** : paquet exporté, source supprimée, import dans une nouvelle racine, titre modifié, sauvegarde/réouverture et réexport des trois formats. Les tests refusent empreinte fausse, fichier tronqué, chemin traversant/absolu, liens et dépassement de limites. La démo30s utilise ces mêmes chemins.

## Mesures

- Démonstration originale : trois scènes, titres/captions, repère sonore48kHz. Trois MP4 H.264,30fps,720×1280,1280×1280 et1280×720 ; chacun30s, piste audio présente, images décodées à1,5/14/28s. Le lot depuis le projet transporté a pris56,3657s dans DeliveryValidation4, puis55,4852s dans FinalValidation et55,2270s dans la dernière ReleaseCandidateValidation. [Fichiers](Evidence/Demo/) ; aucune extrapolation vers iPhone physique.
- Dernier pic mono décodé dans ReleaseCandidateValidation :0,928899≤1. Les repères A/V restent aux mêmes instants ; aucune saturation détectée sur ce corpus.
- Synchronisation initiale après coupes et vitesses1×/2×/0,5× : repères0,1/0,5/0,8s ; pics audio0,109854167/0,495125/0,812583333s. Erreurmax12,584ms <33,333ms (une image30fps). Les courbes audio arbitraires ne sont pas qualifiées par cette seule mesure.
- Stabilisation : mesures dans les pixels du vrai FrameRenderer, RMS4,0983→0,6111px, ratio0,1491 ; crop1,05263. Les MP4 ont aussi été rouverts par AVFoundation macOS ; les contrôles1,5/14/28s sont dans Evidence/Demo, les images14s verticales/paysage ont été inspectées. Le shell sandboxé bloquait le service de décodage ; la même commande autorisée hors sandbox a réussi.
- Un outlier Vision sur texture périodique est détecté par comparaison photométrique réelle. [Pièces](Evidence/Vision/).
- Suivi :20observations, confiance min0,771 sur objet mobile encodé. Pas de corpus humain inventé.
- Premier microbenchmark :15images synthétiques360×640 en0,023188s. Ce n’est pas un benchmark de décodage vidéo ni de fluidité matérielle.
- Démarrage/latence de scrub/images perdues/mémoire maximale/thermique : non mesurés précisément ; aucune valeur commerciale déduite des durées des tests.

## Défauts observés et corrections

- Test UI initial : retour « Fermer » ambigu et menu imbriqué dans une carte-bouton ; zones interactives séparées, identifiants précis. Anciennes captures/échecs conservés dans FirstUI et UI5.
- Capture de rotation prise pendant l’animation : attente de fin de rotation ajoutée. Capture paysage réelle inspectée ensuite.
- Stabilisation : corrélation Vision erronée avec confiance1 sur mire répétitive. Ajout d’un contrôle photométrique et d’une recherche locale bornée ; le test d’amélioration dans les pixels a ensuite réussi sans diminuer son seuil.
- Surcharge locale et animation : risque de double application du cadrage pour suivi/stabilisation ; inversion vers le domaine commun corrigée et tests ajoutés.
- Export long : blocage après environ30s, puis erreur de suppression temporaire trompeuse. Ancienne boucle attendait l’audio avant d’alimenter l’image ; nouvelle pompe sert les deux entrées prêtes, conserve une quantité bornée d’échantillons et ne déclare un blocage qu’en absence de progression des deux. Le lot complet30s×3 passe après correction. Installation finale par rename POSIX atomique, ancien fichier conservé si l’installation échoue.
- Pic AAC initial1,10068 après downmix mono : marge conservatrice réduite0,95→0,80, assertion pic≤1 ajoutée. Dernière mesure0,9284009≤1 ; test passé ; pas de revendication de limiteur true-peak universel.
- Test de fond flouté : mesure au pixel extrême influencée par le bord interpolé (229/255) ; contrôle déplacé de5px à l’intérieur de la zone de fond, seuil couleur inchangé. Test canevas désormais PASS, fond visible aux trois modes et export réel.
- Aperçu dans les feuilles : les captures ont montré que le preview disparaissait au défilement. Il est maintenant fixé au-dessus des réglages de captions, keyframes et effets ; la dernière suite UI passe après correction.
- Test UI final : après ajout de l’aperçu dans la feuille captions, la commande Enregistrer se trouve plus bas dans une List chargée à la demande. Le test attendait sa présence sans défiler ; ajout du défilement jusqu’à la commande accessible.
- Répertoire temporaire de modèle : durée de vie liée à l’objet d’aperçu pour éviter sa suppression lors d’un sélecteur intermédiaire.

## Captures et couverture UI

Les captures par appareil (iPhone18Pro, iPhoneSE3 et iPhone18ProMax) documentent bibliothèque, Scénario, Timeline, inspecteur carré, paysage, comparateur, export, réouverture, revue d’import, captions et paquet transportable. Elles proviennent de XCUIScreen, pas d’une maquette. `Evidence/Screenshots/iPhone18Pro`, `Evidence/Screenshots/iPhoneSE3` et `Evidence/Screenshots/iPhone18ProMax` reprend des noms lisibles ; les manifestes XCTest relient chaque pièce au test et au simulateur.

Le scénario UI passe en français. Il importe une ressource durable déjà présente vers la revue d’import ; il ne remplace pas une recette Photos de trois vidéos et une photo choisies sur un appareil réel. ExportMP4 et transport dans sandbox propre sont éprouvés en intégration ; l’UI vérifie la création du paquet et l’accès au partage, sans envoyer un fichier à un tiers.

## Non exécuté / restant

Test microphone refusé, fournisseur cloud indisponible, transcription de parole réelle et ressources installées, corpus HDR/VFRréel, Photos refusé, casque/Bluetooth/appel, chauffe/mémoire sous charge, session matérielle en mode avion et VoiceOver/DynamicType exhaustif. Ni un test synthétique ni une compilation ne vaut réussite de ces cas. Voir KnownLimitations.md et la matrice pour les écarts fonctionnels restants.

## Reproduire

`Scripts/validate.sh SIMULATOR_UDID` fait un clean build puis tous les tests et extrait les pièces. `Scripts/run-core-tests.sh` teste séparément le noyau. `Scripts/inspect-exports.swift` rouvre les MP4 livrés et extrait des images de contrôle via AVFoundation. Aucun test désactivé pour masquer un échec ; les erreurs des premières passes restent documentées.
