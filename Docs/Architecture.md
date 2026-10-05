# Architecture de CutFuze

Le document `ProjectDocument` est la seule représentation éditable du montage. Scénario, Timeline, comparaison de formats, aperçu et export compilent le même snapshot avec `RenderPlan.compile(document:variantID:)`. L’application initiale du dépôt était un écran SwiftUI « Hello World » : aucun format de montage antérieur n’a été trouvé.

## Modèle et invariants

Les types de `Core/ProjectDocument.swift` sont des valeurs `Codable`, `Equatable` et `Sendable`, sans AVFoundation ni UI. Le document conserve les UUID des médias, scènes, instances, variantes et keyframes. Une scène possède ses clips locaux ; `globalClips` contient les éléments ancrés au projet. Aucun index aplati n’est persisté. L’appartenance à une scène ne dépend jamais de sa proximité à l’écran.

`MediaTime` contient un entier Int64 et une échelle Int32, habituellement 60 000 ticks/seconde. Les additions utilisent un dénominateur commun entier quand il tient dans CMTime ; égalité et hachage normalisent les fractions. Les temps source, local du clip, local de scène et de composition sont nommés séparément. Les intervalles visibles sont `[début, fin)`. Les durées d’une scène sont explicites : une couche ne peut pas la dépasser lors d’une validation. Les couches globales peuvent prolonger le projet ; cette durée est visible dans le plan compilé.

La validation refuse les identifiants répétés, les références orphelines, les chemins absolus/traversants, les temps négatifs ou trop longs, les valeurs non finies, les plages source dépassant le média, les formats invalides et les surcharges visant un clip absent. Les plafonds du document sont 7 jours par temps, 10 000 scènes, 20 000 médias, 100 000 clips et 100 variantes. Ils limitent les entrées manifestement excessives ; ce ne sont pas des engagements de performance iPhone.

Les scènes s’enchaînent avec un chevauchement sortant. Chaque transition est bornée à la moitié de chacune des scènes voisines : les deux transitions d’une scène courte ne consomment jamais plus que sa durée. La durée est la somme des scènes moins les chevauchements, éventuellement prolongée par des couches globales. Un déplacement transporte les enfants et la transition sortante ; la transition est bornée à nouveau pour ses nouveaux voisins. La dernière scène n’a pas de transition sortante effective.

## Édition et historique

`EditHistory.perform(name:_:)` mute une copie, recalcule les sous-titres liés, valide, puis publie une seule entrée avant/après. Une erreur ne modifie pas le document. Les gestes utilisent `beginTransaction`, `updateTransaction`, `commitTransaction` et `cancelTransaction`. Annuler ou rétablir conserve les UUID historiques mais incrémente la révision courante : un ancien résultat asynchrone ne doit jamais être pris pour le document courant. L’interface complète ce mécanisme par un numéro de requête d’aperçu.

`DocumentEditor` regroupe les opérations de réorganisation, duplication, suppression, split de clip/scène, regroupement, trim, déplacement de propriétaire et surcharge. Une duplication crée des UUID d’instances ; elle partage les fichiers médias immuables et copie les surcharges des trois formats. L’historique conserve jusqu’à 100 commandes. Les médias ne sont pas supprimés automatiquement lorsque leur dernière instance visible disparaît, afin de préserver undo et les autres projets.

Un split de clip ne crée pas de scène. Un split de scène conserve un côté sous le même UUID et crée l’autre. Il découpe les plages source, conserve la courbe de vitesse dans le domaine source absolu, et conserve les keyframes originales avec un `animationOffset`. Le `effectSeed` reste identique pour que grain et shake ne redémarrent pas à la coupe. Les enveloppes audio utilisent également la durée d’animation originale. Le regroupement de scènes adjacentes à coupe franche décale leurs clips locaux sans changer le rendu. Une scène avec une transition interne ne peut actuellement pas être regroupée : l’action produit une erreur explicite. Un split trop proche d’une transition est refusé pour ne pas modifier le chevauchement lors du recalcul des bornes.

## Formats, temps et sous-titres

Les variantes 9:16, 1:1 et 16:9 partagent scène, médias, texte, timing, effets et audio. Chaque variante peut remplacer le bloc `Presentation` d’une instance, sans copier les médias. Les coordonnées sont relatives au canevas ; échelle, rotation, masque et texte sont indépendants de la résolution. Les keyframes communes sont évaluées par rapport à la présentation commune puis composées sur le cadrage local : deltas pour x/y/rotation, ratios pour échelle/opacité. Un zoom animé ne remplace donc pas le cadrage carré. Le bloc de présentation local est entièrement explicite : modifier une présentation commune ne détruit pas ce bloc ; réinitialiser la surcharge restaure l’héritage.

`TimeMapping` interpole la vitesse linéairement en temps source. Il intègre analytiquement `1/v(s)` sur les segments, et inverse cette intégrale par une recherche monotone bornée. La lecture inverse inverse le sens source séparément. Les valeurs proposées sont 0,1× à 100×. Les profils Progressif, Décélération, Impact et Plateau sont des points définis localement, sans prétention de reproduire un profil propriétaire.

Les captions sont des clips texte. Les imports SRT sans provenance sont ancrés au projet. Une transcription liée garde UUID du média et de l’instance source, début/fin source et révision analysée dans le document. `CaptionBindingUpdater` projette ces temps après une commande, les coupe à la plage réellement visible, les place dans la scène du média et les répartit lors d’un split. Modifier une note de narration ne modifie aucun enregistrement ni sous-titre. SRT et VTT exportent les temps de composition.

## Persistance locale

`ProjectStore(rootURL:)` enregistre les manifestes dans `Projects/<UUID>/manifest.json`. Les médias référencés utilisent des chemins relatifs à `rootURL`, généralement `Assets/...`. Un doublon de projet partage ces chemins mais possède un document indépendant. Les opérations du magasin sont sérialisées par un verrou récursif ; ses méthodes sont utilisables depuis une tâche détachée.

Une sauvegarde valide et encode avant toute écriture. Le manifeste précédent valide est conservé sous `previous.json`, puis le nouveau manifeste est écrit atomiquement. Le chargement récupère cette copie si le manifeste courant est endommagé et répare atomiquement le manifeste. Une version future incompatible n’est jamais remplacée par une ancienne sauvegarde. Le succès de `save(document:)` signifie une écriture réussie ; le statut de l’interface doit suivre ce résultat.

Le schéma courant est v2. Une fixture de développement v1 (même graphe de scènes, sans collection/révision/variantes) est migrée sur une copie en mémoire puis validée. Le test démontre ce contrat défini ; il ne prétend pas importer un document d’une ancienne application inexistante, d’un éditeur tiers ou d’un format non documenté. Les autres numéros de version sont refusés.

## Transport autonome

`PortableProject.export(document:rootURL:to:)` et `importPackage(from:into:)` utilisent un conteneur binaire documenté `.cutlabproject` : signature ASCII `CFUZPK02` (8 octets), longueur UInt64 big-endian du manifeste JSON, JSON puis fichiers bruts dans l’ordre annoncé. Ce format sans compression évite les bombes de décompression. Ce n’est pas une archive ZIP renommée.

Le JSON contient version 2, snapshot de document et liste `{path, byteCount, sha256}`. Les médias sont dédupliqués par SHA-256 et renommés sous `Assets/<sha256>.<extension>`. Aucun fichier non référencé ne peut être embarqué. Les liens symboliques et chemins dangereux sont refusés. La lecture, la copie et le calcul SHA-256 utilisent des blocs de 1 MiB ; aucun film complet n’est chargé en mémoire. Le manifeste est limité à 32 MiB, le paquet à 8 GiB et 20 000 fichiers. Taille annoncée et nombre réel d’octets sont contrôlés, les empreintes doivent correspondre et les données finales non déclarées sont refusées.

L’export écrit un fichier temporaire voisin puis le remplace par renommage atomique après synchronisation. Si les sources changent pendant la copie, l’empreinte finale invalide l’export. L’import écrit sous `.Import-<UUID>`, vérifie tous les fichiers, installe par déplacement dans `Imports/<UUID>` puis sauve un document avec un nouvel identifiant. Toute erreur ou annulation nettoie la préparation et ne remplace aucun projet existant. Les références importées sont relatives au nouveau stockage. Le test supprime entièrement le dossier source avant de rouvrir, modifier et réexporter dans un autre stockage.

## Validation et limites connues du noyau

Les tests XCTest couvrent round-trip, fixture v1, refus de version future, historique et transaction annulée, réorganisation avec ancrage global, duplication sans médias copiés, split/regroupement à coupe franche, variantes isolées, intégrale de vitesse et inversion, ripple, sous-titres, récupération de manifeste, transport autonome, falsification d’empreinte, troncature, traversal, chemin absolu, liens et limites réelles.

Restent limités : regroupement au travers d’une transition ; hiérarchie d’ancrage à une source autre que les captions ; suppression automatique de médias non utilisés ; diagnostic par projet dans la bibliothèque si un manifeste et sa sauvegarde sont tous deux irrécupérables ; migration d’un éventuel format externe réel (aucune spécification fournie). La persistance de surcharges de keyframes propres à un format n’est pas encore distincte des keyframes communes. Les limites de charge sont des contrôles de ressources, pas des benchmarks.

Le script `Scripts/run-core-tests.sh` compile le noyau avec Swift 6 et exécute les mêmes XCTest via le framework natif macOS, sans simulateur ni résolution de dépendances. Lors de la validation du 5 octobre 2026 : **29 tests, 0 échec**, durée de suite 0,080 s. Le journal réel est `Docs/Evidence/core-native-tests.log`. Cette exécution macOS ne remplace pas les tests iOS, le rendu ni les essais appareil.

L’éditeur de sous-titres liste les vrais clips et permet correction, saisie de bornes, scission avec deux textes explicites, fusion de voisins compatibles et copie de style à tous avec portée commune ou format actif. Les temps des captions liées sont reconvertis au domaine source, y compris pour une lecture inverse. Une fusion de sources/propriétaires incompatibles échoue explicitement ; le détachement de provenance est une action séparée. Les variantes du premier segment sont conservées lors de fusion et copiées lors de scission. Chaque action est une commande annulable. Les champs de tracking/interligne sont en em, décodés à zéro quand absents et rendus par CoreText. Tests natifs couvrent provenance, retiming ultérieur, undo, isolation de style et compatibilité du décodage.

## Extensions compatibles de présentation

CanvasSettings optionnel par variante : couleur unie, image persistée ou copie floutée du média actif. Les anciens documents sans ce champ gardent leur rendu. Deux champs d’espacement texte en em sont décodés à zéro par défaut et rasterisés par CoreText. BeatMarker est un temps absolu de projet, utilisé comme guide et cible de snapping ; il ne se rend pas dans le MP4 et ne se déplace pas avec une scène.

Les effets peuvent avoir une plage demi-ouverte et des points d’intensité. Leur temps est celui de l’animation du clip (`local + animationOffset`), afin qu’une découpe ne redémarre ni l’enveloppe ni l’effet. Les champs optionnels conservent les anciens documents. Le renderer et la feuille d’aperçu utilisent la même fonction d’évaluation.

CaptionEditing centralise correction de texte/temps, inverse mapping vers la source, scission avec textes explicites, fusion entre voisins compatibles et styles communs/par variante. La fusion de sources ou propriétaires différents est refusée. Aucun alignement mot à mot n’est déduit artificiellement de la longueur des mots.

### Édition des images clés

`AnimationEditing` reconvertit la pose affichée d’un format vers le domaine commun : écarts pour position/rotation, rapports pour échelle/opacité. La commande d’ajout met à jour un point existant au même temps rationnel et à la même propriété, conserve son identifiant et son interpolation. Les formats restent isolés dans leurs cadrages. Les temps de navigation excluent les clés hors du segment visible après une scission ; les clés historiques sont conservées pour maintenir la phase d’animation.

L’éditeur propose le point précédent/suivant, la propriété, la valeur, l’interpolation d’arrivée et un aperçu du brouillon. Les fondus d’entrée/sortie/combinaison ont une durée réglable et ajoutent seulement leurs points d’opacité aux bornes ; les autres clés restent en place. Les modifications passent par l’historique et la sauvegarde commune. Trois tests couvrent la conversion multi-format, les clés après scission et la conservation des points manuels avec annulation des fondus.
