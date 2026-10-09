# Langue de CutFuze — 9 octobre 2026

## Comportement

CutFuze utilise la langue prise en charge choisie par iOS (`Bundle.main.preferredLocalizations`), et non la région du téléphone. Français et anglais sont disponibles ; l’anglais est la langue de développement/repli. Aucun sélecteur de langue propre à CutFuze ni préférence imposant l’anglais n’a été ajouté. Le choix de langue par application fourni par iOS reste respecté.

Les anciens choix de langue indépendants des panneaux ont été remplacés par `AppLocalization`, utilisé par `L` et les helpers bilingues. Le catalogue existant est conservé et complété : commandes contextuelles, accessibilité du séparateur, messages d’erreur, statuts d’export, langues de transcription/traduction, noms et descriptions des douze modèles.

Les modèles et exemples nouvellement créés sont initialisés dans la langue de l’application. Les documents déjà enregistrés ne sont pas migrés : titres, collections, sous-titres, narration et noms de fichiers restent leurs contenus originaux. Une ancienne collection « Exemples » peut donc coexister avec une nouvelle collection « Examples ». Les langues de reconnaissance vocale et de synthèse ne sont pas assimilées à la langue de l’interface.

Le moteur de montage, le rendu et l’architecture multi-format sont conservés. Aucun outil n’est supprimé. L’inspection des captures a également conduit à fixer l’apparence claire de la bibliothèque et des modèles, dont le fond clair produisait un titre blanc et un champ de recherche presque invisible sous le thème sombre de l’iPhone.

## Validation réellement exécutée

Appareil : iPhone 15 Pro physique, iOS 27.0.1, viewport logique 393 × 852.

- Compilation iOS réussie, puis recompilation lors de la dernière passe de tests.
- Première passe : 60 tests, 58 réussis, 2 échecs. CoreTests : 53/54 ; LocalizationTests : 3/3 ; test média transport/réexport : 0/1 ; parcours d’interface : 2/2.
- Dernière passe après correction du contraste : **5/5 réussis** (les 3 tests de localisation et les 2 parcours d’interface).
- Parcours anglais : bibliothèque, réglages, catalogue des modèles, détail d’un modèle avec aperçu et textes anglais, timeline, panneau d’effets, relecture des sous-titres, fermeture sans changement de texte, écran d’export, puis relance française. Dans cette passe, `AppleLanguages=(en)` est associé à `AppleLocale=fr_FR` pour distinguer langue et région. Ces paramètres concernent uniquement le lancement du processus de test ; les réglages du téléphone ne sont pas changés.
- Parcours français : ouverture de la relecture, portée piste/segment, fermeture et conservation du texte.
- Audit `node Scripts/audit-localization.mjs --errors --check` : aucune clé statique `L` ou erreur statique contrôlée sans traduction anglaise. Ce contrôle ne remplace pas une visite exhaustive de tous les écrans.
- `git diff --check` réussi. Application finale rouverte sur l’iPhone sans argument de langue.

Résultats Xcode : `Test-CutFuze-2026.10.09_20-51-00-+0200.xcresult` et `Test-CutFuze-2026.10.09_20-53-43-+0200.xcresult`.

## Captures finales

Neuf captures obtenues et inspectées :

- [Bibliothèque](Evidence/AppLanguages-Final-2026-10-09/C49E6EB4-85FB-4143-959D-96BF1C15633E.png)
- [Réglages](Evidence/AppLanguages-Final-2026-10-09/47AFA0C9-60BB-4C07-B446-154E01AB8A25.png)
- [Modèles](Evidence/AppLanguages-Final-2026-10-09/B40010F8-3AAB-4536-96E9-8038BEA5776D.png)
- [Détail d’un modèle](Evidence/AppLanguages-Final-2026-10-09/1EE8A8FF-BAD6-414F-B321-A565F71E6FDB.png)
- [Timeline en anglais](Evidence/AppLanguages-Final-2026-10-09/0FB0969F-1B6A-4D4F-B312-324BB93632EC.png)
- [Effets visuels](Evidence/AppLanguages-Final-2026-10-09/EC8F2253-E0CD-4C32-A596-79BB0965F5F7.png)
- [Relecture](Evidence/AppLanguages-Final-2026-10-09/D2CA7961-C5EC-4855-8394-97B898AB013B.png)
- [Export](Evidence/AppLanguages-Final-2026-10-09/9DC5E9D5-0194-4130-A93D-9DFFEBE94DE1.png)
- [Retour au français](Evidence/AppLanguages-Final-2026-10-09/4D89EBB3-72D1-4F38-A112-27E2CC0ADA7C.png)

## Limitations

Les deux échecs de la première passe sont `testPortableProjectSurvivesDeletionOfSourceAndPreservesVariants` et `testPhotosOnlyThreeVariantsAudioPortableReexport`, avec « Chemin hors stockage ». Ils sont déjà documentés dans [la passe des effets](UX-VisualEffects-2026-10-09.md) et n’ont pas été corrigés dans cette traduction. Les modifications du stockage/transport concernent ici seulement les messages visibles, pas la résolution des chemins.

La visite anglaise ne couvre pas chaque interaction de chaque panneau, ni les autorisations système, l’iPad ou toutes les tailles de texte. Le test média n’ayant pas terminé le transport/réexport, cette passe ne constitue pas une validation complète de cet enchaînement. Les diagnostics provenant directement d’iOS peuvent garder la langue choisie par le système. Les autres langues que le français et l’anglais ne sont pas traduites.
