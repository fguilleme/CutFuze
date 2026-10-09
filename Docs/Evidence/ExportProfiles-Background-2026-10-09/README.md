# Profils d’export et continuité — 9 octobre 2026

## Changements

- Compact, Équilibré (défaut), Haute fidélité ; compression HEVC (défaut) ou H.264.
- Débit manuel conservé dans Avancé. Résolution, cadence et multi-format conservés.
- Qualité constante VideoToolbox demandée uniquement si le codec/résolution publie cette capacité. Facteurs initiaux : 0,55 / 0,72 / 0,88. Aucun équivalent x264 CRF ou preset slow n’est annoncé.
- Repli sur un débit moyen adapté : pixels × cadence × 0,075 / 0,14 / 0,24, facteur HEVC 0,65, minimum 200 kb/s. Ces valeurs sont des points de départ à calibrer, pas des garanties perceptuelles.
- Taille indicative calculée séparément pour chaque format sélectionné, audio compris ; pas de taille maximale garantie en qualité constante.
- Le reçu indique le mode effectivement utilisé.
- Export et génération/traduction des sous-titres demandent une tâche iOS BGContinuedProcessingTask, avec progression directe, expiration et annulation. Un refus n’est pas masqué : message utilisateur et courte protection UIKit de secours.
- Pas d’accès GPU en arrière-plan ni de nouvel entitlement : le rendu Core Image d’export utilise le CPU, qui peut être plus lent. L’aperçu conserve son contexte accéléré.
- L’écran reste éveillé pendant un traitement au premier plan ; fermeture du panneau de transcription protégée jusqu’à fin/annulation.

## Vérifications exécutées

- Compilation simulateur iPhone 16 Pro / iOS 27 réussie.
- MediaTests + LocalizationTests : 19 tests réussis, incluant six exports courts (trois profils × H.264/HEVC), relus par les vérifications codec, dimensions et durée de l’exporteur.
- Suite unitaire complète CutFuzeTests : 88 tests réussis (97,3 s), y compris réexportation du projet de démonstration, effets, rendu, audio, sous-titres et multi-format.
- Test UI des trois profils, mode manuel et retour après Home : réussi.
- Test UI : export de la démonstration réelle de 30 secondes, 9:16, 720 × 1280, HEVC, Équilibré ; Home pendant trois secondes, retour et attente de Terminé : réussi.
- Captures natives du panneau profils et du mode Avancé inspectées : profiles-fr.png et advanced-fr.png.

## Limites vérifiées, pas promises

Le simulateur n’a publié de capacité de qualité constante ni pour H.264 ni pour HEVC. Les six exports ont donc exercé le repli sur débit adapté ; la branche qualité constante est couverte par le test de configuration, pas par un encodeur matériel réel.
Le simulateur a refusé la tâche prolongée iOS. Le passage bref en arrière-plan utilise le secours UIKit, pas une preuve d’exécution prolongée autorisée.
Pas de test physique sous écran verrouillé, de transcription réelle en arrière-plan, de charge thermique, ni de comparaison perceptuelle sur un corpus de vidéos complexes. Ces points restent à vérifier avant d’annoncer un gain de qualité ou une autonomie en veille.
Si iOS expire la tâche, l’opération est annulée proprement et doit être relancée ; pas de reprise automatique depuis un point de contrôle. Forcer la fermeture de l’app n’est pas pris en charge.

## Résultats locaux

- /private/tmp/CutFuze-QualityProfiles-20261009.xcresult
- /private/tmp/CutFuze-ExportBackground-20261009.xcresult
- /private/tmp/CutFuze-ExportProfilesUI-20261009.xcresult
- /private/tmp/CutFuze-ExportAppSwitch-20261009.xcresult
- /private/tmp/CutFuze-AllUnit-ExportBackground-20261009.xcresult

Documentation de référence : [qualité constante](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_constantqualityfactor), [traitements continus iOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados).

## Validation physique à poursuivre

Compilation arm64 et signature pour l’iPhone 15 Pro réussies. Xcode a demandé de déverrouiller l’appareil avant de lancer les deux tests de profil et le test UI d’export. Le lancement bloqué a été annulé ; aucun test physique ne s’est exécuté. Résultat de cette tentative : /private/tmp/CutFuze-DeviceExportProfiles-20261009.xcresult.

Pour vérifier la vraie suspension (les tests attachés au débogueur ne suffisent pas) : lancer un export assez long depuis l’app, verrouiller l’écran pendant au moins une minute, puis vérifier la progression et le fichier terminé. Répéter avec une transcription sur une source parlée et les modèles de langue déjà téléchargés. Tester ensuite le refus de traitement prolongé et l’annulation depuis l’activité système.
