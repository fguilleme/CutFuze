# Checklist de soumission

Dernière qualification locale : clean build et55tests PASS (simulateur18ProMax), captures SE3/18Pro/18ProMax, troisMP4 et paquet réellement transporté. Cela ne vaut pas qualification sur iPhone physique.

5 octobre 2026. États utilisés : **VÉRIFIÉ**, **À VÉRIFIER**, **BLOQUANT**. Aucun compte ou accès à App Store Connect n’a été supposé. Aucune soumission, publication ou dépense autorisée par cette checklist.

## Audit produit

| État | Vérification | Preuve ou action restante |
|---|---|---|
| VÉRIFIÉ | Cahier indépendant remplaçant les anciennes exigences de copie | ProductSpec.md ; aucun écran concurrent utilisé comme maquette. |
| VÉRIFIÉ | Catalogue original dans le code | 12 TemplateDefinition avec nombres/durées/textes/transitions distincts ; documents ordinaires. |
| VÉRIFIÉ | Pas de compte ni service de transfert applicatif imposé | Inspection du code du workspace. |
| À VÉRIFIER | Parcours complets, utilité, absence d’erreur visible | Exécuter AppReviewNotes sur iPhone physique et confronter ValidationReport. |
| À VÉRIFIER | Accès aux commandes, VoiceOver, petit écran, rotation | Recette complète matérielle ; ne pas confondre compilation et accessibilité. |
| À VÉRIFIER | Exactitude des descriptions et captures | Retirer toute revendication que le binaire candidat ne permet pas de reproduire. |
| À VÉRIFIER | Relecture des règles Apple au moment effectif de soumettre | Audit documentaire daté dans ReferenceAudit ; les règles peuvent évoluer. |

## Droits et confidentialité

| État | Vérification | Preuve ou action restante |
|---|---|---|
| VÉRIFIÉ | Provenance technique des ressources d’exemple | Génération locale PNG/WAV ; ThirdPartyLicenses.md. |
| À VÉRIFIER | Nom CutFuze et identité commerciale | Recherche/validation par l’éditeur ; nom existant conservé, pas considéré comme disponible. |
| À VÉRIFIER | Droits de tout média ajouté par l’éditeur | Registre à mettre à jour avant capture/publi. |
| VÉRIFIÉ | Raison DiskSpace du manifeste correspond au code | E174.1 et contrôle pré-écriture dans MediaSupport ; CA92.1 pour la préférence locale de disposition. |
| À VÉRIFIER | Rapport confidentialité de l’archive finale | Vérifier inclusion PrivacyInfo.xcprivacy, APIs réellement utilisées, SDKs et collecte finale. |
| À VÉRIFIER | Déclarations App Privacy finales | Partir de PrivacyDataMap ; confirmer comportement et destinations. |
| BLOQUANT | Politique de confidentialité publique | URL, identité, coordonnées légales absentes. |

## Paramètres administratifs

| État | Vérification | Preuve ou action restante |
|---|---|---|
| BLOQUANT | Éditeur et contact App Review | Informations utilisateur non fournies. |
| BLOQUANT | URL support réelle | Non fournie ; aucune URL fictive créée. |
| À VÉRIFIER | Bundle ID / équipe / certificats de distribution | Paramètres existants conservés ; accès et autorisation de publication à confirmer. |
| À VÉRIFIER | Âge, territoires, catégorie, conformité export | À remplir par l’éditeur à partir du binaire candidat. |
| BLOQUANT | Autorisation de publier | Le mandat interdit la publication sans demande distincte. |

## Technique

| État | Vérification | Preuve ou action restante |
|---|---|---|
| À VÉRIFIER | Compilation propre et tests du candidat | Voir commandes et résultats réels dans ValidationReport. |
| À VÉRIFIER | Trois parcours signature | Réordre Scénario/Timeline, variantes et transport vers sandbox distinct. |
| À VÉRIFIER | Export/relecture et synchronisation sur appareil | Tester codecs, dimensions, longues durées, interruptions et mémoire. |
| À VÉRIFIER | Refus et révocation des permissions | Microphone, reconnaissance vocale, accès aux fournisseurs Fichiers. |
| À VÉRIFIER | Voix et transcription réelle | Ressources locales, différentes langues, fichiers longs et annulation. |
| À VÉRIFIER | Sources HDR et fichiers iPhone variés | Corpus physique requis ; aucune promesse HDR fondée sur un simple import. |
| À VÉRIFIER | Réinstallation, récupération et espace insuffisant | Exécuter sur appareil avec sauvegardes et erreurs IO réelles. |

Un état VÉRIFIÉ porte sur la vérification indiquée, pas sur l’ensemble du produit ni sur une probabilité d’acceptation.
