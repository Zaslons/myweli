# Supprimer un compte Pro — la ligne d'équipe qui bloquait l'effacement — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-14** sur `fix/provider-deletion-member-fk` — **non fusionné, non déployé**. La fusion et le déploiement en production attendent chacun le mot du propriétaire. |
| **Module** | `access` (les lignes d'équipe) · compte Pro (la suppression, menace T53) |
| **Origine** | Le propriétaire, le 2026-10-14, pendant les vérifications du build 587 avant « Submit for Review » : un compte Pro tout neuf, « Supprimer » → « Une erreur est survenue ». |
| **Bloque** | La soumission de MyWeli Pro : Apple essaie la suppression de compte (règle 5.1.1(v)) sur un compte qu'il crée lui-même. |
| **Régit** | `backend/lib/src/db/migrations.dart` (0038) · `backend/lib/src/db/postgres_provider_auth_repository.dart` (`deleteAccount`) · `backend/lib/src/access/membership_repository.dart` + `backend/lib/src/db/postgres_membership_repository.dart` (`deleteAllForAccount`) · `backend/lib/src/provider_account_service.dart` |
| **Liés** | [pro-account-deletion-export.md](pro-account-deletion-export.md) (le parcours, T53) · [team-access-r1-foundation.md](team-access-r1-foundation.md) §7 · [team-access-r6-multi-salons.md](team-access-r6-multi-salons.md) §4 · [demo-account-deletion-lock.md](demo-account-deletion-lock.md) (son « non vérifié en production : qu'un compte ordinaire se supprime encore » — c'est ce trou) |
| **Skills consultés** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Le défaut, vérifié avant d'écrire

**Ce que dit la production.** Les journaux Cloud Run de `myweli-api` montrent
trois `DELETE /me/provider` à 20:06:18, 20:07:02 et 20:10:26 UTC (révision
`myweli-api-00037-zzq`), tous en **500** avec
`unhandled_route_error … type=ForeignKeyViolationException`. Sur 60 jours, la
route n'a reçu que six appels : ces trois 500, deux 403 du compte démo (le
verrou, comme prévu) et un 401. **Aucune suppression de compte Pro n'a jamais
abouti en production.**

**Le chemin du code.** `ProviderAccountService.deleteAccount` appelait
`revokeAllForAccount`, un `UPDATE … SET status = 'revoked'` qui **garde
`account_id`**, puis `PostgresProviderAuthRepository.deleteAccount`, qui
supprime la ligne `provider_users`. Or `provider_members.account_id` référence
`provider_users(id)` **sans action ON DELETE** (migration 0027) : la ligne
révoquée retient l'identité, et le `DELETE` échoue. Le test l'a reproduit mot
pour mot : `23503 … violates foreign key constraint
"provider_members_account_id_fkey" on table "provider_members"`.

**Qui est touché.** Tout compte qui porte une ligne d'équipe, c'est-à-dire
**tout propriétaire de salon** (la ligne « owner » est écrite à la création du
salon) et tout membre qui a accepté une invitation. Un compte sans salon ni
équipe se supprimait. **Depuis quand** : le 2026-07-12 (#222, team access R1 —
la migration et l'appel arrivent ensemble).

**Pourquoi aucun test ne l'a vu.** Tous les tests de suppression tournaient sur
les jumeaux en mémoire, qui n'ont pas de clés étrangères. Aucun test Postgres
n'appelait `deleteAccount`, ni côté Pro ni côté client.

**L'état partiel.** Le service n'est pas une transaction. La requête qui échoue
a déjà, dans l'ordre : passé les salons en `draft`, effacé les documents KYC,
supprimé appareils et notifications, **révoqué les lignes d'équipe**, puis — dans
le dépôt — supprimé les jetons de session et les codes, avant que le dernier
`DELETE` n'échoue. Le compte survit donc, déconnecté, avec sa ligne
« owner » révoquée — l'état du compte de test du propriétaire en production
(§9). **Lu dans le code, pas observé** : à la reconnexion, `GET /me/provider`
trouve le salon par le lien `account.providerId` ; `memberOf`, ne voyant aucune
ligne active, passe par son auto-réparation `ensureOwner`, qui en Postgres
renvoie la ligne existante telle quelle (`ON CONFLICT … DO UPDATE SET
account_id`), révoquée comprise, et l'accès se résout par le rôle. Le compte
devrait donc se reconnecter en propriétaire et retrouver « Supprimer » — ce qui,
avant ce correctif, rejouait le même 500.

## 2. Ce que voit l'utilisateur

« Supprimer mon compte » aboutit : 204, l'app suit le parcours prévu
([pro-account-deletion-export.md](pro-account-deletion-export.md)). Un membre
d'équipe qui supprime son compte **disparaît** de la liste « Équipe » du salon
au lieu d'y rester « révoqué » avec son adresse : la suppression est
« définitive », l'adresse e-mail en fait partie.

## 3. Contrat d'API

Inchangé : `DELETE /me/provider` → 204 · 403 `demo_account_locked` /
`forbidden` · 409 `future_bookings`. Aucune modification d'`openapi.yaml`.

## 4. Les trois changements

| # | Où | Avant | Après |
|---|---|---|---|
| a | Migration **0038** `0038_provider_members_account_cascade` | `account_id text REFERENCES provider_users(id)` (aucune action) | même clé, **`ON DELETE CASCADE`** — comme `provider_refresh_tokens` depuis toujours |
| b | `ProviderAccountService` + `MembershipRepository` | `revokeAllForAccount` (UPDATE, la ligne reste) | **`deleteAllForAccount`** (DELETE ; `removeWhere` dans le jumeau en mémoire), appelé **après** la suppression de l'identité |
| c | `PostgresProviderAuthRepository.deleteAccount` | quatre `DELETE` l'un après l'autre | les mêmes quatre **dans une transaction** |

**Pourquoi (a) et (b) ensemble.** (a) est la cause : le schéma dit enfin ce
que le code annonçait (« a member row must never outlive its account »), et
protège tout futur chemin qui supprimerait une identité. (b) garde les deux
jumeaux d'accord : avec (a) seul, Postgres effacerait les lignes et le jumeau en
mémoire les garderait révoquées — deux vérités, et des tests qui affirment la
mauvaise. Supprimer plutôt que révoquer, c'est aussi ne pas garder l'adresse
d'une personne qui a demandé l'effacement.

**Après l'identité, jamais avant** (relevé par la revue adverse du premier
commit, `959c9634`). En Postgres, la cascade de (a) supprime les lignes **dans
la transaction de l'identité** ; (b) vient ensuite et n'en trouve plus — il
sert au jumeau en mémoire. Appelé avant, (b) ouvrait deux défauts : une
suppression de l'identité qui échoue perdait les lignes pour de bon (le lien
scalaire ne recrée que la ligne « owner » du salon lié — pas celle d'un second
salon possédé, pas une place de « staff ») ; et dans l'intervalle, un compte
encore vivant sans aucune ligne d'équipe faisait créer un salon par
`GET /me/provider` (l'auto-provisionnement ne se retient que si le compte a au
moins une ligne) — un salon orphelin pour un compte de « staff ».

**Pourquoi (c).** Une suppression qui échoue ne doit rien laisser à moitié.
(c) couvre l'identité, ses sessions, ses codes et — par la cascade — ses
lignes d'équipe. Restent hors transaction les étapes du service qui précèdent
(dépublier, KYC, appareils, notifications) : elles traversent plusieurs dépôts
et le stockage. Ce qui rend ce reste acceptable : chacune est idempotente et
voulue par l'utilisateur, et un échec laisse un compte entier — identité,
sessions, équipe — qui peut relancer la suppression.

**La migration.** `DROP CONSTRAINT IF EXISTS provider_members_account_id_fkey`
puis `ADD CONSTRAINT … ON DELETE CASCADE`, dans la transaction unique de la
migration : il n'existe aucun instant sans clé. Le nom est celui que produit le
`REFERENCES` en ligne de 0027 (`<table>_<colonne>_fkey`), lu dans l'erreur 23503
de la base de test sur le même DDL. **Sûre au retour arrière** : la clé accepte
exactement les mêmes lignes ; une image plus ancienne (révoquer puis supprimer)
réussit désormais au lieu d'échouer. **Verrous** : les deux tables comptent
quelques dizaines de lignes ; l'attente est bornée par le `lock_timeout` de 3 s
des migrations, et un échec laisse l'ancienne révision servir.

## 5. Sécurité

Aucun nouveau point d'entrée, aucune nouvelle frontière de confiance. T53 se
renforce : l'identité, ses sessions et ses lignes d'équipe partent ensemble.
Le verrou démo (T69) répond toujours **avant** toute écriture — rien ne change
dans cet ordre, et l'inventaire `demo_locks_inventory_test.dart` (un seul
`DELETE FROM provider_users`, un seul appelant) reste vert.

## 6. Performance

Un `DELETE` indexé (`provider_members_account`) au lieu d'un `UPDATE` ; une
transaction de quatre instructions au lieu de quatre allers-retours séparés.

## 7. Tests — chacun vu rouge d'abord

Dans `backend/test/db/postgres_repositories_test.dart` (le fichier qui vide
`provider_users` avant chaque test : un fichier à part courrait contre lui sous
`dart test`), groupe « provider account deletion — on the real schema (T53) » :

1. **Le chemin de production, de bout en bout** — le câblage de
   `dependencies.dart` sur la vraie base : un propriétaire avec un salon actif,
   un coéquipier, une place de « staff » dans un second salon, un appareil, une
   notification. Rouge sur le code d'avant avec **l'erreur exacte de la
   production** (23503, `provider_members_account_id_fkey`). Vert : compte,
   sessions, lignes d'équipe, appareil et notification partis ; le salon en
   `draft` ; le coéquipier garde sa place ; l'autre salon garde son
   propriétaire et reste `active`.
2. **La classe, pas seulement l'instance** — aucune clé étrangère vers
   `users`, `provider_users` ou `admins` n'a une action qui bloque (`a`/`r`) ;
   au moins quatre clés trouvées, pour que la vérification ne passe pas à vide.
   Rouge avant : exactement `provider_members.account_id → provider_users: a`.
3. **Une suppression qui échoue ne change rien** — une table-sonde (créée puis
   supprimée dans le test) retient l'identité ; le `DELETE` lève, et les
   sessions sont toujours là. Rouge avant : 0 session sur 1 — supprimées avant
   l'instruction qui échoue.
4. **Les lignes d'équipe partent avec l'identité, jamais avant** — le service
   entier, la même table-sonde : la suppression lève, et la ligne « owner » est
   toujours là. Rouge sur le premier commit du correctif (`959c9634`, où
   `deleteAllForAccount` passait avant l'identité) : 0 ligne sur 1.

Les tests en mémoire disent la même chose : les lignes d'équipe d'un compte
supprimé sont **vides**, pas révoquées (`provider_account_service_test.dart`,
`membership_test.dart`). Les quatre tests qui se servaient de
`revokeAllForAccount` pour fabriquer un membre révoqué révoquent désormais la
ligne elle-même (`revoke(id)`) — c'est ce qu'ils testent.

Suite complète sur une base neuve (les 38 migrations), après la correction de l'ordre : 1 741 réussis, 2
ignorés, 0 échec. La migration a aussi été appliquée à une base portant
l'ancienne clé, comme le fera la production : une seule clé sur
`account_id`, désormais `c`.

**Revue adverse** (trois angles — la migration en production, la justesse et
les jumeaux, la sécurité et le verrou démo —, chaque constat repris par un
sceptique) : rien sur la migration (nom de la clé, verrous, retour arrière,
validation) ; l'ordre ci-dessus, corrigé ; deux défauts **antérieurs** à ce
correctif, hors de son périmètre et suivis à part — une réinvitation après
révocation ou expiration répond 500 en Postgres (`UNIQUE (provider_id,
email)`), et `POST /auth/provider/register` accepte un `providerId` venu du
client.

## 8. Mise en service

PR → CI → **fusion sur le mot du propriétaire** → **déploiement en production
sur son « go » explicite** (`deploy-backend.yml`, `environment=production`) →
vérifier la révision servie (digest) → le propriétaire recrée un compte Pro neuf,
crée le salon, « Supprimer » → attendu : la suppression aboutit. C'est le seul
oracle qui compte, parce qu'il passe par le même bouton qu'Apple.

## 9. Le compte de test laissé à moitié en production

La migration ne touche pas à sa ligne « owner » révoquée, et n'en a pas
besoin : une fois le correctif en production, la suppression de l'identité
l'emporte par la cascade. D'après le code (§1), le compte se
reconnecte en propriétaire avec **la même adresse** : c'est **le meilleur essai
possible** — le compte même qui a échoué, par le même bouton. Si la reconnexion
n'atteignait pas « Supprimer » (ce que §1 prédit sans l'avoir vu), deux voies :
refaire l'essai avec une **autre adresse e-mail**, et laisser celui-ci (aucune
donnée réelle avant le lancement, un salon `draft` invisible partout) ou le
**supprimer à la main** — avec l'accord du propriétaire, c'est une écriture en
base de production.

## 10. Définition de « fait »

Les quatre tests vus rouges puis verts ; la suite complète verte ; `dart
analyze` à 0 ; CI verte ; fusion ; déploiement ; **un compte Pro neuf supprimé
avec succès depuis l'iPhone**. Ensuite seulement, « Submit for Review ».

## 11. Questions ouvertes

1. **Le reste du service hors transaction.** Atteindre l'atomicité de bout en
   bout demanderait une transaction partagée entre dépôts (et le stockage n'y
   entrera jamais). Non fait ici : avec (a), il ne reste aucune cause connue
   d'échec du dernier `DELETE`, et un échec laisse un compte entier.
2. **La suppression côté client** (`DELETE /me`) n'a pas non plus de test
   Postgres. Le test 2 couvre sa seule clé étrangère (`refresh_tokens.user_id`,
   en cascade) ; un test de bout en bout reste à écrire.
3. **`ensureOwner` diverge entre les jumeaux.** En Postgres il renvoie une
   ligne existante telle quelle, révoquée comprise, et ni `memberOf` ni `can`
   ne relisent son statut : une ligne « owner » révoquée sur le salon lié
   garde les droits du rôle, alors que `can` se dit « `status != active` →
   false ». Le jumeau en mémoire, lui, ajoute une nouvelle ligne active.
   **Inatteignable par le produit aujourd'hui** : la gestion d'équipe refuse de
   révoquer un propriétaire (`owner_protected`), et la suppression — le seul
   chemin qui le faisait — supprime désormais. À aligner dans une tranche à
   part, sans toucher à ce correctif.
