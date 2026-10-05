# Provenance des ressources et dépendances

État du 5 octobre 2026.

| Élément distribué | Provenance | Modalités / limites |
|---|---|---|
| Code Swift du produit | Écrit dans ce workspace pour CutFuze | Aucun extrait de catalogue ou moteur propriétaire concurrent incorporé. Le titulaire et les conditions de diffusion commerciales restent à renseigner par l’éditeur. |
| Bibliothèques | Frameworks publics Apple : SwiftUI, UIKit, AVFoundation/AVFAudio, Core Image, Speech, PhotosUI, CryptoKit, Foundation, selon les fichiers utilisés | Frameworks système liés à l’app ; aucun paquet tiers ni binaire téléchargé requis. Conditions du SDK Apple applicables. |
| Illustrations PNG des modèles/exemple | Dessin procédural original de `SyntheticResources.make` : dégradés, soleil, courbes et cadres | Générées localement lors de la création du document et incluses comme médias normaux. Aucun média de stock. |
| Repère sonore WAV | Oscillateurs sinusoïdaux originaux et impulsions de `SyntheticResources.makeReferenceSound` | Généré localement ; aucune composition ou prise sonore tiers copiée. Ce son n’est pas une vraie voix ni un échantillon de validation de transcription. |
| 12 modèles de montage | Données originales de `TemplateCatalog` | Textes, durées, transitions et mises en page modifiables. Aucun modèle premium ou catalogue tiers importé. |
| Icône de développement | Trois cadres créés pour ce projet | Nom et disponibilité de marque à confirmer ; l’icône n’est pas une preuve de dépôt. |
| Symboles de l’interface | SF Symbols via les API système | Utilisés dans l’interface Apple. Pas de fichier de police système exporté dans un paquet projet. |
| Polices des textes | Polices système résolues par les API de la plateforme | Les fichiers de polices ne sont pas copiés. Un document transporte ses réglages, pas une licence de police externe. |
| Voix de synthèse | Voix effectivement retournées par AVSpeechSynthesisVoice | Les ressources de voix restent gérées par le système. Les conditions d’utilisation d’une voix ou d’un contenu importé restent à confirmer par l’éditeur et l’utilisateur. |
| Médias importés par l’utilisateur | Sélection explicite Photos/Fichiers | Les droits de diffusion restent ceux de l’utilisateur. Le transport de projet n’accorde aucun droit supplémentaire. |

Aucune politique de licence commerciale globale, identité juridique d’éditeur ni autorisation sur des médias utilisateur n’a été inventée. Avant publication, vérifier les droits sur toute ressource ajoutée après cet audit.

Le corpus de tests `SyntheticVideoCorpus` produit aussi des MP4 originaux avec compteur d’images, grille orientée, rectangle texturé mobile et une piste CAF d’impulsions de référence. Les scènes et le mouvement sont calculés par ce projet ; les tests Vision mesurent ensuite le fichier encodé au moyen du moteur réel. Aucune séquence filmée de tiers n’est utilisée pour ce corpus.
