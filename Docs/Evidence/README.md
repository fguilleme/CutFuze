# Preuves produites

Les fichiers de ce dossier proviennent de compilations, XCTest et captures de simulateurs réellement exécutés. Les MP4 sont des sorties du moteur, les PNG du dossier Demo sont décodés depuis ces MP4. Les images UI sont des captures XCUIScreen.

## Démonstration autonome

- [Projet complet](Demo/Trente-secondes.cutlabproject), importable depuis la bibliothèque de CutFuze.
- [9:16](Demo/9x16.mp4), [1:1](Demo/1x1.mp4), [16:9](Demo/16x9.mp4). Chaque fichier fait30s,30fps,H.264 et contient une piste audio.
- [Relecture AVFoundation](Demo/inspection.txt) ; contrôles1,5s/14s/28s aux côtés des vidéos.
- [Image verticale à14s](Demo/9x16.14.0s.png), [image paysage à14s](Demo/16x9.14.0s.png).

## Captures

`Screenshots/iPhone18Pro` et `Screenshots/iPhoneSE3` contiennent les étapes numérotées. Les captures grand écran finales sont dans `Screenshots/iPhone18ProMax`. Les manifestes dans Delivery, Compact, FinalUI et les pièces finales relient noms, appareils et tests. Une capture n’atteste pas d’une mesure de performance matérielle.

## Journaux

`latest-clean-build.log` contient la dernière compilation propre. `core-native-tests.log` contient29tests Foundation sur macOS. `release-summary.json` atteste55tests réussis dans la dernière passe complète. Les résumés JSON sont issus de xcresulttool, sans résultats inventés. Les bundles XCTest complets restent sous `build/`, exclus de Git.

Les dossiers FirstUI, UI5 et Final conservent notamment les erreurs UI des premières passes. Le rapport principal explique leurs corrections et indique les résultats qui les remplacent. Ne pas additionner les tests répétés comme des tests distincts.
