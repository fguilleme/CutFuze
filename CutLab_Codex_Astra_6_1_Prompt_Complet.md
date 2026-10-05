# CutLab — Cahier autonome pour Codex / Astra 6.1

## Version indépendante : Scénario, Timeline et projets multiformats

Révision du 5 octobre 2026. Ce document remplace le prompt de reproduction de CapCut. Il sert à construire une application indépendante et à documenter ses vérifications ; il ne garantit pas son acceptation App Store.

## 1. Mandat, remplacement du cahier initial et autonomie

Tu es l’agent de développement chargé de livrer une véritable application iPhone native, pas un plan ni une maquette. Travaille dans le workspace courant avec les outils et autorisations réellement disponibles. Livre code, projet Xcode, ressources originales, tests et preuves d’exécution.

Ce document REMPLACE INTÉGRALEMENT le précédent cahier « Prompt_CapCut_iPhone_Astra_6_1 ». Les anciennes exigences de reproduction des écrans, des parcours, des proportions, des couleurs et de fidélité visuelle à CapCut sont abandonnées. Les exigences techniques utiles sont reprises ici ; il n’est pas nécessaire de disposer du document antérieur.

Construis un éditeur indépendant : nom interne CutLab, sauf nom de projet déjà défini. Ce nom est provisoire et sa disponibilité commerciale n’est pas vérifiée. L’objectif est un atelier de montage narratif et multiformat, disposant des capacités d’un éditeur mobile avancé, et non une application concurrente simplement rebaptisée.

Trois caractéristiques structurent réellement le produit : deux vues Scénario et Timeline du même montage ; plusieurs formats de sortie partageant ce montage ; des projets locaux transportables avec leurs médias. Elles ne doivent pas être des onglets décoratifs ajoutés à une interface copiée.

Si le développement a déjà commencé, audite l’existant et réutilise le moteur, les traitements, les tests et les composants génériques qui fonctionnent. Remplace l’expérience imitative, pas arbitrairement tout le code. Prévois des migrations testées pour les documents existants, sans perte de médias, de montage ou de réglages. Ne modifie pas une autre application présente dans le workspace. Si le dossier ne contient que des projets sans rapport, crée un sous-dossier CutLab clairement isolé.

Lis les instructions locales applicables, dont AGENTS.md. Ne les écrase pas pour imposer ce cahier. Dans la documentation de ce projet, marque les anciennes spécifications de copie comme obsolètes et remplace leurs prescriptions actives ; conserve leur historique. N’utilise pas une réécriture de l’historique Git, un reset destructif ou la suppression de fichiers utilisateur pour repartir proprement.

« One shot » signifie une seule consigne suivie de cycles autonomes d’implémentation, compilation, test et correction. Décide sans validation intermédiaire pour les choix ordinaires. Un plan court est utile mais ne constitue pas la livraison. Ne t’arrête pas au premier écran fonctionnel. Si une ressource manque, poursuis ce qui reste possible et documente le blocage sans inventer un résultat.

Ne publie rien, ne pousse pas sur un dépôt distant, ne soumets pas à TestFlight/App Store, ne souscris pas de service et n’engage pas de dépense sans autorisation. Ne désactive pas les contrôles de sécurité de l’environnement. Une signature absente ne doit pas empêcher les validations simulateur qui restent possibles.

## 2. Références, originalité et niveau de certitude

Utilise les références officielles en annexe. Les sources Apple servent à vérifier les API, les contraintes de distribution et les pratiques de plateforme. La documentation CapCut sert uniquement à inventorier des besoins et des résultats de montage ; elle ne constitue plus une spécification d’interface à suivre.

Pour toute fonction tirée d’une source concurrente, distingue Mobile, Desktop et Web. Note ce qui est confirmé, inféré ou propre à CutLab. Ne déduis ni une version ni une disponibilité iPhone d’une capture non identifiée. Ne présente aucune courbe, aucun modèle ou paramètre propriétaire comme reproduit exactement.

Crée Docs/ReferenceAudit.md : source, URL, date réelle de consultation, plateforme concernée, enseignement utile et incertitude. Les références techniques reprises du cahier initial doivent être revérifiées à l’usage ; l’existence d’un lien dans ce document ne prouve pas une consultation ni la disponibilité d’une API dans le SDK local. Si l’accès Web manque, note la limite et exploite la documentation installée et le compilateur.

Conçois une expérience indépendante de bout en bout : architecture de navigation, composants, organisation des tâches, bibliothèque, modèles et identité graphique. Les conventions générales d’un éditeur restent autorisées dans ce cahier : triangle de lecture, timeline, poignées de découpe, undo/redo et gestes iOS habituels. Ne rends pas les commandes déroutantes simplement pour les rendre différentes.

Aucun logo, habillage distinctif, fichier de catalogue, modèle premium, son ou média propriétaire concurrent n’est un asset à distribuer. Aucun badge commercial, compte, flux social ou service distant fictif. Les références documentaires peuvent rester dans les documents internes ; elles ne deviennent pas un argument commercial de filiation.

Crée Docs/OriginalityAudit.md, fondé sur les écrans et fonctions réellement livrés. Pour chaque parcours clé, décris notre choix, son utilité et les similitudes génériques restantes. Ne calcule pas un pourcentage de ressemblance arbitraire et ne définis pas de seuil supposé d’acceptation Apple. La différenciation demandée est un choix de produit, pas une affirmation d’invention universellement nouvelle ni une garantie de validation.

## 3. Socle natif

Utilise Swift, SwiftUI pour la structure, UIKit lorsque nécessaire pour la timeline et les gestes précis, AVFoundation pour le média, Core Image/Metal pour le rendu, CoreText pour les textes, Photos/PhotosUI, AVFAudio et Vision selon leurs capacités publiques.

Cible minimale proposée pour un projet neuf : iOS 18. Si une cible existe déjà, conserve-la sauf nécessité documentée. Utilise le SDK réellement installé, avec contrôles de disponibilité pour les API plus récentes, notamment SpeechAnalyzer. Vérifie les signatures dans la documentation et par compilation. N’invente pas d’API. N’utilise pas aveuglément le code Objective-C des anciens guides Apple.

Livre un `.xcodeproj` ouvrable, un schéma partagé et des cibles de tests. Privilégie les frameworks Apple. Pas d’éditeur basé sur une WebView, de dépendance serveur obligatoire, de bibliothèque binaire introuvable ou de package non verrouillé. Une dépendance externe doit avoir une nécessité précise, une version fixée et une licence vérifiée.

L’application doit fonctionner sans compte. Le montage principal reste local. Aucune vidéo ne quitte l’appareil implicitement. Les téléchargements de modèles ou de ressources nécessitent une information claire ; aucune clé ne doit être codée en dur.

Ne modifie pas un Bundle ID ou une équipe de signature déjà configurés sans nécessité. Pour un projet neuf, rends ces paramètres configurables ; ne prétends pas disposer des identifiants de publication. Vérifie les comportements sur le SDK disponible, sans exiger un numéro de version de Xcode ou du modèle de l’agent supposé à partir de ce prompt.

## 4. Architecture et document de projet

Sépare le modèle de montage, les commandes d’édition, le compilateur de timeline, le rendu, l’audio, les analyses, l’export, la persistance et l’interface. Utilise des interfaces testables sans multiplier les abstractions inutiles.

Prévois notamment `ProjectDocument`, `MediaAsset`, `Track`, `Clip`, `TimeMapping`, `Transition`, `EffectInstance`, `KeyframeTrack`, `CaptionSegment`, `EditCommand`, `RenderPlan` et `ExportJob`.

Le document sérialisable est la source de vérité. Il décrit les médias, plages source, positions et durées de montage, ordre des couches, transformations, retiming, effets, masques, animations, audio, sous-titres et réglages de sortie. Identifiants stables ; pas d’objets AVFoundation sérialisés.

Utilise des temps rationnels compatibles CMTime. Sépare explicitement temps source, temps local du clip, temps de composition et échantillons audio. Ne calcule pas un montage en accumulant des approximations en millisecondes. Les intervalles sont définis sans ambiguïté, par exemple `[début, fin)`.

Chaque mutation passe par une commande annulable. Un geste continu constitue une transaction unique. Les aperçus de réglage sont temporaires jusqu’à validation ; Annuler restaure l’état antérieur. Undo/redo doit restaurer aussi les dépendances temporelles et les identifiants utiles.

Compile un snapshot immuable du document en RenderPlan versionné. Un résultat asynchrone associé à une ancienne révision ne doit jamais remplacer le résultat courant. L’export utilise son propre snapshot, même si l’édition reprend ensuite.

Ajoute des concepts explicites Scene, SceneAnchor, OutputVariant et PresentationOverride. Ce sont des propositions de responsabilités, pas l’obligation de renommer les types équivalents déjà présents. La structure doit empêcher deux vérités concurrentes entre Scénario et Timeline, ou entre variantes de format.

Les caches, le RenderPlan et les index temporels sont dérivés ; ils ne deviennent pas des documents éditables indépendants. Valide les références croisées, l’absence de cycles d’ancrage et la cohérence des durées au chargement. Une migration transforme une copie puis la valide avant de remplacer le manifeste courant.

## 5. Signature produit : Scénario et Timeline synchronisés

La vue Scénario est une représentation éditable du montage, pas une liste de notes séparée. Chaque scène affiche une vignette réelle, un titre, sa durée, une note ou un texte de narration facultatif, et les éléments associés : clips, illustrations, voix, textes et sous-titres.

L’import peut créer une scène par média principal ; l’utilisateur peut ensuite regrouper, scinder et réordonner les scènes. Le montage reste utilisable sans narration ni script. La vue Timeline permet le travail fin sur les mêmes contenus, avec limites de scènes visibles et sélection synchronisée.

Modèle recommandé : une séquence ordonnée de scènes possédant leur montage local et leurs couches liées, plus des pistes globales explicitement ancrées au projet. Le compilateur produit la timeline aplatie et les correspondances temporelles. Une architecture équivalente est acceptable si elle respecte les invariants suivants ; ne persiste pas à la fois une timeline complète et une copie indépendante dans chaque scène.

Chaque élément a un propriétaire et un mode d’ancrage explicites : scène, média source ou projet. Un élément global ne devient pas enfant d’une scène simplement parce qu’il apparaît au même instant. Le déplacement d’une scène déplace ses éléments liés ; la musique ancrée au projet reste à sa position absolue. L’inspecteur permet de comprendre et modifier cet ancrage.

Réordonner, dupliquer, supprimer, regrouper et scinder une scène sont de vraies commandes annulables. Une duplication crée des identifiants d’instances distincts et partage les fichiers média immuables. Scinder un clip dans Timeline ne crée pas automatiquement une nouvelle scène. L’action explicite Scinder la scène répartit les instances traversant la limite, préserve leurs animations et ne doit pas changer le rendu à elle seule.

Le passage d’un élément d’une scène à une autre est une opération explicite avec feedback de destination. Il ne résulte pas silencieusement d’un changement de zoom. Les mouvements de scènes doivent gérer les transitions de frontière, les éléments qui chevauchent une limite et les pistes globales selon des règles documentées et testées.

Les durées de scène et positions globales sont calculées selon une seule sémantique de montage. Une voix plus longue que les images déclenche une décision explicite : prolongation d’un plan fixe, ajout de visuel ou ajustement manuel. N’accélère pas une voix et ne rogne pas sa fin sans demande.

Le texte de narration est un brouillon éditorial, pas une transcription synchronisée par défaut. Modifier ce texte ne régénère ni ne remplace automatiquement l’enregistrement. Propose des actions séparées Enregistrer, Synthétiser et Générer les sous-titres, seulement lorsqu’elles sont réellement opérationnelles.

Changer de vue conserve document, sélection, tête de lecture, état undo/redo et format actif. La vue Scénario doit permettre un vrai montage utilisable sans obliger l’utilisateur à manipuler immédiatement des pistes minuscules.

## 6. Signature produit : un montage, plusieurs formats

Implémente des variantes 9:16, 1:1 et 16:9 dans un même projet ; ajoute Original et 4:5 lorsque le comportement est cohérent. Elles partagent les médias, les coupes, l’ordre des scènes, les vitesses, les transitions, les contenus textuels et le mixage audio. Elles ne sont pas des copies de projet.

Une variante contient les différences de présentation : cadrage, ajuster/remplir, placement et échelle des couches, mise en page des textes, marges de sécurité éditables et éventuelles keyframes de présentation. Les différences temporelles de montage ne font pas partie de cette version du multiformat.

Définis un calcul de présentation de base pour chaque ratio, puis des surcharges explicites. L’inspecteur montre la portée Commune ou Format actif avant toute modification concernée. Une surcharge peut être réinitialisée pour retrouver la présentation héritée. Ne propage jamais un réglage local à toutes les variantes par erreur, et n’annule pas leurs réglages locaux lors d’un changement commun.

Sépare les coordonnées du média orienté, du canevas logique et de l’écran. Les paramètres sont indépendants de la résolution d’export. Définis le comportement des tailles de texte, retours à la ligne, masques et animations quand le ratio change. Conserve l’aspect des médias ; aucun étirement implicite.

Propose une comparaison des variantes au même instant, avec vignettes rendues par le vrai moteur. Le recadrage manuel doit fonctionner. Un éventuel centrage sur sujet utilise une analyse réelle, demeure corrigeable et ne doit pas être annoncé comme suivi automatique si ce n’est qu’un centrage statique.

Ajoute une file d’export multiformat : choix des variantes et réglages, estimation informative, progression par fichier, annulation, erreur et relance. Tous les fichiers d’un lot utilisent la même révision figée du projet. Partage les ressources quand c’est possible, sans lancer plusieurs encodages simultanés au prix d’une saturation mémoire.

Tests impératifs : une coupe commune se retrouve dans les trois sorties ; un cadrage propre au carré ne change pas le vertical ; undo/redo restaure héritage et surcharges ; réouverture et transport du projet conservent les trois mises en page ; créer une variante ne recopie pas les fichiers média.

## 7. Bibliothèque de projets, persistance et récupération

L’accueil est une bibliothèque de travail : reprise du dernier projet, Nouveau projet, collections et recherche. Chaque carte montre vignette, titre, durée, modification et formats configurés. Les exemples sont accessibles depuis un espace Découvrir les exemples, sans flux social ni catalogue commercial simulé. Réglages reste une destination secondaire.

Les actions créer, ouvrir, renommer, dupliquer, classer et supprimer fonctionnent réellement. États vide, chargement et erreur explicites. Ne transforme pas l’accueil en copie du tableau d’onglets d’un concurrent ni en galerie de douze boutons identiques.

Sauvegarde automatique atomique, différée après les commandes et aux étapes pertinentes du cycle de vie. Sauvegardé signifie écriture réussie, pas seulement programmation d’une tâche. Prévois récupération de la dernière version valide et erreur exploitable si le disque est plein.

Le stockage durable contient manifeste versionné, originaux importés et ressources nécessaires. Vignettes, proxies, formes d’onde et analyses régénérables sont séparés. Un projet ne dépend jamais uniquement de tmp, d’une URL de sélecteur expirée ou d’un cache purgeable.

La duplication isole les paramètres sans dupliquer inutilement les originaux. Le nettoyage tient compte des références des projets et de l’historique actif. Ni rotation, ni fermeture d’un panneau, ni interruption d’export ne doit invalider le document.

## 8. Import et bibliothèque

Utilise en priorité le sélecteur système Photos pour la sélection multiple de vidéos et photos. Préserve l’ordre choisi quand l’API le permet et propose un réordonnancement avant insertion. Dans la bibliothèque interne, affiche filtres, vraies vignettes, durées et état d’import. N’exige pas un accès global à la photothèque pour un simple import. Un navigateur PhotoKit supplémentaire doit justifier son utilité et gérer l’accès limité.

Ajoute Fichiers pour vidéos, images, audio et sous-titres. Recopie les fichiers temporaires sélectionnés dans le stockage durable avant d’en dépendre. Gère les URL à accès sécurisé et les médias iCloud non téléchargés avec progression et annulation.

Accepte les formats réellement décodables sur l’appareil, notamment les médias iPhone courants. Vérifie contenu et pistes, pas seulement l’extension. Gère orientation, vidéos à cadence variable, images haute résolution, sources HDR, absence de piste audio, fichier corrompu et codec non pris en charge.

L’import ne doit pas charger un film entier en Data ou toutes ses images en mémoire. Les vignettes et proxies sont calculés en arrière-plan et mis en cache avec une politique bornée.

## 9. Interface originale et ergonomie iPhone

Conçois une interface cohérente pour ce produit, pas un habillage différent autour des mêmes écrans concurrents. Direction visuelle proposée : bibliothèque ivoire douce, atelier bleu encre, accent ambre, typographie système sobre et pictogrammes usuels ou dessinés pour cette application. Valeurs de départ centralisées dans DesignTokens : fond clair #F6F3EE ; atelier #15191F ; panneau #232A33 ; accent #EBA65A. Ce sont nos choix, modifiables pour le contraste et la lisibilité.

Crée une icône de développement originale évoquant trois cadres de formats différents ; évite les rubans croisés et tout symbole imitant une marque existante. Elle n’atteste pas la disponibilité commerciale du nom. Ressources vectorielles et icônes doivent avoir une provenance connue ; ne redistribue pas des fichiers de polices système.

En portrait, hiérarchie de l’éditeur : en-tête compact avec retour bibliothèque, titre, undo/redo et exporter ; aperçu ; transport et choix du format actif ; sélecteur Scénario/Timeline ; zone de montage ; accès à l’inspecteur Image, Son, Texte, Animation. Les propriétés affichées dépendent de la sélection. Les opérations de montage communes sont accessibles depuis une barre contextuelle courte et un menu secondaire, pas un ruban copié de catégories concurrentes.

Le réglage détaillé d’export appartient à l’espace Exporter, pas à une imitation d’un panneau observé dans CapCut. Les variantes restent accessibles pendant le montage. La bibliothèque d’effets s’ouvre depuis la propriété correspondante ; elle ne devient pas un faux catalogue Pro.

En paysage, aperçu et inspecteur sont côte à côte, timeline ou scénario en dessous ; un réglage inverse leur position. Les proportions s’adaptent à la taille disponible. Les panneaux ne recouvrent jamais intégralement la vidéo pendant une édition visuelle. Préserve sélection, format et temps à la rotation.

Dans l’aperçu, manipulation directe des couches : déplacement, rotation, échelle et guides. Les poignées d’édition ne sont pas rendues dans la vidéo. Retour ferme d’abord le panneau courant ; quitter le projet est une action distincte. Le clavier laisse visibles le texte édité et les commandes de validation.

Utilise des états de navigation explicites et des commandes réutilisables. Évite les boîtes modales empilées et les sliders sans valeur. Chaque réglage offre reset et, lorsque pertinent, une comparaison avant/après temporaire.

Zones tactiles visées : au moins 44 points, même pour une icône visuellement compacte. Arbitrage réel des poignées voisines, du scroll et des gestes. Respecte VoiceOver, contrastes, réduction des animations et agrandissement du texte dans les écrans concernés. Aucun retour important uniquement sonore ou uniquement indiqué par couleur. Fournis les chaînes françaises et anglaises centralisées.

Documente les choix dans Docs/DesignSystem.md et Docs/UserFlows.md, puis inspecte les captures réelles sur petit et grand iPhone. Une différence de couleur ne compte pas comme une refonte de parcours.

## 10. Timeline réellement utilisable

Implémente une timeline multipiste virtualisée : piste principale, superpositions, textes/stickers/sous-titres, audio et effets temporels. Affiche de vraies vignettes et formes d’onde, pas des décors répétés sans rapport avec le contenu.

Règle adaptative, tête de lecture, temps courant/durée totale, commandes d’ajout et en-têtes de pistes lisibles. Prévois un suivi automatique de lecture désactivable pendant la navigation manuelle. Affiche aussi les limites et titres de scènes. Sélection, poignées de trim, transitions et keyframes sont visibles sans surcharger la zone.

Gestes indispensables : scrub horizontal, pincement pour zoom temporel autour d’une ancre stable, trim des deux bords, appui long puis réorganisation, déplacement libre des couches secondaires, autoscroll aux bords et snapping activable. Le seuil de snapping est exprimé en points puis converti en temps.

Arbitre explicitement les gestes : un trim ne déclenche pas un scroll ; un pincement ne déplace pas le clip ; un tap ne devient pas une découpe. Coalesce les demandes de seek et abandonne les résultats obsolètes. À l’arrêt du scrub, cherche précisément l’image voulue.

Définis et teste les règles de ripple et d’ancrage. Par défaut proposé : superpositions et sous-titres liés suivent leur contenu ; une musique indépendante reste ancrée au projet. Les changements de vitesse doivent remapper les sous-titres liés, pas seulement décaler leur début.

Pour les transitions, adopte une sémantique explicite. Utilise un chevauchement : durée principale = somme des durées des clips − somme des chevauchements. Borne les transitions pour qu’elles ne consomment pas deux fois les mêmes plages d’un clip court. Documente les frontières entre scènes et les limites de chevauchement ; ce sont les règles de notre moteur.

La durée totale tient compte des couches autorisées à dépasser la piste principale. Ces prolongations doivent être visibles et intentionnelles ; aucune image noire finale ajoutée par erreur.

Les actions Timeline utilisent les mêmes commandes de document que Scénario. Le snapping peut viser une limite de scène sans changer l’appartenance d’un élément. Les éléments globaux ont un marquage distinct. Une fenêtre d’inspection temporelle offre une saisie précise quand le geste tactile ne suffit pas.

## 11. Montage de base et retiming

Implémente trim non destructif, découpe à la tête de lecture, suppression, duplication, réorganisation, remplacement du média, recadrage, rotation, miroir, volume du clip, extraction audio, arrêt sur image et lecture inversée.

Une découpe préserve la continuité des effets, de la transformation, de l’animation, des captions liées et du mapping source. Remplacer un média conserve les réglages compatibles, ajuste les bornes et signale les incompatibilités. Un arrêt sur image fige la bonne image source sans appliquer deux fois l’étalonnage.

Vitesse constante : cible 0,1× à 100×, avec valeurs directes, durée résultante et option de conservation de hauteur lorsque le traitement audio la prend réellement en charge. Expose les modes Constante et Courbe dans l’inspecteur temporel du clip, selon notre navigation.

Courbes : points ajoutables, déplaçables et supprimables, aperçu, réinitialisation et préréglages. Définis des profils originaux, par exemple Progressif, Décélération, Impact et Plateau, avec coefficients documentés. N’emprunte pas les noms ou les profils distinctifs d’un catalogue concurrent.

Définis le domaine des points. Si la vitesse dépend du temps source `s`, la durée de sortie découle de l’intégrale de `1/v(s)` ; ne remplace pas cela par une vitesse moyenne arbitraire. Construis une conversion aller/retour monotone et testée entre les domaines temporels : croissante pour la lecture directe et adaptée séparément à l’inversion.

La courbe visible doit agir sur le fichier exporté. Si un pré-rendu est nécessaire, calcule-le par blocs avec progression, cache invalidable et audio cohérent ; utilise le même résultat pour l’aperçu et l’export.

L’inversion ne doit pas reposer sur `player.rate = -1`. Génère une source dérivée en mémoire bornée, avec ordre de présentation et timestamps corrects. Prévois explicitement le traitement du son inversé ou sa désactivation, sans décision silencieuse.

## 12. Moteur partagé aperçu/export

Principe non négociable : même modèle, mêmes fonctions d’évaluation, même ordre des effets et même interprétation temporelle pour l’aperçu et l’export. La résolution d’aperçu peut être réduite, jamais le contenu fonctionnel sans indication.

Base recommandée : AVComposition/AVMutableComposition pour les pistes temporelles, composition vidéo et compositeur personnalisé AVVideoCompositing avec Core Image/Metal pour les opérations multipistes. Utilise le lecteur et l’export avec un RenderPlan commun ; un autre pipeline est acceptable seulement si sa parité est démontrée.

Gère correctement les identifiants de pistes source, les plages des instructions et les chevauchements. Prévois les montages composés uniquement de photos, les fonds générés et les intervalles sans vidéo source ; vérifie que le compositeur est effectivement sollicité.

Rendu par image : lecture et orientation source, conversion colorimétrique, traitements propres au clip, transformation/crop, masque et opacité, transitions et composition des couches, effets globaux puis conversion vers l’espace de sortie. Définis précisément les exceptions ; ne laisse pas l’ordre dépendre du chemin de code.

Textes et stickers doivent être composités dans les images vidéo, pas simplement affichés au-dessus d’un AVPlayerLayer. Prépare les ressources typographiques hors de la boucle critique et utilise le même layout pour aperçu/export.

Réutilise CIContext, ressources Metal et pools de pixel buffers. Aucun décodage lourd sur le thread principal. Les requêtes du compositeur doivent se terminer exactement une fois : image, erreur ou annulation. Gère changement de contexte, destruction et cancellation sans fuite ni attente infinie.

Les effets aléatoires utilisent une graine déterministe liée au projet et au temps. Les valeurs neutres produisent un vrai bypass avant compression. Les exports reprennent les originaux, pas les proxies de prévisualisation.

Le RenderPlan reçoit explicitement l’identifiant de variante. Sa compilation résout l’héritage de présentation avant rendu. Les modes Scénario/Timeline ne produisent pas deux pipelines différents. Une image comparative de variantes et un export évaluent le même instant du même snapshot.

## 13. Transitions, effets, couleurs et animations

Fournis un catalogue original cohérent et fonctionnel : au moins huit transitions réellement distinctes, par exemple fondu enchaîné, noir, blanc, glissement, balayage, zoom, flou et glitch. Durée ajustable, aperçu et application à plusieurs jonctions compatibles.

Crée des filtres originaux avec intensité et retour au neutre. Ajustements : exposition, luminosité, contraste, saturation, température, teinte, hautes lumières, ombres, netteté, vignette, grain et fondu des noirs. Ajoute courbes RGB et HSL si le moteur permet leur validation complète ; sinon consigne l’écart, sans sliders inactifs.

Les effets temporels ont leur propre plage et leurs paramètres. Implémente plusieurs familles visuellement différentes : flou, glow, grain, séparation RGB, pixelisation, shake, vignette et effet rétro. Les aperçus de catalogue sont générés avec le vrai moteur.

Keyframes pour position, échelle, rotation, opacité et paramètres animables. Ajout/suppression, précédent/suivant, interpolation linéaire et easing. À un instant déjà marqué, modifier met à jour le point existant. Fractionner un clip ne doit pas redémarrer son animation.

Animations d’entrée, sortie et combinaison pour clips, textes et stickers, avec durée réglable. Définis leur composition avec les keyframes manuelles. Les animations du média suivent le temps du montage, pas l’horloge d’une animation SwiftUI.

## 14. Superpositions, masques et fond

Ajoute plusieurs vidéos/images en superposition, déplacement temporel, trim, ordre des couches, transformation, opacité et modes de fusion. Implémente au minimum Normal, Produit, Écran, Superposition, Éclaircir et Assombrir avec tests de rendu.

Masques : cercle/ellipse, rectangle, rectangle arrondi, séparation linéaire et bande ; formes supplémentaires si implémentées proprement. Position, taille, rotation, inversion et contour progressif. Les paramètres animables restent cohérents entre résolutions.

Chroma key : choix de couleur à la pipette, tolérance, douceur des bords et réduction du débordement coloré. La pipette doit échantillonner la bonne couche et convertir correctement ses coordonnées et son espace couleur.

Canvas : original, 9:16, 16:9, 1:1, 4:5 et ratios supplémentaires utiles. Ajuster/remplir, fond uni, image de fond et copie floutée du média. Aucun étirement des visages. Le changement de ratio suit l’héritage et les surcharges des variantes ; les coordonnées et transformations restent cohérentes.

## 15. Audio et voix off

Vraies pistes pour audio original, musique importée, effets sonores et enregistrements. Trim, découpe, déplacement, duplication, mute, volume et fondus indépendants. L’extraction audio conserve la synchronisation et évite le doublage du son source.

Génère les formes d’onde depuis les échantillons, avec niveaux de détail adaptés au zoom. Ajoute marqueurs rythmiques manuels et détection automatique simple si validée ; ne présente pas une détection de pics comme une IA musicale propriétaire.

Enregistrement voix off avec permission microphone, compte à rebours, visualisation de niveau, lecture de référence et gestion des interruptions/changements de route. Pas de feedback audio incontrôlé.

Un mixage commun alimente aperçu et export. AVAudioMix convient aux volumes/fondus ; pour des traitements supplémentaires, utilise un véritable pipeline audio, éventuellement un rendu offline avec AVAudioEngine, puis réutilise le résultat. Un effet audible seulement en écoute ne compte pas comme implémenté.

Ajoute ducking de la musique sous la voix avec enveloppe déterministe, contrôle du niveau et prévention de l’écrêtage. Toute réduction de bruit doit être un traitement réel, nommé et évalué, pas un simple changement de gain présenté comme séparation vocale.

Synthèse vocale : voix système réellement disponibles, choix de langue/voix/débit, production d’un fichier audio durable puis insertion dans le montage. Utilise les voix effectivement disponibles et ne promets pas l’équivalence avec un catalogue propriétaire.

Les voix de narration sont liées explicitement à leur scène. Une piste musicale de projet peut traverser plusieurs scènes sans être découpée ni déplacée par leur réorganisation. Documente l’ordre de mixage, les enveloppes et la gestion des dépassements de niveau.

## 16. Texte et sous-titres

Texte multiligne éditable : police, taille, alignement, couleur, graisse, contour, ombre, fond, espacement et opacité. Styles originaux prédéfinis ; animation et manipulation directe. Affichage correct des accents, emojis et écritures prises en charge par les polices utilisées.

Depuis Texte ou la carte de narration, ouvre Générer des sous-titres : choix explicite de la source, de la langue et du style, puis génération et correction dans notre inspecteur. Présente une progression honnête, une annulation et des erreurs exploitables. Le texte généré reste intégralement éditable.

Sur les systèmes compatibles, intègre SpeechAnalyzer/SpeechTranscriber en vérifiant disponibilité, langues et ressources installées. Sur les versions antérieures, utilise un moteur public réellement disponible, tel que SFSpeechRecognizer en mode local quand il le permet. N’envoie jamais l’audio à un service distant pour masquer une indisponibilité locale.

Prévois les longues durées, formats audio, segmentation et déduplication entre blocs si le moteur de repli en a besoin. Conserve la provenance temporelle de la transcription. Pour un média identifié, stocke les timestamps source et projette-les dans le montage après coupes, vitesse et déplacement. Pour une transcription du mix final, conserve la révision analysée : si un changement rend le rattachement ambigu, marque la zone à régénérer au lieu de prétendre à une synchronisation correcte.

Stocke phrases et mots horodatés lorsque le moteur les fournit réellement. N’invente pas une précision mot à mot en distribuant uniformément les mots. Les styles karaoké utilisent de vrais temps ; une interpolation éventuelle doit être explicitement distinguée.

Correction, fusion/scission des segments, modification de durée, style commun ou individuel et application à tous. Implémente l’import/export SRT UTF-8 et l’export VTT. Les fichiers de sous-titres décrivent le temps du montage ; conserve un rattachement documenté et n’applique pas deux fois un changement de vitesse.

Ne confonds pas reconnaissance et traduction. Les sous-titres bilingues nécessitent un moteur de traduction effectivement intégré, ses ressources et une validation distincte. Sans ce moteur, conserve le montage et l’édition manuelle, et signale précisément la capacité manquante.

Les mots et phrases sont communs aux variantes ; leur placement et leur mise en page peuvent être spécifiques au format. Préserve les dates de début/fin lors d’un simple recadrage. Un style animé doit utiliser la même base temporelle que le rendu, pas une animation d’interface indépendante.

## 17. Fonctions avancées et limites des services propriétaires

Implémente aussi les fonctions avancées réalisables localement, plutôt que de les remplacer systématiquement par une roadmap.

Détourage de personnes : analyse Vision ou modèle local autorisé, masques temporels mis en cache, contour ajustable, aperçu et export identiques. Ne présente pas la segmentation de personnes comme une extraction universelle d’objets ; teste cheveux, mouvement, faible lumière et occultations.

Suivi : sélection d’une région, suivi Vision ou équivalent validé, confiance, arrêt/réinitialisation en cas de perte et conversion en trajectoire/keyframes éditables pour texte ou sticker. Une trajectoire prédéfinie n’est pas du tracking.

Stabilisation : analyse d’une vidéo importée, estimation de mouvement, lissage de trajectoire et correction avec recadrage contrôlé. Les réglages de stabilisation d’une session de capture ne stabilisent pas rétroactivement un fichier existant. Vérifie que le résultat améliore vraiment un corpus tremblant.

Ralenti interpolé, séparation vocale, effets corporels, retouche beauté et fonctions génératives : réalise ce qui dispose d’une implémentation et de ressources valides. Une API de flot optique ne suffit pas à prétendre disposer d’un interpolateur vidéo complet ; une segmentation ne suffit pas à simuler une retouche corporelle.

N’invente ni accès aux modèles/serveurs de CapCut, ni catalogue distant, ni synchronisation cloud. Pour une capacité indisponible, préserve un contrat de service propre et consigne NON IMPLÉMENTÉ ou BLOQUÉ. Ne laisse pas un bouton actif produire un faux succès. Ces exceptions ne justifient pas d’abandonner les fonctions locales exigées.

Les fonctions Scénario, variantes, montage local, transport des projets et export normal ne sont pas des dépendances à un service propriétaire : elles ne peuvent pas être reportées sous prétexte qu’un modèle d’IA manque. Une fonction non livrée reste dans la matrice interne, sans bouton de faux succès dans la version utilisateur.

## 18. Modèles originaux et ressources utilisables

Livre au moins douze modèles originaux de montage, pas douze vignettes ouvrant le même projet. Ils définissent des emplacements médias, durées, transitions, textes, animations et styles différents : portrait sous-titré, avant/après, diaporama, voyage, présentation produit, rythme musical, etc.

Le parcours doit fonctionner : choisir, prévisualiser, sélectionner les médias, remplacer les contenus, ajuster les textes, ouvrir dans l’éditeur et exporter. Un modèle instancié devient un document normal, complètement modifiable.

Bibliothèque locale de stickers/formes originales et de styles de texte. Utilise uniquement des sons et médias synthétiques ou sous licence compatible documentée. Aucun téléchargement implicite d’un catalogue propriétaire.

Les modèles instanciés utilisent les mêmes scènes, pistes et variantes que les projets normaux. Leur export portable suit les règles de la section suivante, y compris les restrictions de redistribution des ressources.

## 19. Signature produit : projets transportables et travail local

Implémente Exporter le projet complet et Importer un projet depuis Fichiers. Le paquet contient un manifeste versionné et tous les fichiers autorisés nécessaires : vidéos, photos, voix off, audio synthétisé, sous-titres, styles, références de modèles et paramètres de toutes les variantes. Extension de travail possible : .cutlabproject, avec type de document déclaré correctement dans l’application.

N’embarque ni fichiers de polices système ni ressources dont la redistribution n’est pas permise. Une dépendance manquante ou non transportable est signalée avant export. Les documents identifient les polices nécessaires et proposent un remplacement explicite si elles ne sont pas disponibles sur l’appareil de destination.

Les références internes sont relatives au paquet ; déduplique les médias identiques et vérifie leur intégrité. Les données régénérables peuvent être omises. L’export d’un projet en cours d’édition utilise un snapshot cohérent et ne modifie pas le projet source.

L’import refuse les chemins absolus ou sortant de la destination, les liens dangereux, les versions incompatibles et les archives dont le contenu décompressé dépasse les limites de ressources prévues. Vérifie le volume décompressé réel, pas seulement la taille du fichier reçu. Évite le chargement intégral d’une grosse archive en mémoire.

Importe dans une zone de préparation, vérifie les références et les médias, puis installe atomiquement une nouvelle copie. Un échec ou une annulation ne remplace pas un projet valide. Gère les collisions d’identifiants sans écraser un projet existant. Ne purge pas les originaux pour libérer la place nécessaire à l’import.

Test de portabilité : exporter un projet, l’importer dans un sandbox distinct sans accès aux chemins d’origine, rouvrir, modifier, relire et réexporter ses variantes. Ce test doit prouver que le paquet est autonome, pas simplement que le manifeste JSON a été créé.

Aucun compte, serveur, tracking publicitaire ou transfert média automatique. Le cœur du montage doit fonctionner hors ligne. Distingue clairement ce cœur local des imports depuis un fournisseur cloud et des téléchargements de ressources de transcription, qui nécessitent une connectivité. Ne prétends pas que tout est disponible hors ligne dès la première installation.

## 20. Export réel, colorimétrie et partage

Crée notre espace Exporter : choix des variantes, résolution, cadence, qualité/débit et estimation de taille, avec commandes de lancement et de suivi explicites. Expose les dimensions réelles selon le ratio ; ne transforme pas une vidéo verticale en paysage ni en carré.

Cibles : 720p, 1080p, 1440p et 2160p, avec dimensions exactes affichées pour chaque ratio, et 24/25/30/50/60 images/s lorsque prises en charge ; 120 images/s seulement si tout le pipeline et l’appareil le permettent et si cela a été testé. MP4 H.264 et HEVC suivant compatibilité vérifiée. Indique les limites plutôt que substituer silencieusement un réglage.

Si des presets AVAssetExportSession suffisent, utilise-les. Pour un débit/codec précisément contrôlé, emploie AVAssetReader/AVAssetWriter ou les API publiques appropriées. Ne crée pas un slider de bitrate qui ne modifie pas l’encodage.

SDR Rec.709 est la base obligatoire. Gère correctement les sources HDR avec conversion/tone mapping vers SDR. Une option HDR ne devient active qu’avec une chaîne réellement validée : traitement, précision, encodage, métadonnées et lecture. N’affiche pas de commutateur HDR actif sans traitement correspondant.

Respecte orientation, pixels carrés, dimensions compatibles encodeur, alpha prémultiplié, espaces couleur, cadence rationnelle et ordre de composition. Les images exportées sont datées à partir de leur index et de la cadence, sans dérive cumulative.

Mixage complet, audio synchronisé, sous-titres et overlays incrustés, effets et transitions présents, aucune image finale parasite et aucun filigrane ajouté. Les imports VFR doivent donner une sortie cohérente, pas des ralentissements aléatoires.

Progression liée au travail réel, annulation, gestion des erreurs et fichier temporaire remplacé atomiquement seulement après succès. Contrôle de l’espace disque avant et pendant les traitements longs. Ne promets pas qu’iOS laissera un export tourner indéfiniment en arrière-plan.

Après export, rouvre le fichier et vérifie pistes, durée, dimensions, cadence et images de contrôle. Distingue réussite de l’encodage, enregistrement dans Photos et partage. Un refus Photos ne doit pas faire perdre le fichier : propose Fichiers/feuille de partage système. Aucun envoi automatique à un réseau social.

Une variante conserve le même montage temporel : l’export vertical et carré d’un lot ne doivent pas raconter deux versions décalées. La politique de fin de montage et l’arrondi à la grille de cadence sont identiques. Mesure les écarts de durée dus aux conteneurs/encodeurs au lieu d’exiger une égalité binaire entre fichiers compressés.

## 21. Fluidité, accessibilité et robustesse

Virtualisation de timeline, caches bornés, proxies adaptatifs et invalidation ciblée. Ne reconstruis pas toute la composition à chaque déplacement d’un slider. Analyse, génération de vignettes et export ont des priorités et des tâches annulables distinctes.

Le projet reste modifiable pendant les tâches qui le permettent. Aucun indicateur Working permanent : chaque tâche a un état, une fin, une erreur ou une annulation. Annuler ferme réellement le traitement associé.

Mesure démarrage, ouverture de projet, latence du scrub, images perdues, mémoire maximale et durée d’export sur le matériel disponible. Distingue simulateur et appareil physique. Les objectifs de fluidité sont des cibles, jamais des benchmarks inventés.

Gère mémoire basse, chauffe, interruption audio, passage arrière-plan, média manquant et reprise. VoiceOver sur les actions essentielles, valeurs de réglages annoncées, contraste suffisant, état sélectionné pas uniquement indiqué par couleur et respect de Réduire les animations.

Teste particulièrement les conflits entre défilement vertical des scènes, réorganisation par appui long, timeline horizontale et sliders de l’inspecteur. Le mode gaucher inverse le placement prévu, sans inverser les coordonnées des médias ni le sens chronologique.

## 22. Préparation App Store et vérification indépendante

Relis les règles officielles [A1] au moment de préparer la soumission : 4.1 pour les copies et identités ; 4.3 pour les applications indifférenciées ou multipliées artificiellement ; 2.1/4.2 pour la complétude et l’utilité ; 2.3 pour des métadonnées exactes ; 5.1 pour la confidentialité ; 5.2 pour les droits sur les contenus. Cette liste n’est pas exhaustive. Un audit interne ne garantit pas l’acceptation.

Prépare Docs/AppReviewNotes.md à partir des fonctions livrées. Décris le produit par ses usages : organiser une histoire par scènes, ajuster sur timeline, préparer plusieurs formats d’un seul montage et transporter le projet. N’affirme pas que ces capacités n’existent nulle part ailleurs. N’utilise pas un discours de « clone complet » ou d’affiliation.

Prépare un projet de démonstration original d’environ 30 secondes, avec plusieurs scènes, une voix ou un son de référence, des sous-titres et trois cadrages distincts. Le bouton Ouvrir le projet exemple utilise le vrai éditeur et les mêmes traitements que tout autre projet. Ce n’est pas un mode réservé aux évaluateurs et aucun comportement ne change selon l’identité supposée du testeur.

Ajoute un parcours de test reproductible aux notes, ainsi que les limites de matériel, de langue ou de ressources réellement présentes. Un raccourci vers l’exemple permet de tester sans compte et sans accès à la photothèque. Ne déguise pas un service indisponible en fonctionnalité opérationnelle.

Crée les brouillons Docs/StoreMetadata.fr.md et Docs/StoreMetadata.en.md à partir du produit construit : nom provisoire signalé, description factuelle et captures réelles. Pas de marque concurrente utilisée comme identité ou mot-clé d’attraction ; pas de statistiques de performance non mesurées.

Établis Docs/PrivacyDataMap.md à partir des flux réellement présents, y compris SDK et téléchargements. Prépare les descriptions de permissions contextualisées, la politique de conservation/suppression et les déclarations de confidentialité pertinentes. Vérifie le manifeste de confidentialité et les raisons approuvées uniquement pour les API effectivement concernées [A6] ; ne copie pas une liste de raisons inutilisée.

Les domaines publics, le contact support, le nom commercial définitif et les informations légales de l’éditeur doivent provenir de l’utilisateur ou de la configuration existante. Ne fabrique pas une adresse ou une URL de confidentialité. Prépare les textes et les écrans locaux, puis marque l’absence des coordonnées ou URLs requises comme blocage de publication ; cela ne doit pas bloquer le montage ni les tests locaux.

Livre Docs/StoreSubmissionChecklist.md avec trois états par vérification : VÉRIFIÉ, À VÉRIFIER, BLOQUANT. Sépare audit produit, droits à confirmer, paramètres administratifs et tests techniques. Aucun score de risque inventé, aucune promesse « anti-rejet » et aucune soumission automatique.

## 23. Validation automatisée et preuves

Crée un corpus synthétique reproductible : couleurs connues, mire orientée, compteur de frames, objet mobile, alpha, tons audio, impulsions de synchronisation et sous-titres de référence. Ajoute des médias réels seulement si disponibles et autorisés. N’invente pas un test HDR ou de reconnaissance vocale faute de source adaptée.

Tests unitaires : round-trip du document, migration, undo/redo, split/trim, ripple, transitions sur clips courts, mapping de vitesse constante et variable, inversion, keyframes aux bornes, transformations après orientation, ancrage et remapping des captions, invalidation des caches et annulation asynchrone.

Tests d’intégration : montage photos uniquement ; vidéos muettes ; sources portrait/paysage mélangées ; audio extrait ; plusieurs overlays ; masques ; texte animé ; courbe de vitesse ; reprise après sauvegarde ; permissions refusées ; source absente ; fichier corrompu ; export annulé puis relancé.

Tests de rendu : pixels de référence avant compression, valeurs neutres, ordre des couches, visibilité des sous-titres à leurs bornes, effets à des temps choisis et correspondance aperçu/export. Après compression, utilise des tolérances documentées ; une égalité binaire n’est pas exigée pour un encodage avec pertes.

Teste la synchronisation audio/vidéo avec impulsions et images repères après plusieurs coupes et retimings. Cible une erreur inférieure à une image de sortie dans le corpus déterministe et documente les limites mesurées.

Scénario UI complet : créer → importer trois clips et une photo → réorganiser → découper → transition → musique → texte animé → overlay masqué → vitesse → sous-titres → sauvegarder → fermer/rouvrir → exporter → relire. Ajoute une rotation en paysage et une séquence undo/redo.

Capture réellement bibliothèque, import, Scénario, Timeline, inspecteur, variantes, sous-titres, export et transport du projet. Évalue-les contre notre DesignSystem et nos parcours, pas par rapprochement pixel à pixel avec CapCut. Conserve les défauts observés et les corrections dans le rapport ; ne fabrique pas un taux d’originalité.

Ajoute des tests dédiés aux scènes : réordonner une scène complète, déplacer ses éléments liés, conserver la musique globale, scinder/regrouper sans changement de rendu, migrer un ancien projet, alterner les deux vues après chaque opération et annuler/rétablir la transaction complète.

Ajoute les tests multiformats et portabilité définis plus haut, une session sans réseau avec ressources déjà présentes, un import cloud indisponible et un refus microphone. La transcription locale d’un fichier réel nécessite un échantillon adapté et une ressource moteur disponible ; ne remplace pas ce test par une phrase codée en dur.

Scénario de recette signature : créer trois scènes avec illustration et narration ; les réordonner dans Scénario ; ajuster une coupe dans Timeline ; corriger un cadrage uniquement en 1:1 ; modifier un texte commun ; sauver et rouvrir ; exporter 9:16, 1:1 et 16:9 ; transporter le projet dans un sandbox propre et réexporter. Vérifie toutes les propagations attendues et l’absence de propagation des surcharges locales.

## 24. Exécution, critères de livraison et compte rendu

Commence par auditer le dossier, les instructions locales, l’état du code, Xcode, SDK, simulateurs et dépendances. Lis ce document intégralement, par sections si nécessaire, sans te limiter à une sortie d’outil tronquée. Note un plan court et implémente immédiatement. Utilise des sous-agents seulement si l’environnement les fournit, avec contrats de données stables et responsabilité claire d’intégration.

Obtiens d’abord une chaîne import → document → montage → lecture → sauvegarde → export. Ensuite consolide les scènes, les variantes et la portabilité avant d’étendre les catalogues. Complète toutes les familles de montage demandées et termine par les tests, les corrections visuelles et la préparation documentaire. L’ordre est un ordre de travail, pas l’autorisation de réduire le produit à cette première chaîne.

Compile régulièrement. Après chaque changement structurel, exécute les tests concernés. À la fin, réalise une compilation propre, les suites automatisées disponibles, une inspection des captures et la relecture d’exports. Distingue résultats simulateur, appareil physique et simple inspection du code. Si l’environnement ne possède pas Xcode, livre le code et les scripts mais marque la compilation iOS NON EXÉCUTÉE ; ne la remplace pas par un faux log.

Conserve un état d’avancement concis dans Docs/ImplementationStatus.md pour pouvoir reprendre sans perdre les décisions. Le cahier complet reste dans un fichier explicite tel que Docs/ProductSpec.md ; ne colle pas des dizaines de kilooctets dans AGENTS.md. Un renvoi concis y est possible si les conventions locales l’autorisent.

Livrables : projet Xcode et schéma partagé ; code Swift/Metal ; ressources ; tests ; scripts reproductibles ; README.md ; Docs/ProductSpec.md ; Docs/ReferenceAudit.md ; Docs/Architecture.md ; Docs/DesignSystem.md ; Docs/UserFlows.md ; Docs/OriginalityAudit.md ; Docs/FeatureMatrix.md ; Docs/ValidationReport.md ; Docs/KnownLimitations.md ; Docs/ThirdPartyLicenses.md ; Docs/PrivacyDataMap.md ; Docs/AppReviewNotes.md ; Docs/StoreMetadata.fr.md ; Docs/StoreMetadata.en.md ; Docs/StoreSubmissionChecklist.md ; logs, captures et exports réellement produits.

Dans FeatureMatrix, donne un statut par fonction : IMPLÉMENTÉ ET TESTÉ, IMPLÉMENTÉ NON TESTÉ, PARTIEL, BLOQUÉ ou NON IMPLÉMENTÉ. Précise séparément UI, document/persistance, aperçu, export et preuve. Scénario, variantes et transport du projet ont leurs propres lignes détaillées. Une fonction décrite dans README ou accessible par un bouton ne compte pas comme implémentée.

La livraison ne peut pas être déclarée complète si une des trois signatures est décorative, si un effet n’existe qu’en aperçu, si le projet ne se rouvre pas, si une migration perd des réglages ou si les exports sont désynchronisés. Ne cache pas un test en échec et ne supprime pas une exigence du cahier pour améliorer le bilan.

Un blocage sur une fonction avancée doit identifier la cause, la partie livrée et le travail restant. Une compilation verte seule ne prouve pas la conformité App Store. Une différenciation fonctionnelle seule ne suffit pas à déclarer la publication prête tant que les autres vérifications pertinentes manquent.

Termine par un compte rendu bref : ce qui a été livré ; commandes exécutées et résultats réels ; trois parcours signature vérifiés ; anomalies et fonctions restantes ; blocages de publication ; étapes locales nécessaires pour ouvrir et installer le projet. Ne réclame pas une validation intermédiaire pour continuer les tâches ordinaires. Commence maintenant.

## Annexe — Références officielles de travail

Cette annexe fournit des liens de vérification, pas une affirmation que toutes les pages ont été relues dans cette session. Les règles Apple et les guides Codex ont été consultés pour cette révision du 5 octobre 2026. Les pages d’API peuvent nécessiter leur rendu JavaScript ou la documentation Xcode ; leur signature et disponibilité doivent être contrôlées par l’agent. Les choix de produit et de tests ci-dessus sont notre cahier, pas des spécifications internes de CapCut.

### Apple — distribution, plateforme et API

[A1] App Review Guidelines ; notamment 4.1, 4.3, 2.1, 2.3, 4.2, 5.1 et 5.2 :
`https://developer.apple.com/app-store/review/guidelines/`

[A2] Human Interface Guidelines :
`https://developer.apple.com/design/human-interface-guidelines/`

[A3] Composition et compositeur vidéo personnalisé :
`https://developer.apple.com/documentation/avfoundation/avmutablecomposition`
`https://developer.apple.com/documentation/avfoundation/avvideocompositing`

[A4] Export, lecture et écriture des échantillons :
`https://developer.apple.com/documentation/avfoundation/avassetexportsession`
`https://developer.apple.com/documentation/avfoundation/avassetreader`
`https://developer.apple.com/documentation/avfoundation/avassetwriter`

[A5] Sélection Photos :
`https://developer.apple.com/documentation/photosui/photospicker`
`https://developer.apple.com/videos/play/wwdc2022/10023/`

[A6] Manifeste de confidentialité :
`https://developer.apple.com/documentation/bundleresources/privacy-manifest-files`

[A7] Reconnaissance vocale :
`https://developer.apple.com/documentation/speech/speechanalyzer`
`https://developer.apple.com/documentation/speech/sfspeechrecognizer`
`https://developer.apple.com/videos/play/wwdc2025/277/`

[A8] Vision, segmentation et suivi :
`https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest`
`https://developer.apple.com/documentation/vision/vntrackobjectrequest`

[A9] Moteur audio :
`https://developer.apple.com/documentation/avfaudio/avaudioengine`

[A10] Principes de montage HDR ; valider le pipeline retenu :
`https://developer.apple.com/videos/play/wwdc2020/10009/`

[A11] Archive conceptuelle de montage AVFoundation ; ne pas recopier ses anciens exemples sans modernisation :
`https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html`

### CapCut — inventaire fonctionnel seulement, jamais maquette à reproduire

[R1] Fiche mobile publiée par l’éditeur :
`https://apps.apple.com/us/app/capcut-photo-video-editor/id1500855883`

[R2] Tutoriel ; distinguer les plateformes :
`https://www.capcut.com/resource/capcut-tutorial-for-beginners`

[R3] Vitesse et courbes ; utiliser les résultats attendus, pas leurs écrans ni profils propriétaires :
`https://www.capcut.com/resource/how-to-speed-up-a-video`
`https://www.capcut.com/resource/how-to-do-velocity-on-capcut`

[R4] Sous-titres et différences entre plateformes :
`https://www.capcut.com/help/how-to-recognise-subtitles`
`https://www.capcut.com/help/bilingual-subtitles`

[R5] Centre d’aide :
`https://www.capcut.com/help`

### OpenAI — utilisation de Codex

[C1] Instructions locales AGENTS.md :
`https://developers.openai.com/codex/guides/agents-md/`

[C2] Prompts, contexte et vérifications :
`https://developers.openai.com/codex/prompting/`
