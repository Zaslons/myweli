# L'inscription Pro ne lie plus un salon choisi par le client — spec (T72)

| | |
|---|---|
| **Statut** | **Construit, fusionné (#595, `94875708`) et déployé en production le 2026-10-14** — révision `myweli-api-00039-mgq`, image `sha256:9497b203…` (= l'étiquette `9c0540a`), sur le « go » du propriétaire. **Non exercé en production** : le vérifier là-bas demanderait de créer un compte ; la preuve est le test de route vu rouge, et l'empreinte de l'image servie. **Vérifié le 2026-10-14 vers 23:26 UTC, en lecture seule** (owner's go ; `cloud-sql-proxy` 2.26.0 installé pour l'occasion, identifiants lus dans Secret Manager sans être affichés, session `default_transaction_read_only=on` + `BEGIN READ ONLY … ROLLBACK`) : témoin — 2 comptes Pro, 3 salons, 2 lignes d'équipe, toutes « owner », dans deux salons distincts ; **0** salon avec plus d'une ligne « owner », **0** salon lié depuis plus d'un compte, **0** compte lié à un salon dont la ligne « owner » est à un autre compte, **0** invitation adressée à l'identité démo. **Aucune trace d'exploitation.** (Le troisième salon est le brouillon laissé par le compte de test supprimé — attendu, T51.) |
| **Module** | auth Pro · `access` (lignes d'équipe) |
| **Origine** | La revue adverse du correctif de suppression ([backend-provider-deletion-member-fk.md](backend-provider-deletion-member-fk.md)), le 2026-10-14 : constat « bloquant », confirmé par un sceptique, puis relu ici avant d'écrire. |
| **Régit** | `backend/routes/auth/provider/register.dart` · `docs/api/openapi.yaml` (`POST /auth/provider/register`) · `web/lib/api/schema.ts` (régénéré) |
| **Menace** | **T72** ([BACKEND.md](../BACKEND.md) §7) |
| **Skills consultés** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Le défaut, vérifié avant d'écrire

`POST /auth/provider/register` lisait un champ facultatif `providerId` dans le
corps de la requête et le passait tel quel au dépôt, sur les trois branches
d'identité (Google, Apple, e-mail + code). Le dépôt l'écrit dans
`provider_users.provider_id` — une colonne `text` sans clé étrangère ni unicité
— sans rien vérifier. Ensuite `_provisioned` appelle
`SalonProvisioningService.ensureSalon` : comme le compte a déjà un
`providerId`, il prend la branche « déjà lié » et appelle `ensureOwner`, qui
écrit une ligne **« owner » active** pour ce compte dans ce salon (les adresses
diffèrent, donc pas de conflit sur `(provider_id, email)`).

**Conséquence.** Quiconque prouve *une* identité — son propre compte Google,
son Apple ID, ou son adresse e-mail et le code reçu — devient **propriétaire de
n'importe quel salon** dont il connaît l'identifiant, et l'identifiant d'un
salon publié est public (sa page, ses réservations). Propriétaire veut dire : les
clientes du salon (noms, téléphones), l'agenda, l'équipe, et les coordonnées
d'acompte — un attaquant pourrait y mettre son propre numéro Mobile Money.

**Ce que le test a montré sur le code d'avant** : le compte créé revient lié à
l'identifiant du salon visé (`provider_…` = l'identifiant de la victime).

**Aucun client légitime n'envoie ce champ** : ni l'app (`api_auth_service.dart`,
les trois appels à `/auth/provider/register`), ni le web
(`web/app/api/pro/auth/register/route.ts`), ni le test de fumée
(`funnel_smoke_test.dart`). Seuls des tests au niveau du dépôt passent un
`providerId` — directement à `register(...)`, pas par la route.

**Depuis quand** : la route lit ce champ depuis #49 (2026-06-23).

**Non vérifié** : si la production a été exploitée. Une requête en lecture seule
le dirait (§8). Ce qui rend la chose peu probable sans la prouver : le
2026-10-14, `GET https://api.myweli.com/providers` liste **0 salon publié**
(lu ce jour-là) — aucun identifiant n'était donc offert par la liste publique ;
ceux des brouillons (`provider_<microsecondes>`) ne se devinent pas d'un coup.
Une fois des salons publiés, leur identifiant est public par construction :
c'est la clé de leur page et de chaque réservation.

## 2. Ce que voit l'utilisateur

Rien. L'inscription se déroule à l'identique et crée, comme toujours, le salon
brouillon du compte.

## 3. Contrat d'API

`providerId` disparaît du corps de `POST /auth/provider/register` dans
`openapi.yaml`, dont la description dit désormais la règle (le salon est
toujours nouveau). Les types du web sont régénérés (`npm run gen:api`) : un
seul champ facultatif en moins, que rien n'utilisait (`tsc --noEmit` : 0).
**Un client qui enverrait encore le champ n'échoue pas** : il est ignoré, pas
refusé — aucun client à casser, et un refus n'apprendrait rien de plus à un
attaquant.

## 4. Le changement

La route ne lit plus `providerId`, et ne le passe plus à `repo.register(...)`
sur aucune des trois branches. Le paramètre du dépôt reste — les tests du dépôt
s'en servent pour fabriquer un compte lié — mais plus rien de ce qu'un client
envoie ne l'atteint. `linkProvider`, l'autre façon de lier un compte à un
salon, n'a qu'un appelant : la branche « création » d'`ensureSalon`, qui lie le
compte au salon qu'elle vient de créer.

## 5. Sécurité

T72 ajoutée au modèle de menaces. Aucun nouveau point d'entrée.

**Seconde ligne, non faite ici** : qu'`ensureSalon`, sur la branche « déjà
lié », refuse d'écrire une ligne « owner » quand le salon en a déjà une pour un
autre compte. Plus rien n'atteint cette branche avec un salon étranger ; la
seconde ligne protégerait d'un futur chemin qui recréerait le défaut (§9).

## 6. Performance

Sans objet.

## 7. Tests — vus rouges d'abord

Dans `backend/test/auth/provider_auth_test.dart`, groupe « a salon is never
claimed by id at registration (T72) » :

1. **Comportement** — un salon « victime » existe ; une inscription Google
   envoie son identifiant dans `providerId`. Attendu : 201, un salon brouillon
   **neuf** pour le compte, et **rien** dans le salon victime. Rouge avant : le
   compte revient lié à l'identifiant de la victime.
2. **Structure** — la route, commentaires retirés, ne contient ni
   `body['providerId']` ni `providerId:` ; témoin : elle contient bien
   `body['phoneNumber']`. Ce test tient les trois branches, que le test 1 ne
   conduit pas toutes. Rouge avant.

## 8. Mise en service et vérifications

PR → CI → fusion sur le mot du propriétaire → déploiement en production sur son
« go » (peut partir avec le correctif de suppression, #594) → vérifier la
révision servie.

**La production a-t-elle été exploitée ?** Requête en lecture seule, à lancer
avec l'accord du propriétaire (lecture de la base de production) : les salons
avec plus d'une ligne « owner », et les comptes liés à un salon dont la ligne
« owner » appartient à un autre compte. Attendu avant le lancement : le salon
démo et les salons de test du propriétaire seulement.

## 9. Questions ouvertes

1. La seconde ligne de §5 — dans une tranche à part.
2. Le paramètre `providerId` de `ProviderAuthRepository.register` : le retirer
   aussi demanderait de réécrire les tests du dépôt qui fabriquent des comptes
   liés. À faire si un autre appelant apparaît.
