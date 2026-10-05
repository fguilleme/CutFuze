# Matrice fonctionnelle

5 octobre 2026. Un statut « IMPLÉMENTÉ ET TESTÉ » signifie qu’une preuve exécutée couvre le périmètre décrit, pas tous les appareils ou toutes les interactions possibles. Les résultats et limitations précis sont dans ValidationReport.md et KnownLimitations.md. Une compilation seule n’est pas une validation visuelle.

| Fonction | Statut | UI | Document/persistance | Aperçu | Export | Preuve/périmètre |
|---|---|---|---|---|---|---|
| Bibliothèque/recherche/collections | IMPLÉMENTÉ ET TESTÉ | Cartes, menus, recherche | Manifestes/UUID | Vraies vignettes | Sans objet | WorkspaceUITests ouvre et rouvre ; pas chaque menu automatisé |
| Import Photos multiple/ordre | PARTIEL | Sélecteur système + revue réordonnable | Copie durable | Images réellement décodées | Originaux durables | Moteur testé ; parcours Photos/iCloud complet restant |
| Import Fichiers audio/vidéo/image | IMPLÉMENTÉ ET TESTÉ | Sélecteur avec accès sécurisé | Copie en blocs + SHA-256 | Vignettes et waveform | Mêmes sources | MediaTests corrupt/missing/orientation ; UI fournisseur restant |
| Scénario : narration et calques | IMPLÉMENTÉ ET TESTÉ | Cartes éditables + propriétés | Scènes/enfants/note distincte | Plan commun | Plan commun | CoreTests et parcours UI réel |
| Scénario : réordre/duplication/suppression | IMPLÉMENTÉ ET TESTÉ | Menu + drag/drop | Commande atomique/UUID/surcharges | Enfants suivent | Musique globale fixe | CoreTests réordre/undo ; menu réel UI |
| Scinder/regrouper des scènes | PARTIEL | Menus explicites | Conserve temps/animation/surcharges | Continu à coupe franche | Même plan | CoreTests ; refuse transition interne |
| Scénario ↔ Timeline | IMPLÉMENTÉ ET TESTÉ | Sélection/temps/format communs | Un seul document | Un renderer | Un renderer | WorkspaceUITests + invariants noyau |
| Variantes 9:16/1:1/16:9 | IMPLÉMENTÉ ET TESTÉ | Sélecteur/comparateur | Surcharges de présentation | Même instant comparé | Lot séquentiel même snapshot | CoreTests, MediaTests et DeliveryTests |
| Cadrage local et héritage | IMPLÉMENTÉ ET TESTÉ | Portée/reset | Bloc local explicite | Animation commune + delta local | Identique | Isolation/split/duplication/round-trip tests |
| Keyframes propres au format | NON IMPLÉMENTÉ | Non proposées | Seulement keyframes communes | Cadrage local conservé | Idem | Écart : pas de trajectoire locale distincte |
| Transport .cutlabproject | IMPLÉMENTÉ ET TESTÉ | Exporter/Importer | Manifestes+fichiers SHA-256 | Réouvre depuis autre racine | Réexport depuis copie | MediaTests supprime source ; Delivery30s et3ratios |
| Sécurité/intégrité du transport | IMPLÉMENTÉ ET TESTÉ | Erreur explicite | Stage/limites/chemins/symlinks | Aucun fichier corrompu substitué | Snapshot validé | CoreTests traversal/hash/troncature/cancel/collision |
| Sauvegarde/reprise/migration | IMPLÉMENTÉ ET TESTÉ | Statut après succès | Atomique + previous.json/v1 défini | Réouverture | Snapshot | CoreTests recovery/version ; UI reopen |
| Undo/redo transactionnel | IMPLÉMENTÉ ET TESTÉ | Boutons et un geste=une entrée | 100 snapshots, révisions monotones | Rafraîchissement réel | Document final | CoreTests + drag/undo/redo UI |
| Timeline multipiste/zoom/scrub | PARTIEL | Dessin viewport, zoom, scroll | Temps rationnels | Seek coalescé | Même mapping | UI timeline ; pas de filmstrip/proxies/perf physique |
| Trim/déplacement/snapping/ripple | IMPLÉMENTÉ ET TESTÉ | Gestes + saisie précise | Commandes ancrées | Preview après commande | Bornes identiques | CoreTests ; gestes exhaustifs restant |
| Découpe/duplicate/remplacement/extraction/freeze | IMPLÉMENTÉ ET TESTÉ | Menu sélection | Non destructif, source originale | Effets une seule fois sur freeze | Rendu partagé | CoreTests split ; MediaTests mapping ; remplacement UI restant |
| Vitesse0,1–100/courbes | IMPLÉMENTÉ ET TESTÉ | Points/profils originaux | Intégrale1/v et inverse | Temps source identique | Courbe réelle + audio20ms | CoreTests analytique ; MediaTests vidéo/impulsions |
| Reverse | IMPLÉMENTÉ ET TESTÉ | Commande annonce son coupé | Mapping source décroissant | Décodage image exact | Timestamps croissants | MediaTests vidéo inversée |
| Transitions8 | IMPLÉMENTÉ ET TESTÉ | Scène/durée/brouillon | Chevauchement borné | Rendu réel | Rendu réel | Huit signatures pixels distinctes |
| Ajustements/effets18 | IMPLÉMENTÉ ET TESTÉ | Sliders/valeurs/reset | Paramètres persistés | CI réel, neutre bypass | CI identique | MediaTests catalogue/neutre |
| Courbes RGB/HSL | NON IMPLÉMENTÉ | Non proposées | Absent | Absent | Absent | Validation complète non réalisée |
| Plages d’effets et intensité animée | IMPLÉMENTÉ ET TESTÉ | Feuille temps/points/easing/aperçu | Champs optionnels compatibles | Même évaluation, borne exclue | Même renderer | MediaTests rendu/bornes/legacy/split passés FinalValidation |
| Piste d’effets globaux | NON IMPLÉMENTÉ | Effets attachés clips | Pas de piste dédiée | Clip uniquement | Clip uniquement | Écart au cahier |
| Keyframes de transformation/opacité | IMPLÉMENTÉ ET TESTÉ | Ajout/édition/suppression/précédent/suivant/easing | x/y/scale/rotation/opacity + easing | Même évaluateur | Même évaluateur | CoreTests conversion/IDs/easing/split passés iOS |
| Animations entrée/sortie/combinaison | IMPLÉMENTÉ ET TESTÉ | Fondus entrée/sortie/combiné, durée, mouvement doux | Keyframes et phase conservée | Temps du document | Temps du document | CoreTests iOS fondus/undo/conservation points manuels |
| Superpositions et ordre | IMPLÉMENTÉ ET TESTÉ | Ajout/transformation/temps/couche | Scene ou global | Composition CI | Identique | MediaTests plusieurs couches |
| Fusion6/masques | IMPLÉMENTÉ ET TESTÉ | Forme/position/rotation/feather/inversion | Présentation variante | CI réel | Identique | MediaTests six fusions/masque tourné |
| Chroma/pipette | IMPLÉMENTÉ ET TESTÉ | Source orientée/brouillon/validation | Couleur/tolérance/douceur | Pixels sRGB + spill | Identique | Tests coordonnées/alpha/couleurs/renderer |
| Canevas/fonds/ratios | IMPLÉMENTÉ ET TESTÉ | Uni/image/flou,4:5/original | Canvas par variante optionnel | Renderer commun | Dimensions et fond réels | CanvasTests legacy/pixels/MP4 |
| Audio montage/mix/fades | IMPLÉMENTÉ ET TESTÉ | Pistes et Son | Gain/enveloppes/ancrage | AVAudioMix | Même mix | Impulsions A/V et exports audio |
| Ducking et marge de mixage | PARTIEL | Ancrage voix-scène/musique-projet | Enveloppe déterministe | Baisse12dB + marge0,80 | Même mix | AAC pic décodé testé ; pas limiteur universel |
| Repères rythmiques | IMPLÉMENTÉ ET TESTÉ | Manuels, édition, dessin/snapping | Absolus au projet | Guides non rendus | Non incrustés | BeatMarkerTests ; détection auto absente |
| Voix off | IMPLÉMENTÉ NON TESTÉ | Aperçu synchronisé ou placement après prise, permission/countdown/niveau/casque | Fichier durable puis clip au temps choisi | Vrai enregistreur et vidéo de référence | Audio normal | Compilation appareil ; microphone/intelligibilité et synchronisation physique à qualifier |
| Synthèse vocale | IMPLÉMENTÉ NON TESTÉ | Voix système/langue/débit | CAF vérifié puis clip | Audio normal | Audio normal | Compilation ; pas échantillon vocal validé |
| Transcription locale | IMPLÉMENTÉ NON TESTÉ | Source/langue/style/progrès/cancel | Temps source/révision | Segments éditables | Captions incrustées | Ressource et parole réelle non testées |
| Texte multiligne/style | IMPLÉMENTÉ ET TESTÉ | Police/taille/alignement/couleur/contour/fond/espacement | Présentation commune ou locale | CoreText | Incrusté identiquement | Pixels accents/écritures/bornes ; polices spécifiques à vérifier |
| Sous-titres SRT/VTT/remapping | IMPLÉMENTÉ ET TESTÉ | Import/export/édition | Provenance liée ou temps global | Bornes demi-ouvertes | Incrustation + fichiers | CoreTests vitesse/split/provenance/SRT |
| Captions fusion/scission/style commun | IMPLÉMENTÉ ET TESTÉ | Éditeur segments | Commandes et limites provenance | Textes/timings communs | Identique | CoreTests captions édition |
| Karaoké/traduction | PARTIEL | Traduction optionnelle lors de la génération | Traduction locale par segment, temps conservés | Sous-titres traduits | Incrustation et export habituels | Traduction Apple locale intégrée ; karaoké et temps mot à mot absents |
| Segmentation personnes | IMPLÉMENTÉ NON TESTÉ | Toggle Vision | Paramètre persistant | Masque local réel | Même masque | Compilation ; corpus humain requis |
| Suivi Vision | IMPLÉMENTÉ ET TESTÉ | Région/cible/confiance | Trajectoire keyframes | Réel sur source | Keyframes éditables | VisionTests rectangleH264/orientation/baseline locale |
| Stabilisation | IMPLÉMENTÉ ET TESTÉ | Force/crop/analyse/validation | Keyframes calculées | Translation corrigée | Même rendu | RMS réellement rendu4,0983→0,6111px |
| Interpolation/séparation/beauté/génération | NON IMPLÉMENTÉ | Aucun faux bouton | Aucun service simulé | Absent | Absent | Pas de modèles et corpus validés |
| 12 modèles et démonstration | IMPLÉMENTÉ ET TESTÉ | Choisir/preview/remplacer/éditeur | Documents ordinaires | Vrais médias synthétiques | Export normal/portable | ServiceTests12signatures ; Delivery30s |
| Stickers/formes/styles locaux | PARTIEL | Forme générée/masques/styles texte | Clipshape/text | Vrai rendu | Identique | Bibliothèque de formes encore réduite |
| Export MP4 réglé/vérifié | IMPLÉMENTÉ ET TESTÉ | Codec/cadence/débit/dimensions | Snapshot figé | Relecture lecteur | Writer réel/validation | MediaTests/Delivery ; matériel4KHEVC restant |
| Annulation/relance/remplacement | IMPLÉMENTÉ ET TESTÉ | Progression/cancel | Original préservé | Reprise possible | Temp puis rename atomique | MediaTests cancel/retry/replace/missing |
| SDR/HDR/VFR | PARTIEL | SDR explicite | Cadence rationnelle | forceSDR vidéo | Rec.709 | SDR testé ; HDR/VFR réel non qualifié |
| Photos/partage | IMPLÉMENTÉ NON TESTÉ | API système déclenchée par utilisateur | MP4 conservé si refus | Relecture disponible | MP4 déjà terminé | Photos refusé/partage matériel restant |
| Portrait/paysage/disposition inversée | IMPLÉMENTÉ ET TESTÉ | Preview+inspecteur côte à côte | Préférence locale | Sélection/temps préservés | Sans effet sur vidéo | WorkspaceUITests rotation/captures |
| Accessibilité/localisation | PARTIEL | FR/EN, labels/valeurs/zones | Préférence système | Sans effet sur rendu | Sans effet sur rendu | Captures et inspection ; recette VoiceOver/DynamicType complète restante |
| Hors ligne/confidentialité | PARTIEL | Sans compte | App ne transfère pas les médias | Moteur local | Local | Inspection absenceAPIréseau ; modeavion matériel restant |
| Publication AppStore | BLOQUÉ | Brouillons exacts | Manifestes/permissions | Captures réelles | Non soumis | Identité/URL/support/droitsnom et recette physique requis |
