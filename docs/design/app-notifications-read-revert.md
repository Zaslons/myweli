# App — « marquer comme lu » raté revient en arrière et le dit — spec

| | |
|---|---|
| **Statut** | **Décidé le 2026-10-16** — la tâche consignée au §9 de [web-consumer-optimistic-revert.md](web-consumer-optimistic-revert.md) (« l'app : `markRead` / `markAllRead` optimistes, sans retour en arrière ») ; construit le même jour sur `fix/app-notifications-read-revert` ; §11 dit ce qui a été vu rouge |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Le retour d'une action (SYSTEM.md §15) · V1 — centre de notifications, app client **et** app Pro (un seul fil partagé) |
| **Module** | app — `providers/notifications_provider.dart` (deux retours), `widgets/notifications/notifications_list.dart` (toucher une ligne), `widgets/notifications/mark_all_read_button.dart` (nouveau : « Tout lire », partagé par les deux écrans), `services/api/api_notification_service.dart` (un code) |
| **ROADMAP entry** | [2026-10-16-app-notifications-read-revert.md](../roadmap/entries/2026-10-16-app-notifications-read-revert.md) |
| **Skills checked** | myweli-dev-guardrails ✓ (aucun changement serveur, aucun contrat) · myweli-verification-guardrails (avant de dire « fait ») |
| **Dépend de** | Rien dans le code. La parité vise [#624](https://github.com/Zaslons/myweli/pull/624) (`fix/consumer-optimistic-revert`, pas encore fusionné) : ce changement ne lit aucun de ses fichiers. Les liens vers sa spec ne mènent nulle part tant qu'il n'est pas fusionné. Seul conflit de texte attendu : la ligne de tête de [README.md](README.md) (garder les deux lignes). |

## 1. Le défaut, vu dans le code

| # | Geste | Ce que fait le code | Ce que voit la personne |
|---|---|---|---|
| 1 | Toucher une notification (`NotificationsList._open`) | `provider.markRead(n.id)` **sans `await`**, puis la navigation. `markRead` passe la ligne lue, puis `await _service.markRead(id)` **sans lire l'`ApiResponse`** | la ligne a l'air lue. Au prochain chargement, elle ne l'est pas. Pas un mot |
| 2 | « Tout marquer comme lu » (l'icône de la barre, les deux écrans) | `onPressed: provider.markAllRead`. `markAllRead` passe **tout** lu, puis `await _service.markAllRead()` sans lire la réponse | l'icône disparaît, plus rien n'est en gras, le badge de la cloche tombe à 0. Au prochain chargement, tout revient non lu |

Hors ligne, `ApiNotificationService._post` rend `ApiResponse.error('Pas de
connexion. Réessayez.')`. Sur un refus du serveur, `_errorFrom` rend le
`message` du corps, et le serveur n'en met pas (`jsonError(404,
'not_found')`) : la phrase serait « Erreur ». Aucun des deux n'est lu
aujourd'hui. Rien ne lève (`RefreshingHttpClient.send` rend `null` sur une
coupure), mais un `markRead` non attendu qui lèverait serait une erreur non
gérée.

Le même `NotificationsProvider` sert l'app client (`/notifications`,
`main.dart`) et l'app Pro (`/pro/notifications`, `main_pro.dart`, sur la
session Pro). Le correctif vaut donc pour les deux.

## 2. Ce que fait le web (parité)

#624, §3.2 ②③ de [web-consumer-optimistic-revert.md](web-consumer-optimistic-revert.md) :

- **Toucher une notification** : elle passe lue, la navigation n'attend pas
  l'écriture. Si la page est toujours là quand l'échec arrive, **cette**
  notification redevient non lue et la phrase s'affiche. Si la page est
  partie, rien n'est dit : au retour, le fil la montre non lue, ce qui est vrai.
- **« Tout lire »** : sur un échec, **seules les notifications que ce geste a
  marquées** redeviennent non lues. Une notification déjà lue avant le geste le
  reste. Le bouton revient, et le focus avec lui s'il était tombé.
- **Les phrases** : statut 0 → « Pas de connexion. Réessayez. », tout autre
  échec → « Une erreur est survenue. Réessayez. ».

Le web écrit la phrase en ligne (`role="alert"`), parce que le client web ne
monte aucun toast. L'app, elle, dit l'issue d'une écriture par `AppSnackBar`
(SYSTEM §15), y compris pour l'échec du ♥ (`provider_detail_screen.dart`,
`provider_card.dart`). L'app garde donc son canal, avec les mêmes phrases.

## 3. Décision

**Un « marquer comme lu » raté remet non lu ce que ce geste a marqué, et
seulement cela, puis dit pourquoi.** Rien d'autre ne change : le geste reste
optimiste, la navigation n'attend toujours pas, un succès reste muet (la ligne
le montre déjà).

### 3.1 Les phrases

| Issue du service | Phrase |
|---|---|
| Pas de réponse (`code: 'network'`, §3.4) | la phrase du service : « Pas de connexion. Réessayez. » |
| Toute autre erreur (un refus du serveur, « Non connecté », une exception) | « Une erreur est survenue. Réessayez. » (le repli de l'app sur le ♥) |

Le message du serveur n'est **pas** montré : il n'y en a pas sur ces deux
routes, et `_errorFrom` le remplace par « Erreur », qui ne dit rien. Le web
fait de même (tout statut autre que 0 donne la phrase générique).

### 3.2 Où et comment

1. **Toucher une notification.** Elle passe lue tout de suite, et sa route
   s'ouvre sans attendre l'écriture (inchangé). Sur un échec, **cette**
   notification redevient non lue : titre en gras, pastille, « Non lu » pour
   le lecteur d'écran. La phrase s'affiche en snackbar d'erreur
   (`AppSnackBar.showOn`, `SnackKind.error`, 6 s), **seulement si le fil est
   encore l'écran au premier plan** (`ModalRoute.isCurrentOf`). Une fois la
   réservation ouverte, la phrase arriverait sur **cet** écran et semblerait
   parler de lui. Au retour, la ligne est non lue, ce qui est vrai : c'est la
   règle du web. Un second toucher sur une ligne déjà lue (l'optimisme) ne
   renvoie rien : il n'y a qu'une écriture par geste.
2. **« Tout marquer comme lu ».** Tout passe lu et l'icône disparaît (inchangé).
   Sur un échec, **seules les notifications non lues au moment du geste**
   redeviennent non lues. Une notification lue avant reste lue. Une
   notification touchée juste avant, dont l'écriture est encore en vol, garde
   sa propre issue. Une notification arrivée par un rechargement pendant ce temps n'est
   ni retirée ni modifiée. L'icône revient, et la phrase s'affiche (même règle
   du premier plan). **Le focus** : si l'icône avait le focus clavier quand on
   l'a activée, il est tombé avec elle. Il revient sur elle, **seulement**
   s'il est encore « nulle part » (sur un `FocusScopeNode`). On ne le vole
   jamais à ce qu'on a focalisé entre-temps. Un toucher au doigt ne donne pas
   le focus à un bouton Material, donc rien ne bouge dans ce cas.
3. **Un seul « Tout lire » pour les deux écrans.** L'icône était copiée à
   l'identique dans `notifications_screen.dart` et
   `pro_notifications_screen.dart` (même `Consumer`, même commentaire A15).
   Elle devient `MarkAllReadButton` (`widgets/notifications/`), à côté de la
   liste qu'elle partage déjà. C'est la logique du fichier : « le fil, ses
   quatre états et le geste vivent ici une fois ». Le correctif ne peut ainsi
   pas atteindre un écran et manquer l'autre.

**Pourquoi « seulement ce geste », et jamais un instantané** (SYSTEM §15,
« Undo undoes ONE action ») : remettre la liste d'avant le geste ressusciterait
l'état d'une notification touchée entre-temps, et effacerait une notification
arrivée par un rechargement. Le retour en arrière porte sur des **identifiants**
et s'applique à la liste **courante**.

### 3.3 Le contrat du provider

```dart
/// null quand le serveur a pris l'écriture (ou qu'il n'y avait rien à faire),
/// sinon la phrase à montrer.
Future<String?> markRead(String id);
Future<String?> markAllRead();
```

`markRead` et `markAllRead` rendaient `Future<void>`. Leur retour était ignoré
partout (`notifications_list.dart`, les deux `onPressed`) : aucun appelant ne
casse. Une exception du service est lue comme un échec (la phrase générique),
comme le fait `load()`.

### 3.4 Le service

`ApiNotificationService._networkError` porte désormais `code: 'network'`
(comme `ApiProviderService.getProviderById`). C'est ce qui distingue « pas de
réponse » d'un refus, sans comparer des phrases. Les autres lecteurs de
`_networkError` (`getNotifications`, les préférences) lisent `error`, qui ne
change pas.

## 4. Les états

Aucun état d'écran nouveau : les quatre états du fil (`NotificationsList`) ne
changent pas. Ce qui s'ajoute, c'est l'état « l'écriture a échoué » de chaque
geste : la ligne (ou les lignes) d'avant, plus une snackbar.

## 5. Accessibilité

- La snackbar est une région live (`Semantics(liveRegion: true)`, SYSTEM §15).
  On n'ajoute pas de `SemanticsService`.
- La pastille, le gras et « Non lu » reviennent ensemble : l'état est lisible
  sans la couleur (§13.6).
- Le focus clavier de « Tout lire » revient sur l'icône (§3.2 ②). L'icône garde
  ses 48 dp, son infobulle (« Tout marquer comme lu ») et le commentaire A15
  (une icône, pas un libellé).

## 6. Contrat, sécurité, performance

Aucun changement d'API, de contrat (`openapi.yaml`), de serveur. Un champ de
plus sur une `ApiResponse` d'erreur (`code`). **Sécurité** : rien n'est ouvert,
le serveur reste l'autorité sur l'état lu. **Performance** : un `Set`
d'identifiants par geste, une liste recopiée au retour en arrière (≤ 50
notifications, `listForUser`), aucune requête en plus.

## 7. Déploiement

L'app au prochain build (client et Pro). Rien côté serveur ni web.

## 8. Copie

Aucune phrase nouvelle : « Pas de connexion. Réessayez. » (le service) et
« Une erreur est survenue. Réessayez. » (le ♥) existent déjà dans l'app.

## 9. Hors périmètre, consigné

- **Un rechargement pendant une écriture en vol** : si `load()` rend la
  notification non lue (l'écriture n'a pas encore atteint le serveur) et que
  l'écriture réussit ensuite, la ligne reste non lue jusqu'au prochain
  chargement. C'était déjà le cas, le web fait pareil.
- **Une écriture arrivée au serveur mais dont la réponse s'est perdue** : la
  ligne revient non lue alors qu'elle est lue côté serveur, jusqu'au prochain
  chargement. C'est la lecture prudente : on ne dit pas « lu » sans preuve.
- **Une snackbar d'échec encore affichée quand un nouvel essai réussit** : elle
  part d'elle-même (6 s). Le web efface sa phrase en ligne au nouvel essai.
  Une snackbar d'échec suivante remplace la précédente (`showOn` retire la
  courante).
- **Le mock** (`MockNotificationService`) ne simule aucun échec. Les tests
  utilisent un double (`mocktail`).

## 10. Tests (rouges d'abord, contre le code d'avant)

- **Provider** (`test/unit/notifications_provider_test.dart`) : un double du
  service rend une coupure (`code: 'network'`), un refus du serveur (`code:
  'internal_error'`, « Erreur »), puis lève.
  - `markRead` : la notification redevient non lue, l'autre non lue ne bouge
    pas, la phrase est « Pas de connexion. Réessayez. » ou « Une erreur est
    survenue. Réessayez. ». Un succès rend `null` et la laisse lue. Deux
    `markRead` en vol, le premier qui échoue après la réussite du second :
    seul le premier redevient non lu (pas d'instantané).
  - `markAllRead` : seules les non lues du moment redeviennent non lues, une
    notification lue avant reste lue. Un rechargement pendant le vol apporte
    une nouvelle notification : elle est toujours là après l'échec (pas
    d'instantané). Une notification touchée juste avant « Tout lire », dont
    l'écriture échoue pendant le vol de « Tout lire », reste non lue après
    l'échec de « Tout lire ».
- **Service** (`test/unit/api_notification_service_test.dart`) : sans réponse,
  `markRead` / `markAllRead` rendent `code: 'network'` et la phrase.
- **Widgets** (`test/widget/notifications_read_revert_test.dart`) :
  - toucher une ligne sans route, coupure : la ligne est de nouveau « Non lu »
    et la snackbar d'erreur dit « Pas de connexion. Réessayez. » ; refus : « Une
    erreur est survenue. Réessayez. ».
  - toucher une ligne avec route, la route s'ouvre (une vraie page poussée),
    puis l'échec : aucune snackbar. Au retour, la ligne est « Non lu ».
  - « Tout lire » sur l'écran client **et** sur l'écran Pro : l'icône revient,
    les non lues redeviennent non lues, la lue reste lue, la phrase.
  - focus : activée au clavier (Entrée), l'icône retrouve le focus après
    l'échec. Touchée au doigt, le focus ne bouge pas. Focus déplacé ailleurs
    pendant le vol : il y reste.
- **Mutations** à voir rouges, une par garde : chaque retour en arrière retiré ;
  chaque phrase retirée (le retour forcé à `null`) ; la branche `network`
  retirée (la phrase générique hors ligne) ; le `code` retiré du service ;
  « Tout lire » qui remet **tout** non lu ; chaque retour en arrière réécrit en
  instantané ; le `catch` retiré ; la garde du premier plan retirée ; le retour
  du focus retiré, puis sa garde « il avait le focus », puis sa garde « il est
  tombé » ; l'icône des deux écrans remise à l'ancien `onPressed`.

## 11. Construit — vu rouge

- **Vu rouge contre le code d'avant : 23 des 32 nouveaux tests.** Les tests
  de widgets (12 rouges sur 15) et du service (1 sur 2) tournaient tels quels
  contre l'ancien code. Ceux du provider ne compilaient pas (`markRead`
  rendait `void`). On leur a donc donné l'ancien code avec le nouveau type de
  retour (`return null`), et rien d'autre : 10 rouges sur 15. Chacun a échoué
  pour la bonne raison : la ligne encore lue, la phrase `null`, l'exception
  du service qui remonte, « Tout lire » qui ne revient pas, `code` absent. Les
  9 verts épinglent ce qui ne change pas : les succès (5), les cas « rien à
  faire » (2), le code d'un refus (1), et la notification apportée par un
  rechargement (1). Ce dernier ne peut pas rougir contre l'ancien code, qui ne
  revient jamais en arrière. C'est une garde contre l'instantané, vue rouge en
  mutation.
- **Mutations : 22 sur 22 rattrapées**, sur l'arbre commité (le script refuse
  un arbre modifié et restaure depuis HEAD). Pour chaque geste : le retour en
  arrière retiré, la phrase retirée (`return null`). La branche `network`
  retirée. Le `code` retiré du service. « Tout lire » qui remet **tout** non
  lu. Chaque retour en arrière réécrit en instantané. Le `catch` retiré.
  `markRead` qui réécrit une ligne déjà lue, `markAllRead` qui écrit sans
  rien de non lu. Pour la ligne : la snackbar retirée, la garde du premier
  plan retirée, la navigation qui attend l'écriture. Pour le bouton : la
  snackbar retirée, la garde du premier plan retirée, le retour du focus
  retiré, puis sa garde « il avait le focus », puis sa garde « il est tombé ».
  Et l'ancienne icône remise dans chaque écran, client et Pro.
- **Un détail vérifié, pas supposé** : un toucher au doigt ne donne pas le
  focus à l'`IconButton`. Le test « touchée au doigt » le montre, et la
  mutation qui retire la garde « il avait le focus » le fait rougir.
- **Une ligne ajoutée par l'analyseur** : `_open` est devenue `async`, donc
  `context.push(route)` non attendu y est signalé (`unawaited_futures`). Il
  est enveloppé dans `unawaited(...)`, sans changement de comportement :
  `push` se termine quand la réservation est refermée.
- `flutter analyze` : 0. `dart format` : propre. Les sujets a11y du centre de
  notifications (`layout_test.dart`, `primitives_test.dart`) et les gardes
  qui lisent les sources (`design_system_pin_test`, `route_literals_test`,
  `french_test`, `a15_titles_test`, `feedback_test`, `tap_target_test`…)
  sont verts. Le rendu de l'icône ne change pas (même `IconButton`, même
  infobulle) : aucun golden n'est touché.
- **Suite complète de l'app : 2286 verts, 0 rouge**, 52 sautés (les goldens,
  qui ne tournent que sous Linux, dans le workflow de la CI).
