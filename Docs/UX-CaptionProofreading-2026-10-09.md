# Relecture des sous-titres avec Apple Intelligence — 9 octobre 2026

## Parcours

Sous-titres → Texte → Vérifier → Ce segment ou Toute la piste → Vérifier les sous-titres → comparer les propositions → Appliquer.

Le modèle local Foundation Models corrige l’orthographe, la grammaire et la ponctuation, avec une consigne de conservation de la langue, du sens et du style oral. La version actuelle utilise `SystemLanguageModel(guardrails: .permissiveContentTransformations)`, le mode Apple destiné à transformer du texte existant, avec une réponse `String` décodée strictement par CutFuze. Aucun service distant, compte, transfert réseau ou moteur de montage supplémentaire n’a été ajouté.

Les propositions affichent le texte vérifié et le résultat modifiable. Chaque proposition peut être refusée ; Appliquer est désactivé si aucune n’est acceptée ou si une proposition acceptée est vide. Le brouillon courant est inclus explicitement, sans l’enregistrer à l’ouverture du panneau. Fermer n’applique aucune correction. Les titres ont été raccourcis pour éviter leur troncature sur l’iPhone.

L’application des textes acceptés est atomique et constitue une seule action d’historique. Les UUID, timecodes, limites des segments, liens à la source, styles, effets et variantes restent ceux du document existant. Les textes modifiés ou supprimés depuis la vérification bloquent l’application. Une réponse non JSON, contenant d’autres champs, un texte vide ou non répartissable est rejetée ; les indices internes de redistribution sont également validés.

Pour « Toute la piste », CutFuze regroupe les fragments consécutifs jusqu’à la fin d’une phrase, puis demande au modèle la phrase complète corrigée. Les chevauchements, changements de calque et pauses supérieures à 1,2 seconde séparent les groupes. Chaque session reste limitée à huit segments et 1 800 octets de texte. « Ce segment » traite uniquement le segment choisi. La progression affiche le nombre de segments traités. Un segment dépassant ce budget doit être scindé. Une erreur de génération n’applique pas de résultat partiel.

CutFuze répartit ensuite les mots de la phrase corrigée selon les proportions du nombre de mots des segments d’origine. Chaque mot de la réponse apparaît exactement une fois, sans segment vide. Les corrections des raccords d’une même phrase sont acceptées ou refusées ensemble pour éviter les pertes ou doublons à l’application. Ce traitement rapproche les coupures textuelles de l’original, sans fusionner les clips ni modifier leurs temps.

## Première validation sur iPhone 15 Pro physique — avant le traitement par phrases

- Compilation iOS réussie avec le SDK actuel du projet ; aucun changement du minimum iOS 27 existant.
- Trois nouveaux tests unitaires réussis : conservation des temps/sources/styles/variantes et undo/redo, validation des sorties et refus atomique des textes périmés, lots et brouillon non destructif.
- Deux nouveaux tests UI réussis : ouverture/choix de portée/fermeture sans modification ; vraie génération Apple Intelligence, correction d’un pluriel français, refus puis acceptation d’une proposition, application et annulation unique.
- Un test supplémentaire appelle réellement Apple Intelligence sur neuf sous-titres : deux lots traités, neuf corrections associées aux bons segments, progression 8 puis 9, temps inchangés. Réussi en 7,8 secondes.
- Tests existants réussis : remappage des sous-titres après vitesse/coupe/undo, split/fusion avec provenance source, édition au-dessus du clavier et taille en points, galerie de polices et portée de toute la piste.

Résultats : `Test-CutFuze-2026.10.09_09-58-00-+0200.xcresult` (trois tests unitaires et deux parcours UI), `Test-CutFuze-2026.10.09_09-59-27-+0200.xcresult` (vraie relecture multi-lots), `Test-CutFuze-2026.10.09_10-00-27-+0200.xcresult` (titre compact, accès et galerie de polices), et `Test-CutFuze-2026.10.09_09-55-58-+0200.xcresult` (non-régressions réussies ; son premier essai d’undo UI avait encore une requête ambiguë).

Captures obtenues et inspectées : [choix de portée](Evidence/CaptionProofreading-Final/C90948A2-F336-4F08-8024-D83370B75E07.png), [proposition issue du modèle local](Evidence/CaptionProofreading-Final/64236CB0-14EA-4650-9930-18A1523189D0.png), [texte restauré après annulation](Evidence/CaptionProofreading-Final/A3843C08-0A85-4C36-8AA6-2D29251DC010.png). Cette dernière capture précède le raccourcissement final du titre du panneau de sous-titres.

[Accès Vérifier et titre Sous-titres après correction visuelle](Evidence/CaptionProofreading-Polish/1A06A693-30AA-44D9-A7C4-9B83C79C1D04.png), également inspecté.

Les premiers essais ont révélé une fixture contenant un sous-titre supplémentaire, une requête UI cherchant un TextView alors que le contrôle est exposé comme TextField, puis une ambiguïté entre les boutons d’undo du panneau et de l’éditeur. Ces erreurs de test ont été corrigées sans supprimer leurs assertions. Un premier lancement UI avait aussi été refusé par l’authentification de l’iPhone ; les parcours suivants ont été exécutés après déverrouillage.

## Validation du traitement par phrases — version actuelle

Compilation iOS réussie. Résultat final physique : `Test-CutFuze-2026.10.09_10-32-11-+0200.xcresult`, **12 tests réussis, aucun échec ni test ignoré**, sur iPhone 15 Pro / iOS 27.0.1.

- Six tests de données : sorties invalides/refus textuels, regroupement des phrases et validation liée, redistribution de tous les mots et coupures approximatives, préservation du document et undo/redo, rejet atomique des textes périmés, limites de sessions et brouillon.
- Deux tests appellent réellement Apple Intelligence : correction de « Les chat / joue dans le / jardin. » puis « Pas espagnol » sans traduction ; neuf sous-titres complets traités successivement avec progression 1 à 9 et mêmes identités/timecodes.
- Deux non-régressions existantes : sous-titres liés après vitesse/coupe/undo ; split/fusion avec provenance source.
- Deux parcours UI réels : portée par défaut, explication du traitement par phrases et fermeture non destructive ; brouillon avec erreur de pluriel, génération native, refus/acceptation, application et annulation unique.

Une première exécution physique a révélé des réponses JSON mal structurées dans l’ancien mode demandant un tableau de corrections. Le protocole a été remplacé par une réponse texte unique et une redistribution contrôlée par CutFuze ; les tests natifs et UI ont ensuite été relancés et réussis. Aucun assouplissement du rejet des refus ou des réponses invalides.

Captures finales exportées : cinq images dans `Evidence/CaptionProofreading-Phrases-Final`. Principaux états inspectés : [Toute la piste](Evidence/CaptionProofreading-Phrases-Final/2F9B7130-39AE-4C6B-A9B2-58F36213E387.png), [proposition native](Evidence/CaptionProofreading-Phrases-Final/3A801616-41B5-4B47-B0EF-658D47560B36.png), [texte restauré après undo](Evidence/CaptionProofreading-Phrases-Final/7702E6AD-141D-48B7-9B66-A363BD893AEC.png). Pas de troncature observée dans ces états.

Le journal du parcours avec clavier contient encore l’avertissement SwiftUI « Invalid frame dimension (negative or non-finite) ». Il n’a pas provoqué d’échec ni de défaut visible dans les captures inspectées ; sa cause n’a pas été isolée dans cette passe. La validation liée de plusieurs corrections est testée au niveau document ; le geste de bascule simultanée de plusieurs propositions n’a pas été exécuté dans un parcours UI automatisé. Le texte de la piste réelle ayant déclenché le refus initial n’a pas été fourni et n’a pas été testé.

## Écouter un segment pendant la relecture

Chaque proposition possède maintenant une commande « Écouter le segment », remplacée par « Arrêter l’écoute » pendant la lecture. Un seul segment peut jouer à la fois ; un nouveau tap sur son bouton l’arrête, choisir un autre segment remplace la lecture, et chaque relance repart du début du passage. La lecture est bornée par les timecodes existants via `forwardPlaybackEndTime`.

`CaptionSegmentPlayer` réutilise `AudioComposer.preparePlayerItem`, donc le mix, les trims, vitesses, volumes et fondus du montage. Il ne lit pas une synthèse du texte proposé. Il n’édite ni le document, ni la sélection, ni le curseur de l’éditeur. Fermer le panneau, appliquer les corrections, recommencer une relecture ou quitter l’application arrête l’écoute. Les interruptions audio et la perte du casque sont également prises en compte, sans reprise automatique. Un montage dépourvu de son reçoit un message explicite. Activation et désactivation de la session audio sont asynchrones et ordonnées pour ne pas bloquer les gestes.

Validation finale : compilation iOS et **7 tests réussis, aucun échec ni test ignoré**, sur l’iPhone 15 Pro, résultat `Test-CutFuze-2026.10.09_10-55-57-+0200.xcresult`.

- Deux tests audio nouveaux : limites et absence de son ; vrai fichier PCM lu par AVPlayer, progression temporelle, arrêt à la borne finale, changement de segment et annulation pendant la préparation.
- Trois tests de relecture : redistribution, conservation des propriétés et undo, vraie correction par Apple Intelligence.
- Deux parcours UI : accès/portée/fermeture non destructive ; vraie proposition native, bouton écouter/arrêter, relance et arrêt automatique, texte proposé inchangé après écoute, acceptation/application/undo.

Six captures exportées dans `Evidence/CaptionProofreading-Listening-Final`. [Écoute en cours](Evidence/CaptionProofreading-Listening-Final/2BA3B12E-6D58-4549-A828-66E461B7F6CB.png) et [bouton revenu à Écouter après l’arrêt](Evidence/CaptionProofreading-Listening-Final/C09BF264-81BE-4E17-B232-FCB6F656C9CE.png) inspectés : commandes visibles et accessibles, contenu dans la liste scrollable. L’avertissement d’activation audio sur le thread principal détecté au premier essai n’apparaît plus après passage aux API asynchrones. L’avertissement de frame SwiftUI mentionné précédemment subsiste.

Ces vérifications constatent la lecture AVPlayer et ses bornes ; elles ne constituent pas une écoute humaine du haut-parleur. La piste réelle de l’utilisateur, les appels entrants, le débranchement physique d’un casque et l’iPad n’ont pas été testés dans cette passe. Le mix inclut les autres sons du montage : aucune isolation automatique de la voix.

## Limites

La relecture vérifie le texte, pas sa fidélité à l’audio. Elle peut laisser passer des erreurs ou proposer une correction inadéquate : la validation humaine reste indispensable. Aucune traduction ou réécriture créative n’est demandée au modèle. La redistribution suit les longueurs textuelles, pas un alignement acoustique. Une phrase longue ou sans ponctuation peut dépasser la limite de huit segments et être relue en plusieurs groupes ; la piste entière n’est pas envoyée dans un contexte unique.

L’appareil doit être compatible avec Apple Intelligence, la fonctionnalité activée et le modèle téléchargé. Des messages dédiés couvrent ces indisponibilités, les langues non prises en charge et les refus du modèle. Ces états ont été implémentés mais pas simulés physiquement ; l’iPhone testé disposait effectivement du modèle. L’arrêt d’une génération en cours n’a pas fait l’objet d’un parcours UI automatisé.

L’iPad, Dynamic Type, VoiceOver, les longues pistes réelles et les langues autres que le français n’ont pas été qualifiés dans cette passe. Les suites complètes de tests n’ont pas été relancées ; les tests ci-dessus sont ciblés. Aucun commit automatique.

Références API : [SystemLanguageModel — Apple Developer](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [mode de transformation de contenu — Apple Developer](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails/permissivecontenttransformations). Ce mode ne garantit pas l’absence de refus du modèle. Les refus, blocages du filtre, langues non prises en charge et réponses invalides ont des messages distincts, avec la plage temporelle concernée ; aucun refus textuel n’est appliqué comme sous-titre.
