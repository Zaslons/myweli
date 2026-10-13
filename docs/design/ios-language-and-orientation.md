# iOS — la langue que lit l'App Store, et le portrait sur iPhone — spec

- **Statut** : construit le 2026-10-13 ; l'effet sur la fiche ne se lit
  qu'après l'envoi d'un build (§8.3).
- **Module** : mise en production (release) — projet iOS partagé par les deux
  apps.
- **Décision** : le propriétaire, le 2026-10-13 (« tout comme recommandé ») —
  les décisions 1 et 2 de [app-store-forms.md](app-store-forms.md) §13.1.
- **Régit** : `mobile/ios/Runner.xcodeproj/project.pbxproj`,
  `mobile/ios/Runner/Info.plist`, `mobile/ios/Runner/fr.lproj/InfoPlist.strings`,
  `mobile/test/infra/ios_store_readiness_test.dart`.

## 1. But et périmètre

Deux défauts, **vérifiés avant d'écrire** :

1. **App Store Connect lit l'app comme anglaise.** Lu par l'API le 2026-10-13
   sur le build 577 : `buildBundles.locales = ["en"]`. Dans l'archive
   `Runner-pro-577.xcarchive`, la racine de `Runner.app` ne contient qu'un seul
   dossier de langue, `Base.lproj` ; son `Info.plist` dit
   `CFBundleDevelopmentRegion = en` (la clé vaut `$(DEVELOPMENT_LANGUAGE)`, que
   Xcode remplit avec le `developmentRegion = en` du projet) et
   `CFBundleLocalizations = [fr]`. La fiche afficherait « Langues : anglais »
   pour une app qui ne parle que français — `CFBundleLocalizations` ne suffit
   donc pas, contrairement à ce que supposait
   [app-store-forms.md](app-store-forms.md) §14.
2. **L'iPhone autorise le paysage.** `UISupportedInterfaceOrientations` liste
   `Portrait`, `LandscapeLeft` et `LandscapeRight` ; aucun écran n'a jamais été
   essayé en paysage et rien n'appelle `setPreferredOrientations`. Un relecteur
   qui tourne le téléphone voit des écrans écrasés.

**Ce que dit Apple** sur le premier : la ligne « Langues » vient des
localisations de l'app — « the `*.lproj` folders in your project » — et la
localisation de base d'un projet Xcode est l'anglais par défaut
([forum Apple, fil 718409](https://developer.apple.com/forums/thread/718409),
réponse d'un ingénieur Apple).

**Périmètre** : le projet iOS n'a qu'une cible `Runner` et un `Info.plist`
pour les deux saveurs — le changement vaut donc pour **MyWeli et MyWeli Pro**.
Les deux ne parlent que français (`supportedLocales: fr_FR`), et aucune des
deux n'a été essayée en paysage.

**Hors périmètre** :

- **Android** : le manifeste ne fixe aucune orientation (`screenOrientation`
  absent). Même défaut de qualité, autre magasin, autre décision — §11.
- **iPad** (l'app consommateur seule ; Pro est iPhone seul) :
  `UISupportedInterfaceOrientations~ipad` garde ses quatre orientations. Le
  multitâche iPad les exige toutes, sauf à déclarer `UIRequiresFullScreen`.
- Une traduction anglaise.

## 2. Ce que voit l'utilisateur

Aucun écran ne change. Sur iPhone l'app ne tourne plus avec le téléphone. Sur
la fiche App Store : « Langues : français ». L'interface système dans l'app
(boutons des alertes de permission, sélecteur de documents) était déjà en
français par `CFBundleLocalizations` et le reste.

## 3. Contrat d'API · 4. Données

Sans objet.

## 5. Les trois changements

| # | Fichier | Avant | Après |
|---|---|---|---|
| a | `project.pbxproj` | `developmentRegion = en` ; `knownRegions = (en, Base)` | `developmentRegion = fr` ; `knownRegions = (fr, Base)` |
| b | `Runner/fr.lproj/InfoPlist.strings` (nouveau), inscrit dans le projet comme ressource localisée (`PBXVariantGroup`, phase « Resources ») | — | un fichier sans clé (un commentaire qui dit pourquoi il existe) : il fait apparaître `fr.lproj` à la racine du paquet |
| c | `Info.plist`, `UISupportedInterfaceOrientations` | Portrait, LandscapeLeft, LandscapeRight | **Portrait** seul |

**Pourquoi (a) et (b) ensemble.** (a) seul fait de `Base.lproj` du français,
mais compte sur une règle qu'Apple ne documente pas — que le magasin range
`Base` sous la langue de développement. (b) seul afficherait deux langues :
`fr.lproj` pour le français, et `Base.lproj` resterait de l'anglais. Avec les
deux, le résultat est « français » quelle que soit la règle : un essai manqué
coûte un build, un envoi et un numéro.

**Pourquoi `InfoPlist.strings` et sans clé.** C'est le fichier localisé le
plus ordinaire d'un paquet iOS, et il ne change rien à l'exécution tant qu'il
est vide : iOS lit alors les valeurs de `Info.plist`. Les textes de permission
restent là où ils sont — des réglages de build par saveur
(`mobile/ios/tool/…`, épinglés par le groupe « purpose strings are per
flavour ») : un fichier de chaînes partagé ne pourrait pas dire « MyWeli » ici
et « MyWeli Pro » là.

`CFBundleLocalizations = [fr]` reste : c'est lui qui met l'interface système en
français.

## 6. Sécurité · 7. Performance

Sans objet : aucune donnée, aucun droit, aucun code exécuté.

## 8. Tests

### 8.1 Dans le dépôt — `ios_store_readiness_test.dart`, vus rouges d'abord

- le projet déclare `developmentRegion = fr` et ne connaît que `fr` et `Base` ;
- `fr.lproj/InfoPlist.strings` existe, **et** le projet le copie : une
  référence de fichier, un groupe de variantes, une entrée dans la phase
  « Resources » de `Runner` (un fichier sur disque que le projet ignore ne
  serait pas dans le paquet) ;
- aucun autre dossier de langue dans `Runner/` que `Base.lproj` et `fr.lproj` ;
- l'iPhone ne déclare que le portrait ; l'iPad garde ses quatre orientations
  (témoin : le test doit distinguer les deux clés) ;
- `CFBundleDevelopmentRegion` reste `$(DEVELOPMENT_LANGUAGE)` — une valeur
  écrite en dur masquerait un `developmentRegion` faux.

Chaque épingle est écrite **avant** le correctif et vue échouer sur les
fichiers d'aujourd'hui.

### 8.2 Sur le paquet construit

Un build de simulateur de la saveur Pro, puis lecture de `Runner.app` :
`CFBundleDevelopmentRegion = fr`, `UISupportedInterfaceOrientations =
[Portrait]`, `fr.lproj` et `Base.lproj` à la racine, aucun `en.lproj`. Les
mêmes lignes rejoignent la vérification de l'IPA
([app-store-forms.md](app-store-forms.md) §11.3) et se relisent sur l'IPA de
production.

### 8.3 Ce qu'aucun test local ne montre

La lecture d'Apple. **Seul oracle : `buildBundles.locales` du build envoyé,
lu par l'API** — il doit valoir `["fr"]` ; le 577 donne `["en"]` (le témoin :
la mesure distingue bien les deux états). S'il vaut encore `["en"]`, ou
`["en", "fr"]`, on ne soumet pas et on rouvre cette spec.

Que l'app ne tourne plus : à voir sur l'iPhone, avec les autres vérifications
de [app-store-forms.md](app-store-forms.md) §11.6.

## 9. Mise en service

PR → CI → fusion → build de production depuis `main` (numéro = nombre de
commits) → vérification de l'IPA → envoi → lecture de `locales` → TestFlight →
rattachement à la version 0.0.1. Aucun serveur, aucun déploiement.

## 10. Définition de « fait »

Les épingles vues rouges puis vertes ; le paquet de simulateur relu ;
`flutter analyze` à 0 ; sur le build envoyé, `locales = ["fr"]` ; la ligne de
[app-store-forms.md](app-store-forms.md) §14 sur `CFBundleDevelopmentRegion`
et celle sur le paysage retirées du registre des points ouverts.

## 11. Questions ouvertes

1. **Android en paysage** — même verrou à poser dans le manifeste
   (`android:screenOrientation`), ou une passe en paysage ? Non décidé ; rien
   ne change sur Android ici.
2. **L'app consommateur est verrouillée elle aussi sur iPhone**, par
   construction (un seul `Info.plist`). C'est cohérent — elle n'a pas été
   essayée en paysage non plus — mais la décision du propriétaire portait sur
   Pro : à confirmer, ou à séparer par saveur avant sa propre soumission.
