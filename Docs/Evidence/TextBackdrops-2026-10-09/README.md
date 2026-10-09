# Fonds de texte colorés — 2026-10-09

Style propose une couleur de texte libre, une couleur de fond libre, une palette rapide et six formes vectorielles originales : arrondi, rectangle, pilule, nuage, étoile et cœur. L'opacité reste indépendante. Les formes suivent le texte, sa position et ses animations. La sélection « toute la piste » existante s'applique aussi à ces propriétés.

Le champ Codable optionnel `textBackgroundShape` conserve `.rounded` comme valeur par défaut pour les anciens documents. Preview et export utilisent TextRasterizer, avec une clé de cache incluant la forme. Les formes décoratives réservent une largeur de texte plus étroite.

Validation exécutée :

- 56 CoreTests et 3 TextRenderingTests : passage, sauvegarde/rechargement, compatibilité des anciens documents, portée piste, variantes, undo et six rendus distincts.
- Export MP4 court avec nuage rouge : fichier décodé et présence de pixels rouges vérifiée.
- iPhone : sélection de quatre formes et test existant du panneau Style compact passent.
- iPad : sélection de quatre formes passe.
- Captures des six rendus vectoriels et captures UI iPhone/iPad obtenues. Nuage, étoile, cœur et captures UI inspectés.
- Compilation physique, installation et lancement sur l'iPad connecté réussis. Pas de test de gestes exécuté sur cet iPad physique.

Résultats temporaires : `/private/tmp/CutFuze-TextBackdrops-20261009.xcresult`, `/private/tmp/CutFuze-TextBackdrop-Export-20261009.xcresult`, `/private/tmp/CutFuze-TextBackdrops-Visible-iPhone.xcresult`, `/private/tmp/CutFuze-TextBackdrops-Visible-iPad.xcresult`.

Captures conservées ici : `iphone-cloud.png`, `ipad-heart.png`.

Limites : les fonds suivent un bloc de texte, pas chaque ligne individuellement. Pas de dessin libre, de fond image ni de réglage indépendant des marges du fond.
