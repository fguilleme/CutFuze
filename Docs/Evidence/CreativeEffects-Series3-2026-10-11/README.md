# Effets créatifs — lot 3

## Implémentation

Six effets ajoutés au catalogue Créatif, avec le même éditeur de preview redimensionnable, courbes, interpolation, plage, annuler/rétablir et activation que les effets existants :

- Grand-angle pulsé : déformation sur toute l’image et impulsion de zoom ; enveloppe de trois points prête à modifier.
- Traînée fantôme : jusqu’à cinq vrais échantillons précédents du calque, espacement et décroissance réglables ; les transformations animées font aussi partie des échantillons.
- Stop-motion : cadence propre au calque (2–24 images/s), sans changement de la cadence d’export, de l’audio ni des autres pistes.
- Flou filé : flou directionnel et angle réglable.
- Trame pop : points d’impression et taille réglable.
- Duotone : deux couleurs personnalisables, trois palettes et inversion.

Les nouveaux paramètres sont optionnels dans le document Codable. Les anciennes ressources, les effets, le montage multi-format et les outils existants sont conservés. Aucun asset ou preset propriétaire Adobe/CapCut n’a été importé.

Les effets temporels réutilisent la conversion temporelle existante. Un échantillon précédant une coupe peut retrouver sa position source sans modifier les limites du document. Le cache de détourage utilise maintenant la date réellement décodée, y compris pour ces échantillons historiques.

## Correction découverte à la validation

La comparaison des images rendues aux vidéos décodées révélait une différence systématique de tons moyens. Le profil Core Graphics nommé Rec.709 et les buffers Core Video ITU_R_709_2 n’avaient pas la même fonction de transfert. L’export convertit maintenant les pixels vers l’espace dérivé des métadonnées vidéo et attache ces métadonnées aux buffers. Les codecs, les profils de compression et la structure du moteur d’export restent inchangés.

Les seuils de comparaison des tests n’ont pas été augmentés pour masquer cet écart. Le test des profils vérifie aussi les tons moyens à ±5 niveaux par canal, en H.264 et HEVC pour les trois profils.

## Validation

Régression finale sur simulateur iPhone 16 Pro (viewport 6,3 pouces, 1206 × 2622) : **117 réussis, 0 échec, 0 ignoré** — 115 tests de modèle/média/services et 2 parcours d’interface ciblés sur les six nouveaux effets. Ce n’est pas une exécution de toute la suite UITests.

Le relais XcodeBuildMCP a atteint sa limite de réponse de 300 secondes ; le processus Xcode a bien terminé avec `TEST EXECUTE SUCCEEDED`. Le résultat a été confirmé directement avec `xcresulttool get test-results summary` : 117 tests, résultat `Passed`, aucune défaillance ni avertissement d’exécution. Bundle : `/Users/francois/Library/Developer/XcodeBuildMCP/workspaces/CutFuze-b40d000a0964/result-bundles/test_sim_2026-10-11T11-37-11-430Z_pid2186_2e0f1b28.xcresult`.

Tests ajoutés ou étendus : paramètres et migration, validation des bornes, courbes pour chaque type d’effet, round-trip du document, undo/redo, continuité après split, preroll avec vitesse variable et lecture inversée, transparence, changement réel des pixels, vrais médias temporels, maintien des poses sans saccader les autres calques, export et cadence inchangée.

Les premières exécutions ont échoué : différence de couleurs à l’export, mauvais échantillon choisi pour distinguer le stop-motion d’une image source 30 fps, et gestes de test qui dépassaient le bouton recherché dans le catalogue. Les deux derniers cas concernaient les tests ; le premier a nécessité la correction du moteur d’export décrite ci-dessus.

Les captures de diagnostic iPhone ont été ouvertes et inspectées. Les choix d’angle et de cadence manquaient d’un état sélectionné visuel : ils utilisent maintenant des boutons compacts avec sélection ambrée. L’éditeur conserve son scrolling commun à la preview, la courbe et les réglages.

Treize captures d’interface finales ont été obtenues, avec les images de rendu et les vidéos H.264 de comparaison dans [Final/manifest.json](Final/manifest.json). Les états de réglage corrigés ont été inspectés :

- [Grand-angle — courbe](Final/8C6E3DA6-69F6-4A5E-945D-49B948101303.png)
- [Traînée — réglages](Final/E0810803-935F-478C-80D2-95EF07D87922.png)
- [Stop-motion — cadence](Final/3282BF82-08A1-4DC1-9988-9D268437B7F7.png)
- [Flou filé — angle](Final/22FB297D-3926-4FE1-8D15-F3D909AE442F.png)
- [Trame — taille des points](Final/4A141B14-3C0E-4079-B456-4CB4DC9BA716.png)
- [Duotone — palette](Final/0430A207-B8AC-4A87-A621-326B1255A7BB.png)

## Limites

- Ce lot n’a pas encore été lancé ni testé sur un appareil physique, ni validé sur iPad.
- Les mesures utilisent de petits médias synthétiques, pas un benchmark de montage long en 4K.
- La traînée ajoute jusqu’à cinq rendus historiques : coût supérieur aux effets spatiaux ; une image immobile sans animation ne produit pas de silhouettes distinctes.
- Le grand-angle est une déformation créative, pas une calibration d’objectif ni une reproduction exacte d’Optics Compensation.
- Seule l’intensité de ces effets possède une courbe ; leurs paramètres secondaires restent des valeurs fixes.

## Références de comportement

- [Adobe — Time effects : Echo, Posterize Time](https://helpx.adobe.com/after-effects/desktop/apply-effects-and-animation-presets/list-of-effects/time-effects.html)
- [Adobe — Distort effects : Optics Compensation](https://helpx.adobe.com/after-effects/desktop/apply-effects-and-animation-presets/list-of-effects/distort-effects.html)
- [Apple — Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)
- [Apple — Tagging media with video color information](https://developer.apple.com/documentation/avfoundation/tagging-media-with-video-color-information)
