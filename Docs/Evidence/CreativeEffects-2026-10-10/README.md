# Effets créatifs — 10 octobre 2026

Première série issue de l’analyse de la documentation After Effects : **Zoom impact**, **Glitch court**, **Néon**. Implémentations propres à CutFuze, sans assets ni presets Adobe. La documentation technique ne démontre pas leur « viralité ».

## Utilisation

Sélectionner un clip vidéo, une photo, un overlay ou un texte, puis **Effets → Créatif → preset**. Les trois nouveaux presets sont au début du catalogue. Le preset est inséré au montage ; la coche valide les réglages du brouillon.

| Preset | Comportement initial | Réglages |
| --- | --- | --- |
| Zoom impact | Zoom, secousse, flou radial ; enveloppe de 0,48 s | Points d’intensité et interpolation |
| Glitch court | Décalages horizontaux par bandes et séparation RGB ; rafale de 0,30 s | Points d’intensité et interpolation |
| Néon | Contour lumineux et halo diffus ; intensité constante initiale | Intensité animable, étendue du halo, cinq couleurs et sélecteur libre |

Les rafales sont placées à la tête de lecture lorsqu’elle est dans le clip. Près de la fin, leur début est décalé pour que l’enveloppe reste dans le clip. Les clips très courts obtiennent une enveloppe raccourcie.

La courbe des rafales montre d’abord leur propre intervalle, pas toute la durée d’un long clip. **Voir tout le clip** donne accès à la vue complète. L’interpolation règle l’arrivée vers le point sélectionné ; elle est désactivée sur le premier point. Le menu reste directement sous la courbe. Annulation/rétablissement du brouillon et réouverture des réglages sont conservés.

Le catalogue occupe maintenant 178 pt au lieu de 266 pt en portrait. Les cibles tactiles de ses boutons font 44 pt. La feuille d’effets iPad utilise le dimensionnement page/grande hauteur ; ses réglages restent défilants.

### Ajustement du halo après essai iPhone

Le halo initial était trop proche d’un simple contour coloré. Le Néon combine maintenant un cœur net, une lueur proche et une diffusion plus large. **Étendue du halo** règle la diffusion indépendamment de l’intensité animable : 0 % conserve seulement le contour, 100 % produit le halo le plus large. Le réglage est dans la première section de la feuille, avec les couleurs.

Le rayon est proportionnel à la taille de l’image, enregistré dans le projet et conservé après une coupe. Les anciens effets sans rayon utilisent 45 %. Annulation/rétablissement du réglage utilisent le brouillon existant. Preview et export partagent le même traitement.

Après cette modification, compilation simulateur et signée iOS réussies, puis **96 tests unitaires/intégration passés**, zéro échec. Le test de diffusion compare des pixels à distance du contour à intensité constante, vérifie la continuité après coupe et la neutralité à intensité nulle. Le test d’export du texte utilise un halo large. Résultat : `test_sim_2026-10-10T21-43-30-759Z_pid2186_0b6b9ef6.xcresult` (la suite UI jointe à ce premier passage a échoué sur une assertion de geste trop précise : 93 % obtenu au lieu de 90 % visé).

Preuves complémentaires : `render-neon-contour-only.png`, `render-neon-wide-halo.png`, `render-neon-text-wide.png` et `export-neon-wide.mp4`. Les images et exports de la première version restent conservés séparément.

Le test UI iPhone relancé passe : toucher/glisser du slider, annulation vers 45 %, rétablissement de la valeur atteinte et conservation exacte après validation/réouverture. La tolérance ne concerne que la position initiale du geste XCTest, pas la persistance. Résultat : `test_sim_2026-10-10T21-47-44-436Z_pid2186_03d9d918.xcresult`. Capture : `iphone-neon-wide-halo.png`. Version ensuite installée et lancée avec succès sur l’iPhone 15 Pro connecté ; retour utilisateur positif. Les gestes automatisés restent vérifiés uniquement sur simulateur.

## Architecture conservée

- Même document, pistes, commandes de montage, historique et multi-format.
- Même `FrameRenderer` pour les effets en preview et à l’export ; filtres compatibles avec le rendu CPU déjà utilisé par l’export.
- Courbe `KeyframeGraph` existante, avec une fenêtre temporelle optionnelle. Les autres animations gardent la vue complète par défaut.
- Pas de nouveau moteur, de dépendance externe ni de suppression d’un effet existant.
- `colorHex` est optionnel ; les anciens effets sans ce champ continuent à se décoder.
- L’enveloppe et la graine déterministe restent dans le domaine d’animation existant, donc une coupe ne redémarre pas le Glitch.
- Le Néon est calculé après détourage/chroma/masque. Le texte et les éléments isolés utilisent leur alpha ; les médias non détourés utilisent leurs contours de luminance.
- Réglages communs aux formats ; cadrage et position spécifiques à chaque format inchangés.

## Validation

Compilation simulateur et compilation signée `generic/platform=iOS` exécutées avec succès. Les avertissements de dépréciation AVFoundation/Vision préexistants restent présents.

La suite complète `CutFuzeTests` a passé **95 tests, zéro échec, zéro saut**. Elle comprend notamment migration, sélection, commandes de timeline, variantes, sous-titres, rendu texte, Vision, audio et réexport de la démo de 30 secondes.

Tests ajoutés/étendus :

- Presets bornés au clip, clips très courts, valeurs d’intensité, JSON ancien/nouveau, conservation après coupe et intensité initiale des anciens menus.
- Interpolation d’intensité non linéaire et conservation JSON.
- Rendu CPU des trois effets réellement différent d’une image témoin, répétabilité, continuité après coupe, neutralité en dehors d’une rafale.
- Export vidéo réel de chacun des trois effets après une coupe, décodage à l’image exacte demandée et comparaison avec le rendu attendu.
- Couleur du Néon sur texte et masque elliptique ; export réel du texte avec halo.
- Gestes UI : sélection et déplacement des points, interpolation immédiate, undo, validation, réouverture et changement de couleur conservé.

Les premiers essais ont révélé et permis de corriger la palette de couleur difficile à atteindre, une description tronquée, le dimensionnement trop court de la feuille iPad et l’interpolation enfouie dans les réglages iPhone. La comparaison d’export utilise une tolérance de recherche temporelle nulle : une image voisine ne convient pas à une rafale de Glitch.

Derniers passages de la version finale : **5 tests ciblés passés sur iPhone** (3 tests de modèle/rendu et 2 tests UI), puis **1 test UI passé sur iPad**, zéro échec ni saut. Ces passages vérifient notamment que l’interpolation est accessible directement sous la courbe. Les régressions de l’éditeur d’animation et des contrôles bas iPad ont également passé leurs tests UI pendant cette série.

Résultats XCTest conservés localement :

- Suite complète : `test_sim_2026-10-10T20-44-24-730Z_pid2186_c8327f74.xcresult`.
- Dernier iPhone : `test_sim_2026-10-10T20-57-00-457Z_pid2186_02daf9a9.xcresult`.
- Dernier iPad : `test_sim_2026-10-10T21-00-18-264Z_pid2186_9ff4bc74.xcresult`.

Ils se trouvent dans `/Users/francois/Library/Developer/XcodeBuildMCP/workspaces/CutFuze-b40d000a0964/result-bundles/`. La compilation signée a été relancée avec succès après les derniers changements.

## Captures et exports

Captures issues de l’application exécutée en simulateur, pas de maquettes. Corpus local de la démo CutFuze.

- `iphone-catalog.png`, `iphone-impact.png`, `iphone-impact-easing.png`, `iphone-glitch.png`, `iphone-glitch-easing.png`, `iphone-neon.png`
- `ipad-catalog.png`, `ipad-impact.png`, `ipad-impact-easing.png`, `ipad-glitch.png`, `ipad-glitch-easing.png`, `ipad-neon.png`
- `render-neon-text.png`, `render-neon-mask.png` : images produites par le rendu CPU des tests.
- `export-impact.mp4`, `export-glitch.mp4`, `export-neon.mp4` : exports réellement encodés, corpus de test 160 × 160.

## Limites

- Gestes vérifiés en simulateurs iPhone 6,3 pouces et iPad 13 pouces, pas sur appareil physique pour cette série. La compilation physique ne constitue pas un test d’interaction.
- Pas de mesure de fluidité, température ou autonomie sur appareil physique, ni de benchmark d’un export long 4K avec ces effets.
- Le contour alpha a été vérifié sur texte et forme masquée, pas sur une personne réelle détourée du projet utilisateur.
- La preview de cette feuille d’effets reste de hauteur fixe ; le redimensionnement déjà disponible dans l’éditeur d’animation n’a pas été étendu ici.
- Rêve, balayage lumineux, déformation liquide et Echo temporel ne font pas partie de cette première série.

## Références de conception

- [Adobe — effets de stylisation, Glow](https://helpx.adobe.com/after-effects/desktop/apply-effects-and-animation-presets/list-of-effects/stylize-effects.html)
- [Adobe — effets de flou](https://helpx.adobe.com/sg/after-effects/desktop/apply-effects-and-animation-presets/list-of-effects/blur-sharpen-effects.html)
- [Adobe — exemples d’expressions et Wiggle](https://helpx.adobe.com/after-effects/desktop/work-with-expressions/expression-examples/expression-examples.html)

Ces références décrivent des conventions et opérations, pas du code ou des assets réutilisés dans CutFuze.
