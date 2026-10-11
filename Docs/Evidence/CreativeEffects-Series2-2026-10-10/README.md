# Effets créatifs — deuxième série

Accès : sélectionner un clip, puis **Effets → Créatif**. Rêve, Balayage lumineux et Déformation liquide sont les trois premières entrées. Les effets de la première série restent disponibles dans le même catalogue défilant.

## Comportements

- **Rêve / Dream** : mélange de l’image nette avec une version adoucie, bloom et couleurs pastel. Intensité initiale 0,55, animable avec le graphe existant.
- **Balayage lumineux / Light sweep** : un reflet diagonal traverse une fois le clip, sur une plage initiale de 1,2 seconde à la tête de lecture. Couleur dorée par défaut, couleur libre et largeur réglables. Quatre points d’intensité prêts à modifier. La plage détermine la durée du passage. L’éditeur ouvre la preview au milieu du passage pour montrer le reflet.
- **Déformation liquide / Liquid distortion** : une texture de hauteur procédurale, douce et animée, produit des ondulations. Intensité initiale 0,55, vitesse de 0,25 à 2 ×. Le mouvement se calcule dans le temps d’animation conservé après coupe ; aucune accumulation aléatoire d’images.

## Intégration conservée

Même modèle, moteur de rendu, historique, sous-titres, pistes et multi-format. Les réglages sont communs aux formats. Preview et export utilisent `FrameRenderer`. Les nouveaux champs de largeur/vitesse sont optionnels et validés ; les anciens documents restent décodables. Les trois nouveaux effets sont disponibles aussi dans les anciens menus d’inspection.

Le balayage est appliqué après les masques/détourage/chroma, et sa lumière est bornée à l’alpha du calque. Il ne remplit pas les parties transparentes. Comme le Néon, ses couleurs sont éditables dans la première section de la feuille. Les descriptions et noms sont bilingues français/anglais.

## Validation

- Compilation iOS simulateur et compilation iOS signée pour appareil : réussies.
- Après demande de lancement : recompilation, installation et lancement réussis sur l’iPhone 15 Pro physique 📱ZAPHODICUS (11 octobre 2026). Cela confirme le déploiement, pas une validation des gestes ni des performances des effets sur appareil.
- Suite complète `CutFuzeTests` : **98 tests réussis, aucun échec**, sur la version finale du moteur. Domaine des points, persistance JSON, anciens documents, coupe, neutralité, masques, rendu CPU et export réel sont couverts.
- Régression UI de la première série (Zoom impact, Glitch court, Néon) : réussie sur simulateur iPhone.
- Nouveau parcours UI sur simulateur iPhone 6,3 pouces : réussi. Ajout d’un point Rêve ; quatre points du reflet accessibles ; choix cyan, modification de largeur, undo/redo ; modification de vitesse liquide, undo/redo ; application et réouverture des trois effets avec valeurs conservées.
- Même parcours UI sur simulateur iPad 13 pouces : réussi. Captures du catalogue et des trois éditeurs inspectées, réglages principaux lisibles et accessibles.
- Les trois MP4 joints sont de véritables exports H.264 160 × 160, 24 fps, effectués après une coupe. Les images décodées au temps exact sont comparées au rendu de preview (erreur RGB moyenne tolérée < 15/255).
- Déformation liquide : test de mouvement et de vitesse, plus vérification qu’une frontière droite présente une ondulation supérieure à deux pixels ; rendu recalibré après inspection d’une première version trop faible.
- Balayage : test du déplacement gauche/droite, du respect de l’alpha et de l’absence d’effet hors plage. Les captures du calque masqué ont été inspectées.
- Les premiers essais UI ont échoué : le défilement automatisé sautait la section du reflet, puis essayait de lire un élément hors écran. Le test utilise maintenant de petits gestes lents, arrêtés avant relâchement. Les réglages de la version finale ont réellement été manipulés ; les échecs initiaux ne sont pas présentés comme des validations.

Résultats Xcode conservés localement :

- Suite finale : `test_sim_2026-10-10T22-12-50-962Z_pid2186_b43f29c0.xcresult` (98 tests unitaires/intégration réussis ; ancien geste UI en échec).
- UI iPhone corrigée : `test_sim_2026-10-10T22-16-06-699Z_pid2186_ac196958.xcresult` (1 test réussi).
- UI iPad : `test_sim_2026-10-10T22-18-25-470Z_pid2186_28bba85a.xcresult` (1 test réussi).

## Captures et exports

- `iphone-catalog.png`, `iphone-dream.png`, `iphone-lightSweep.png`, `iphone-liquidDistortion.png` : captures réelles du parcours en simulateur, 1206 × 2622. Les réglages inférieurs de la feuille se parcourent par défilement ; sur le reflet, la capture montre la couleur et le slider de largeur intégralement accessibles.
- `ipad-catalog.png`, `ipad-dream.png`, `ipad-lightSweep.png`, `ipad-liquidDistortion.png` : captures réelles en simulateur, 2064 × 2752.
- `render-dream.png`, `render-lightSweep.png`, `render-liquidDistortion.png` : rendus CPU.
- `liquid-first.png`, `liquid-later.png` : même image à deux instants, sans reprise de phase aléatoire.
- `sweep-early.png`, `sweep-late.png` : reflet sur calque masqué à deux instants.
- `export-dream.mp4`, `export-lightSweep.mp4`, `export-liquidDistortion.mp4` : petits corpus de validation après coupe, pas des démonstrations sur un projet utilisateur.

## Limites

- Echo temporel non inclus : ce sera une étape distincte avec échantillonnage de plusieurs images successives.
- Pas de validation de performance sur vidéo longue/4K ou de mesure thermique/autonomie sur appareil physique pour cette série.
- Les interactions des nouveaux effets n’ont pas été testées sur l’iPhone physique ; seule l’installation et le lancement y sont confirmés.
- Le balayage est un reflet stylisé diagonal, pas une simulation d’éclairage 3D ni une transition entre deux clips.
- La preview de cette feuille garde sa hauteur fixe ; les réglages inférieurs restent défilants.
- Aucun preset, asset ou code propriétaire Adobe utilisé.

## Références

- [Apple — Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html) : bloom, flou, gradients, masques et texture de distorsion.
- [Adobe — Distort effects](https://helpx.adobe.com/after-effects/desktop/apply-effects-and-animation-presets/list-of-effects/distort-effects.html) : conventions de déformation fluide.
- [Adobe — Generate effects](https://helpx.adobe.com/after-effects/desktop/apply-effects-and-animation-presets/list-of-effects/generate-effects.html) : catégorie des balayages lumineux.

Ces références décrivent des conventions ; elles ne démontrent pas une viralité ni une équivalence de rendu avec After Effects.
