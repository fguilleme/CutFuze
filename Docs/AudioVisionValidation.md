# Voix, modèles et analyses locales

État constaté le 5 octobre 2026. Les types et appels ont été compilés avec le SDK iOS Simulator 27.0. La cible minimale reste celle du projet ; SpeechAnalyzer est protégé par disponibilité iOS 26.

## Preuves exécutées

Les résultats `Build/SecondValidation.xcresult` ont été lus avec `xcrun xcresulttool get test-results tests` et `summary`. Environnement : **iPhone 18 Pro Simulator, iOS 27.0, arm64**, Xcode 27.0. Les quatre tests suivants sont PASSÉS dans ce résultat :

- `ServiceTests.testDemoContainsThirtySecondsOfRealLocalAssetsAndThreeLayouts` : 3 scènes, 3 captions, 3 présentations distinctes ; PNG réellement décodables 1280×960 ; fichier audio réel 48 kHz de 1 440 000 échantillons, avec signal non nul et sans saturation du corpus.
- `ServiceTests.testTwelveTemplatesCreateDifferentEditableStories` : 12 signatures de montage distinctes, des textes/keyframes modifiables et des ressources présentes.
- `VisionTests.testCorpusContainsOrientedFramesAndSampleTimedImpulses` : vidéo encodée 320×180 avec orientation 90° donnant 180 × 320 ; piste CAF de 96 000 échantillons ; impulsion présente à 0,5 s et silence après sa fin.
- `VisionTests.testRealVisionTracksEncodedMovingRectangle` : le vrai moteur Vision suit le rectangle d’un MP4 généré ; au moins 18 observations ; déplacement horizontal mesuré >0,3 de la largeur ; confiance minimale ≥ 0,3 ; position finale comparée à une tolérance de 0,055.

Ces tests sont un corpus déterministe, pas un benchmark d’iPhone physique ni une validation sur tous les sujets. Le résultat complet de cette passe contient 35 tests passés, sans échec ni test ignoré. Les suites de validation ultérieures font foi pour la livraison finale.

## Voix et transcription

`VoiceRecorder` écrit un AAC durable, gère permission, compte à rebours, niveau RMS, route déconnectée, interruption audio et passage arrière-plan. Une prise interrompue est préservée en tenant compte du fichier effectivement écrit, même si le compteur du recorder revient à zéro. L’écoute de référence exige un casque détecté avant et après le démarrage ; aucun monitoring du microphone n’est ajouté.

`SpeechFileSynthesizer` écrit les buffers système en CAF, ferme puis rouvre le fichier pour vérifier sa longueur avant installation. Il dispose d’annulation et d’un délai maximal explicite. Les voix proviennent du système, sans catalogue fictif.

`LocalTranscriber` utilise SpeechAnalyzer/SpeechTranscriber quand le matériel et la langue sont disponibles et déjà installés. Le repli SFSpeechRecognizer exige `supportsOnDeviceRecognition`, `isAvailable` et `requiresOnDeviceRecognition=true`. Il utilise des blocs de 45 s avec 1 s de chevauchement et une règle temporelle de déduplication ; aucune précision temporelle n’est inventée. Les segments/temps source sont conservés sur les captions liées au clip. Aucun téléchargement ou repli cloud n’est lancé.

**Non exécuté sur matériel physique :** prise microphone intelligible, interruptions téléphoniques/Bluetooth, qualité de synthèse d’une voix locale, reconnaissance de parole réelle et ressources de plusieurs langues. Le repère sonore de la démo n’est pas un test de reconnaissance. Une indisponibilité système reste une erreur et n’est pas remplacée par un texte prédéfini.

## Portée Vision

Le suivi analyse jusqu’à 10 images/s pendant au plus 10 minutes, en mémoire bornée. La région est dessinée ou réglée numériquement. La confiance faible stoppe la trajectoire. Les coordonnées sont projetées après orientation, ajuster/remplir, miroir et rotation du média, puis écrites dans les keyframes de la couche cible. Le suivi est celui d’une région ; aucune reconnaissance d’identité n’est proposée.

La stabilisation estime des translations avec Vision sur une source importée, les lisse sur une fenêtre symétrique et produit position/échelle plus recadrage borné. Limites : extrait ≤ 60 s, analyse ≤ 30 Hz, petites secousses et scène similaire ; rotations, rolling shutter, forts déplacements et grandes ruptures de plan ne sont pas corrigés. Les animations produites sont communes aux formats et calculées pour le cadrage actif, ce que la UI annonce explicitement.

La passe `Build/VisionFinalValidation.xcresult` a été relue directement avec `xcresulttool` : **5 tests passés, aucun échec, aucun ignoré**, sur le même simulateur. En plus du corpus orienté et du suivi, elle valide le respect du cadrage de variante par les keyframes de stabilisation et le rejet d’un faux pic de recalage sur texture périodique, grâce à une vérification photométrique réelle des pixels.

`testStabilizationReducesMeasuredMotionInActualRenderedFrames` mesure le centroïde du rectangle dans les images issues du vrai FrameRenderer, avant/après correction. Résultats de ce corpus de 2 secondes : **RMS 4,0983 pixels avant, 0,6111 pixel après**, ratio 0,1491 ; facteur d’échelle appliqué **1,05263**. Le déplacement inter-images estimé par recalage passe de 0,0337284 à 0,00252557 après lissage. Ces chiffres décrivent ce corpus et ce simulateur, pas la qualité générale de stabilisation sur un iPhone physique. [Mesures brutes](Evidence/Vision/71C31BE2-D0D1-418F-BDD9-431BA323357D.txt).

Le suivi de ce même résultat fournit **20 observations**, du centre normalisé (0,19375 ; 0,5) à (0,607375 ; 0,492424), avec une confiance minimale de **0,771**. [Mesures brutes](Evidence/Vision/2C259BD5-85AA-4207-8761-0951B7A5C79F.txt).

Après cette passe, la conversion des keyframes de suivi vers le domaine commun a été ajustée pour une couche cible ayant une surcharge de cadrage locale ; le test de régression `testTrackingKeyframesRespectTargetVariantBaseline` a été ajouté. Son résultat doit être confirmé dans la passe finale.

## Repères rythmiques manuels

`BeatMarker` persiste un identifiant, un temps rationnel absolu de projet et un libellé. Le champ optionnel du document permet de relire les projets qui n’avaient pas encore de repères. Les commandes ajoutent, corrigent et suppriment ces repères dans les transactions d’annulation normales ; un réordre de scènes conserve leur position absolue. Le panneau autorise le placement à la tête de lecture, la saisie précise et la suppression. `nearestBeat` reçoit une tolérance temporelle calculée par la timeline à partir d’un seuil en points, pour conserver la cohérence du snapping au zoom.

Les tests `BeatMarkerTests` couvrent le round-trip, l’ancien document sans champ, undo/redo avec réordre, absence de doublon et tolérance de snapping. Ils sont ajoutés au projet ; leur résultat est à lire dans la passe finale. Il n’y a pas de détection automatique ou d’IA musicale revendiquée par ces repères manuels.

## Dernière suite moteur

FinalValidation.xcresult : six tests Vision, deux ServiceTests et trois BeatMarkerTests tous passés, parmi54tests horsUI. Le sixième test vérifie la conversion des points de suivi vers le domaine commun quand la cible possède un cadrage local. Les services microphone, synthèse et transcription de parole restent non testés sur appareil réel.
