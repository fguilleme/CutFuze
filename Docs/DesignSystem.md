# Système visuel CutFuze

## Intentions et composants

Bibliothèque ivoire #F6F3EE ; atelier encre #15191F ; panneaux #232A33 ; accent ambre #EBA65A et repères menthe. Tokens centralisés dans UI/DesignSystem.swift. Typographie système : titres éditoriaux serif en bibliothèque, sans-serif pour les commandes, chiffres monospaces pour le temps. Aucune police redistribuée.

Icône : trois cadres de ratios différents dessinés par Scripts/generate-icon.swift. Aucun ruban croisé. L’ancienne image « Neon Film Ribbon Cut Icon.png » déposée par l’utilisateur reste intacte, hors bundle. Les médias de démonstration sont des dessins géométriques UIKit, avec son WAV synthétique.

Bibliothèque : une action principale Nouveau projet ; cartes de documents rendues par le moteur ; recherche/collections ; espace d’exemples distinct des documents. L’éditeur utilise une vue d’aperçu permanente et un inspecteur de propriétés. Les modes Scénario/Timeline exposent les mêmes objets.

## Disposition

Portrait : en-tête, aperçu, transport/formats, inspecteur intégré lorsqu’il est ouvert, zone d’édition et quatre entrées Image/Son/Texte/Animation. Paysage : aperçu et inspecteur côte à côte, édition en dessous. Réglage d’inversion dans la bibliothèque. Fermer l’inspecteur et quitter le projet sont deux étapes distinctes.

Timeline UIKit : canevas limité au viewport pour éviter une texture de la longueur du film ; en-têtes fixes ; lignes distinctes pour couches texte et audio. Les clips de scène suivent le groupe ; les pistes globales ont un repère d’ancrage. Les vignettes sont calculées par le moteur et les formes d’onde depuis les échantillons audio. Les vignettes de timeline sont actuellement des aperçus de scène, pas une bande de frames par clip.

Zones visées : 44 pt sur transport et barre d’outils ; sélection/trim du canevas arbitrés par zones de bord. La précision est aussi accessible via une fenêtre numérique. Le code utilise les labels VoiceOver des actions et des clips visibles, et les contrôles natifs. Une qualification complète Dynamic Type/VoiceOver/contraste sur appareil reste nécessaire.

## Inspection effectuée

Premiers écrans inspectés sur iPhone 18 Pro simulé : bibliothèque, scénario, timeline, inspecteur. Corrections : séparation des pistes de titres/sous-titres qui se chevauchaient visuellement ; rendu de timeline limité à la zone visible ; invariants cadrage/keyframes réparés. Les captures finales et résultats du parcours UI sont consignés dans ValidationReport.md. Aucune comparaison pixel avec un concurrent.

## Inspection petit écran exécutée

Parcours XCUITest complet sur le simulateur dédié « CutFuze Compact », iPhone SE3,375×667points, iOS27 : PASS (CompactUIValidation). Captures portrait et paysage inspectées. L’aperçu reste visible ; l’inspecteur et les pistes ont un défilement indépendant. Sur375points, seuls les premiers réglages et la première piste sont visibles simultanément : les suivants sont accessibles par scroll. En paysage, l’intitulé du segment de portée peut être tronqué, mais le ratio reste présent dans le sélecteur de transport. Ce résultat ne vaut pas validation VoiceOver ou texte agrandi.

Les panneaux captions, images clés et effets gardent désormais leur aperçu dans un inset fixe au-dessus de la liste de réglages. Le preview fait160points en portrait et80en paysage ; le formulaire seul défile. Ce changement corrige la disparition du preview constatée en inspectant les captures de captions.

Inspection finale ProMax effectuée sur les captures ReleaseCandidateValidation : aperçu fixe des captions visible après défilement, paysage utilisable avec pistes défilantes. Les boutons Ajuster/Remplir peuvent se répartir sur deux lignes dans l’inspecteur étroit en paysage ; amélioration de densité typographique restante. Aucun rapprochement pixel à pixel avec un produit concurrent.
