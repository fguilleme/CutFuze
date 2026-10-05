# Moteur média — état et limites

État du code au 5 octobre 2026. Sources Core/Media validées par compilation Swift 6, application compilée pour iOS 27 et tests exécutés sur simulateur iPhone 18 Pro. `build/SecondValidation.xcresult` contient 35 tests réussis (moteur, services, Vision), dont les huit tests média alors présents. La suite finale FinalValidation a exécuté avec succès les onze tests média, dont pipette, remplacement atomique et effets temporisés. Les54tests hors UI passent ; le test UI a ensuite réussi dans FinalUIValidation après adaptation à une liste défilante. Aucun test sur iPhone physique n’est revendiqué.

## Pipeline livré

- Import de fichiers par copie en blocs de 1 Mio dans `Media/`, empreinte SHA-256, validation du contenu ImageIO ou des pistes AVFoundation. Les fichiers temporaires et URL de sélecteur ne deviennent pas des dépendances du montage. Les fichiers de même contenu et même extension partagent leur original durable.
- Vignettes orientées et formes d’onde calculées sur les vrais échantillons. Caches régénérables dans `Cache/`.
- Un acteur `FrameRenderer` sert l’aperçu, les comparaisons et l’export. Images/vidéos orientées ; vidéo décodée à l’instant source évalué par `TimeMapping`. Les vidéos HDR passent par `AVAssetImageGenerator.dynamicRangePolicy = .forceSDR`. Aucun export HDR n’est proposé.
- Segmentation de personnes Vision locale, masque borné (8 résultats), contour progressif appliqué par le même renderer aperçu/export. Aucun corpus humain autorisé n’a encore été validé.
- Textes CoreText incrustés, mise en page normalisée, accents et fallback des polices système ; six modes de fusion, masques transformables, chroma key RGB avec suppression du débordement de la composante dominante, keyframes de transformation et opacité ; huit transitions ; effets Core Image. `amount = 0` est un bypass réel pour tous les effets.
- Sources vidéo lues image par image via AVAssetImageGenerator ; lecture inversée par mapping source décroissant et décodage borné. Le son des clips inversés est explicitement désactivé. Aucun faux `player.rate = -1`.
- `AudioComposer` crée le même AVMutableComposition/AVAudioMix pour l’aperçu et le lecteur d’export : volumes, fondus, chevauchements, vitesse constante exacte et courbe approchée par segments de 20 ms avec algorithme spectral. La durée de composition audio est prolongée par un intervalle vide jusqu’à la fin du montage lorsque nécessaire.
- Convention de mixage : audio global = musique, audio attaché à une scène = voix. La musique diminue de 12 dB sous les voix (attaque 100 ms, relâche 250 ms). Une enveloppe conservatrice limite la somme des gains à 0,80 ; ce n’est ni un limiteur de crêtes true-peak ni une réduction de bruit.
- MP4 H.264/HEVC, dimensions paires, débit effectivement transmis à AVAssetWriter, 24/25/30/50/60 images/s, SDR Rec.709. Les timestamps sont calculés depuis l’index d’image. Arrondi commun de la durée à la grille supérieure ; dernière image prise dans l’intervalle du document.
- Encodages sérialisés, annulation contrôlée, progression liée aux frames écrites, vérification de l’espace disque, fichier temporaire remplacé après succès. Relecture vidéo, audio attendu, codec, dimensions, cadence, durée et image médiane avant installation du fichier final.

## Sémantique de composition

Les scènes sont des groupes visuels. Les couches internes d’une scène sont ordonnées par `layer`, puis le groupe complet participe à la transition de scène. Les couches globales sont composées ensuite, dans leur ordre de couche : un titre global traverse donc une transition sans être fondu avec la scène. Le moteur ne permet pas encore d’intercaler une couche globale au milieu des couches internes d’une scène.

Masques dans les coordonnées normalisées de la source orientée, puis transformation sur le canevas. Texte : taille proportionnelle au plus petit côté du canevas, largeur de ligne 86 % du canevas. Filtres avant transformation, masque/chroma, transformation, opacité, transition de groupe et couches globales. Les fondus du clip sont communs à l’image et au son lorsque le clip possède les deux.

## Limites réelles

- Ce moteur privilégie la parité déterministe et la mémoire bornée. Il ne revendique pas une lecture temps réel à 30/60 fps sur matériel physique : seeking vidéo image par image peut être lent. Pas de proxies adaptatifs ni de décodage séquentiel optimisé pour la lecture continue.
- Caches bitmap plafonnés à 64 Mo pour images et 32 Mo pour textes, 8 cubes de chroma et 6 générateurs vidéo. Ces chiffres ne représentent pas la mémoire totale du processus (encodeur, Core Image et décodage compris). Texture source plafonnée à 4096 pixels sur le plus grand côté ; un très fort zoom d’une photo haute résolution peut perdre de la finesse.
- Courbes de vitesse audio : approximation de 20 ms, conservation de hauteur spectrale pouvant modifier les transitoires. Le corpus de trois coupes à vitesse constante a mesuré un écart A/V maximal de 12,584 ms ; cette mesure ne qualifie pas toutes les courbes possibles. Audio inversé non produit.
- Le ducking découle de l’ancrage scène/projet ; pas de classification sémantique de la voix. Le gain de headroom est conservateur et peut réduire plusieurs sources silencieuses. Pas de réduction de bruit, séparation vocale ou limiteur true-peak. Le premier corpus impulsionnel AAC décodé en mono (réduction de deux canaux) a produit un pic de 1,10068 avec une marge de 0,95. La marge a été réduite à 0,80 et le test exige désormais un maximum décodé ≤ 1 ; cette correction a passé le test final : pic mono décodé0,9284009. Elle ne constitue pas un limiteur true-peak universel.
- Chroma key simple dans l’espace RGB. La pipette UI échantillonne la couche source orientée à l’instant source courant, rejette les bandes hors image, convertit le pixel vers sRGB et déprémultiplie son alpha. Le panneau affiche le résultat composé avec le vrai moteur, avant validation en une commande annulable. L’échantillonnage porte sur l’image avant effets de couleur : ceux-ci peuvent modifier la couleur à détacher et nécessiter un ajustement de tolérance. La segmentation de personnes est implémentée avec Vision mais reste à évaluer sur cheveux, mouvement, occultation et faible lumière ; suivi/stabilisation relèvent des services distincts.
- `band` et `rectangle` utilisent la même primitive de rectangle, avec dimensions configurables. Le texte possède un espacement des lettres et un interligne en em, vérifiés par la géométrie raster ; pas de karaoké mot à mot. Courbes RGB/HSL non implémentées. Les intensités des effets disposent désormais de keyframes avec easing et d’une plage optionnelle dans le temps d’animation ; leur test de rendu, bornes, migration et continuité au split est passé dans FinalValidation.
- La conversion HDR vidéo utilise l’API publique forceSDR, mais aucun média HDR autorisé n’a encore été analysé. Pas de qualification HDR photo/HEIC ni d’export HDR.
- Résolutions jusqu’à 3840 pixels sur le plus grand côté ; un libellé 1080p implique 1920×1080 ou 1080×1920 pour 16:9, et ne doit pas être confondu avec `longEdge = 1080`. Les dimensions exactes retournées par `dimensions(for:)` font foi. HEVC, 4K et hautes cadences nécessitent encore validation du matériel cible.
- Pas de téléchargement iCloud piloté avec progression dédiée : l’accès et les erreurs dépendent du fournisseur de fichiers / sélecteur. La copie d’import est annulable entre blocs, mais l’interface doit conserver et annuler sa tâche pour offrir cette commande.
- Les API AVAssetReader/Writer utilisées restent disponibles mais sont dépréciées dans le SDK 27 au profit des providers/receivers async. Migration envisageable après validation ; aucun contournement privé utilisé.
- Aucun test thermique, interruption en arrière-plan ou mémoire maximale sur iPhone physique n’a été exécuté dans ce module.

## Tests exécutés et mesures

`CutFuzeTests/MediaTests.swift` contient : pixels de couches/masques, effets neutres, bornes de captions, unicité des huit transitions sur corpus à motifs, rendu de chaque effet, six fusions/chroma/masque tourné ; photos seules avec son et trois formats, parité d’image avant/après H.264 avec tolérance de 30 niveaux/canal ; transport dans un sandbox propre avec suppression de la source et réexport des trois formats ; fichier corrompu/manquant ; annulation et relance ; vidéo synthétique réimportée, reverse et courbe ; mesure du temps de 15 rendus 360×640 ; impulsions A/V après coupes et vitesses 1×/2×/0,5× avec cible inférieure à une image à 30 fps.

Les huit tests média antérieurs à la pipette ont réussi dans `SecondValidation.xcresult`, y compris le test additionnel de vidéo orientée par preferredTransform à 90°, vérifiée 180×320 à l’import, en pixels et à l’export. Les MP4 et mesures sont joints aux résultats XCTest et les premières pièces ont été extraites dans `Docs/Evidence/Exports/`.

Mesures effectivement lues dans les pièces :

- [Impulsions après coupes/retiming](Evidence/Exports/7897404C-CD52-4219-AD83-8E78E51EA562.txt) : repères vidéo attendus 0,100 / 0,500 / 0,800 s ; pics audio décodés 0,109854167 / 0,495125 / 0,812583333 s. Erreur absolue maximale 12,584 ms, inférieure à l’image de 33,333 ms à 30 fps. Amplitudes maximales respectives 1,086043 / 0,373108 / 1,1006799 dans cette première exécution avant correction de la marge ; dépassement mesuré dans le downmix stéréo-vers-mono signalé dans les limites.
- [Rendu synthétique](Evidence/Exports/2FE989A7-B4F8-47E0-A6CA-E6655504246C.txt) : 15 images générées en 360×640 ont pris 0,023188 s sur le simulateur. Il ne s’agit ni de décodage de vidéos réelles ni d’un benchmark sur appareil physique ; ne pas convertir ce résultat en promesse de lecture à une cadence commerciale.
- Photos seules + vrai son : trois ratios encodés/relu, tolérance de compression H.264 vérifiée, puis paquet réimporté dans une racine propre, originaux source supprimés et trois formats réexportés avec succès.

Ajouts après `SecondValidation` : test pipette (bandes hors image, coordonnées, pixels sRGB, alpha), installation atomique avec remplacement et conservation de l’ancien résultat en cas de source absente, et plage/keyframes d’intensité (bornes, rendu neutre, interpolation, décodage antérieur, continuité après split et round-trip). Reporter leurs résultats définitifs dans `ValidationReport.md`.

## Correction de l’export long

Le premier test de livraison de 30 secondes échouait après environ 32 secondes ; l’erreur remontée par XCTest mentionnait la suppression d’un fichier temporaire absent. L’audit de la boucle a révélé une attente bloquante sur une seule entrée d’AVAssetWriter : le multiplexeur pouvait attendre la vidéo pendant que le producteur attendait la disponibilité audio.

La pompe est maintenant coopérative et bornée : elle alimente chaque entrée prête, ne bloque jamais une piste en attendant l’autre, marque séparément leur fin, et ne déclenche son délai de 30 secondes que si aucune piste ne progresse. L’installation utilise `fsync` puis `rename` atomique dans le même dossier. Le nettoyage emploie `unlink` sans erreur Swift pour préserver le diagnostic initial ; le test affiche explicitement la description d’erreur.

Preuve après correction : `DeliveryTests/testThirtySecondDemoPortableReexportAndDeliveryArtifacts` a réussi dans `build/DeliveryValidation4.xcresult` en 56,804 s. Les trois formats du véritable exemple de 30 secondes ont été encodés à 1280 pixels, 30 fps, H.264 4 Mbit/s avec audio, depuis le projet transporté après suppression des originaux. Les pistes et images à 1,5 / 14 / 28 secondes sont relues. Cette mesure est propre au simulateur, sans promesse de vitesse sur iPhone physique.

## Mesure finale du mix

`Evidence/Final/CDE1B3CA-5F13-4977-9B11-0320127F46B6.txt` : pics0,923156/0,313884/0,928401 ; maximum mono0,928401≤1. Instants inchangés0,109854/0,495125/0,812583s, donc erreurmax12,584ms. La correction de marge est validée pour ce corpus, sans promesse de limiteur universel.

Dernière confirmation : ReleaseCandidateValidation exécute55tests avec0échec/0ignoré, dont les11tests média. Le pic mono total mesuré sur cette passe est0,928899 ; le lot démo a pris55,2270s.
