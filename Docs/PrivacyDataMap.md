# Carte des données et projet de texte de confidentialité

Audit du code : 5 octobre 2026. Cette carte décrit le comportement implémenté ; la déclaration App Store Connect et la politique publique restent à finaliser après validation du binaire.

| Donnée | Entrée et finalité | Stockage / destinataire | Conservation et suppression |
|---|---|---|---|
| Photos, vidéos, audio | Sélection explicite Photos/Fichiers pour le montage | Copie durable dans le dossier du projet, références relatives dans le manifeste. Aucun serveur applicatif. | Les manifests sont supprimés avec le projet. Les originaux stockés en commun sont conservés par prudence pour les autres projets et l’historique ; aucun ramasse-miettes des médias orphelins n’est livré. La suppression complète du stockage passe actuellement par la désinstallation, sous réserve des sauvegardes système. |
| Titres, narration, textes, paramètres | Saisie dans l’éditeur | Manifeste JSON local versionné et sauvegarde de récupération | Avec le projet ; restauration locale possible depuis la dernière version valide. |
| Voix enregistrée | Action Enregistrer, permission microphone | AAC dans un fichier local durable ; pas de retour micro sur haut-parleur | La prise interrompue est conservée jusqu’à insertion ou abandon explicite. Annulation d’une prise active retire son fichier. |
| Texte synthétisé | Action Synthétiser, voix système choisie | Buffers AVSpeechSynthesizer écrits localement en CAF puis déplacés après succès | Le fichier devient un média du projet. Aucun service distant applicatif. |
| Audio à transcrire | Action explicite de transcription de la source sélectionnée | SpeechAnalyzer avec ressources installées sur iOS26+, sinon SFSpeechRecognizer avec contrôles de disponibilité locale et requiresOnDeviceRecognition=true | Blocs de travail temporaires supprimés à la fin/erreur ; résultats horodatés réinsérés au projet. Aucun repli cloud. |
| Ressources de langue / voix | Gérées par iOS | L’app consulte les ressources déjà présentes et renvoie une erreur si le moteur local n’est pas disponible | L’app ne lance aucun téléchargement implicite. L’installation par les réglages système est extérieure à l’app. |
| Exports vidéo, sous-titres, paquets projet | Action Exporter / Partager | Fichiers locaux puis destination choisie dans la feuille de partage système | Les copies envoyées à Fichiers, Photos ou un service choisi par l’utilisateur sont gérées par cette destination. |
| Capacité disque | Contrôle avant écriture/export | Valeur transitoire locale ; avertissement/erreur si espace insuffisant | Pas de journal distant, pas d’identifiant, pas de transmission. |
| Vignettes / buffers / fichiers intermédiaires | Prévisualisation, lecture, analyse | Mémoire et répertoires locaux de travail | Régénérables ; nettoyage des fichiers temporaires terminé ou annulé. Vérifier le nettoyage après fermeture forcée avant publication. |

Aucun compte, identifiant publicitaire, publicité, traceur, analytics tiers, paiement, synchronisation applicative ni API réseau de téléversement n’est intégré. Une sélection iCloud/Files peut faire télécharger un fichier par le fournisseur système ; une destination de partage peut l’envoyer au service choisi. Les sauvegardes système iCloud de l’app dépendent des réglages de l’appareil. Ces actions ne sont pas un hébergement CutFuze.

## Permissions contextualisées

- Microphone : « Enregistrer une voix off directement dans votre projet. L’enregistrement reste sur cet appareil. » Demande au début de l’action Enregistrer, jamais à l’ouverture de bibliothèque.
- Reconnaissance vocale : « Créer des sous-titres à partir du son sélectionné avec la reconnaissance locale disponible. » Demandée uniquement pour le moteur de repli qui la nécessite. Un refus laisse l’édition manuelle/SRT utilisable.
- Photos : le sélecteur système est privilégié pour l’import, sans accès global obligatoire. Un éventuel enregistrement dans Photos doit demander seulement l’accès nécessaire ; son refus ne doit pas supprimer le fichier exporté.
- Fichiers : la sélection passe par les URL à accès sécurisé du système ; les données sont copiées avant utilisation durable.

## Manifeste livré

`CutFuze/PrivacyInfo.xcprivacy` déclare aucune collecte pour transmission à l’éditeur et aucun tracking. La préférence locale `reversedLayout` utilise UserDefaults et déclare **CA92.1**, sans synchronisation ni transfert. La catégorie DiskSpace déclare **E174.1** pour le contrôle d’espace avant écriture présent dans `MediaSupport.swift`. Source : [raisons Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), vérifiée le 5 octobre 2026. Ce fichier doit être recopié dans le bundle et contrôlé par le rapport de confidentialité d’une archive de distribution. Toute API ajoutée après cet audit impose une revue ciblée ; ne pas copier des raisons inutilisées.

## Projet de politique locale

CutFuze traite vos projets sur votre appareil. Vos médias, enregistrements et textes servent à créer les montages que vous demandez. L’application ne possède pas de compte utilisateur et n’envoie pas vos projets à un serveur de l’éditeur. La transcription exige un moteur local disponible ; si cette condition manque, elle échoue avec un message explicite. Vous choisissez les imports et les destinations de partage.

Vous pouvez supprimer vos documents de projet depuis la bibliothèque. Le stockage commun conserve les originaux afin de ne pas casser les autres projets ; cette version ne possède pas de purge des médias orphelins. Les exports déjà copiés ailleurs, les sauvegardes système et les fichiers conservés par une destination de partage doivent être supprimés dans ces espaces. Désinstaller l’application supprime son espace local, sous réserve des sauvegardes système.

**Publication bloquée :** identité et coordonnées légales de l’éditeur, contact de confidentialité, URL publique de cette politique et URL de support non fournis. Aucun domaine ni adresse fictifs ne remplace ces éléments. La politique devra être relue et datée par l’éditeur avant publication.

## Analyses d’image locales

Le suivi de région et la stabilisation décodent les images du média sélectionné sur l’appareil avec AVFoundation et Vision. Le suivi produit des positions et des niveaux de confiance ; la stabilisation estime des translations, les lisse et convertit la correction en keyframes de position/échelle. Les keyframes sont des données éditables du document. Ces analyses ne constituent pas une reconnaissance d’identité et n’envoient ni image ni mesure à un service distant.
