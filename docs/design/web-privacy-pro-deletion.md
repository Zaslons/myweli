# The privacy policy tells a Pro the truth about deletion (B0.23)

| | |
|---|---|
| **Module** | web — text only, `web/app/politique-confidentialite/page.tsx` (one of the five store-linked pages), `web/lib/legal.ts` `LEGAL_UPDATED_AT`, `infra/legal/registration-manifest.json`; and one internal row of [play-store-forms.md](play-store-forms.md) |
| **Status** | **Approved 2026-11-13 (decision 143). Built 2026-11-14 on `fix/web-privacy-pro-deletion` (stacked on this spec's docs PR, #790); not merged, gated by §7. A review of the branch (2026-11-14) put one question back to the owner on sentence 2's wording (§7, item 6); **answered the same day, decision 145: (b), « Verify first »** — §2's quote, the page and its pin carry it.** The owner approved the eight sentences of the B0.23 draft (session notes, not in the repo; a review's 14 findings folded in before the owner read it), with R2 (b), options A and B, « en détail », and the identity documents named in full |
| **Owner** | the project owner: the merge (a production deploy of the website), on the day `LEGAL_UPDATED_AT` names |
| **Last updated** | 2026-11-14 |
| **PRD ref / phase** | FR-AUTH-005 [V1] (`docs/PRD.md:344`) · V1 · gates android-play-release step 7 (decision 137) |
| **BACKLOG item** | B0.23 · decisions 137, 138, 143 · R2 of [web-pro-account-deletion.md](web-pro-account-deletion.md) §12 |
| **ROADMAP entry** | [2026-11-13-pro-account-deletion-spec.md](../roadmap/entries/2026-11-13-pro-account-deletion-spec.md) |
| **Skills checked** | myweli-web-guardrails (invoked for this spec) · [WEB.md](../WEB.md) · [WEB-SYSTEM.md](WEB-SYSTEM.md) §15 · decision 73 (the five pages) |
| **Related** | [web-pro-account-deletion.md](web-pro-account-deletion.md) §5.1, §11 (the page it must agree with) · [pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) (B0.22, O1, O2) · [admin-pro-account-erase.md](admin-pro-account-erase.md) (the procedure the new sentence promises) · [legal-l1.md](legal-l1.md) · [app-store-forms.md](app-store-forms.md) §7.3 (decision 144) |

OBSERVED = read at `main` `d19655bd`. INFERRED = reasoned from it. Line numbers are `page.tsx`'s unless named.

## 1. Goal & scope

The policy sends Pros to the client « Mon compte » (`:290-291`), says nothing of a deleted owner's salon,
its photos or the team's log, promises « sans nous écrire » to people who must write to support (decision
139), and calls `/suppression-compte` an itemised list it is not. **In:** the eight approved sentences (§2),
the date (§4), the Data safety row (§5). **Out:** the CGU's « supprimer votre compte à tout moment »
(`web/app/cgu/page.tsx:52-53,137-138`), a separate text decision; `/suppression-compte` (decision 140, Q9 (a)).

## 2. The approved sentences, before → after

JSX as the page writes it: `’`, `&nbsp;` before `; : ? !`, a `{' '}` before a `<strong>` or `<A>` that
starts a line, the shared `P` (so the glued-word scan, `web/tests/legal.test.tsx:297-322`, and the
bodyLarge check keep passing).

**1. « Vos droits », the web clause** (`:290-291`; the two app clauses before it stay word for word, pinned
by `legal.test.tsx:274-280`)
> Avant : « … ; sur le web, depuis Mon compte. »
> Après : « … ; sur le web, depuis Mon compte pour un compte client, et depuis **Profil → Compte** une fois connecté avec votre compte professionnel (l’export y est réservé au propriétaire du salon). »

**2. « Vos droits », R2 (b): a new `<P>` between the first paragraph and « La page Supprimer votre compte… » — as amended by decision 145 (2026-11-14)**
(« sans nous écrire » stays)
> Après : « Si vous ne pouvez plus vous connecter à votre compte, ou si votre accès à l’équipe d’un salon vous a été retiré, écrivez-nous depuis la page Aide & Support : nous vous répondrons pour vérifier, depuis l’adresse e-mail de votre compte, qu’il s’agit bien de votre compte ; cette vérification faite, nous confirmerons sa suppression, aux mêmes conditions que si vous la faisiez vous-même. »

« Aide & Support » is an `<A>` to `/support`, not the address: printing `support@myweli.com` widens the page at 200 % text
(WEB-SYSTEM §15 row 38). It promises a reply, as the B0.19 page does, never an automatic deletion; the
reply is [admin-pro-account-erase.md](admin-pro-account-erase.md) §10.

**3. « Vos droits », the pointer** (`:294-295`)
> Avant : « La page Supprimer votre compte décrit poste par poste ce qui est supprimé, … »
> Après : « La page Supprimer votre compte décrit en détail ce qui est supprimé, … »

**4 and 5. The Pro paragraph** (`:161-171`, replaced whole; the identity documents named in full, as Data
safety lists them, `play-store-forms.md:381`; the anchor « pièces d’identité et d’immatriculation » kept
word for word, `infra/legal/registration-manifest.json`)
> Après : « **Si vous êtes professionnel**, vous nous transmettez en outre des documents de vérification : des pièces d’identité et d’immatriculation, une photo de votre visage et un justificatif d’adresse. Ils sont stockés dans un espace privé et séparé, ne sont jamais publiés, et ne sont consultables que par un administrateur MyWeli au moyen d’un lien signé valable cinq minutes. Chaque consultation est journalisée. Ils sont effacés si vous supprimez votre compte, et un document que vous remplacez l’est dès son remplacement. Cet effacement est fait **au mieux** : si notre stockage est indisponible lors de la suppression, ou lorsque vous remplacez ou renvoyez un document, un fichier peut subsister dans notre stockage privé, jamais publié. Si vous supprimez votre compte, chaque salon dont vous êtes propriétaire est retiré du public. Son nom et son historique — rendez-vous et avis — restent, pour vos clients ; ses numéros de téléphone, WhatsApp et Mobile Money et son adresse sont effacés, ainsi que son point sur la carte. »

« ainsi que » keeps the shared pin (`legal.test.tsx:340-354`, run on this page and `/suppression-compte`)
green with no change.

**6. « Conservation », a new `<P>` after the first** (with option A before « Restent aussi »)
> Après : « **Si vous supprimez un compte professionnel**, chaque salon dont vous étiez propriétaire reste dans notre base, caché du public : son nom, sa description, ses prestations, ses horaires, son équipe, ses rendez-vous, son fichier clients et ses avis, ainsi que sa commune et sa ville. Les membres de son équipe y gardent accès. Ses photos — galerie, logo, avant/après, photos de l’équipe — ne sont plus affichées au public sur MyWeli, mais restent accessibles à leur adresse existante pour qui la connaît. Le journal des décisions de notre équipe sur ce compte et ses salons — vérification d’identité acceptée ou refusée, avec le motif écrit d’un refus, suspension d’un salon avec son motif — est conservé de même. Restent aussi, jusqu’à ce qu’ils soient retirés : les e-mails reçus par notre équipe lorsqu’un salon validé a changé d’adresse, de téléphone ou de point sur la carte, dans notre messagerie ; une invitation qu’un autre salon vous avait envoyée et que vous n’aviez pas acceptée, avec votre adresse e-mail ; votre fiche de collaborateur dans l’équipe d’un salon dont vous étiez seulement membre (nom, photo). **Aucune durée de conservation n’est fixée à ce jour** : ces informations ne sont pas effacées automatiquement. »

**7. « Conservation », a new `<P>` after it** (with option B at the end)
> Après : « Le journal des actions de l’équipe d’un salon garde des identifiants techniques, les rôles, la date de chaque action et les recherches faites dans sa liste de clients. Aucune durée de conservation n’est fixée à ce jour, et il n’est pas effacé à la suppression d’un compte. Le texte recherché peut être le nom ou le numéro d’un client. »

**8. The date** — « Dernière mise à jour : 13 novembre 2026 » → the day B0.23 merges, on the four
`LegalPage`s (§4).

**If the owner accepts B0.22's O1 gap in writing** (instead of erasing those pins), sentence 6's kept list
ends « …ainsi que sa commune et sa ville et, pour un compte supprimé avant le {date du déploiement de
B0.22}, son point sur la carte », and sentence 5 is qualified the same way. Only on that written answer.

## 3. The five pages' constraints (decision 73)

Every new word was checked against the lists, and the tests below re-check them on the rendered text:
- **No salon link** in the rendered page, chrome included: no `/pro`, `/pro/…` or `/professionnels…` href
  (`web/tests/store-linked-pages.test.tsx:55-56,213-217`). So the policy never names `/pro/suppression-compte`,
  not even as text (S1 adds it to the raw-HTML loop, web spec §10 #15).
- **No salon words**, case-sensitive: `Espace pro`, `Inscrire mon salon`, `MyWeli Pro pour les salons`,
  `Connexion Espace` (`:219-224`); none of `/abonnement|facturation|\boffres?\b|\btarifs?\b|FCFA/i` (`:239-245`).
- **The raw HTML, RSC payload included:** no `SALON_PATHS`, no `SALON_WORDS`
  (`web/tests/e2e/store-linked-pages.spec.ts:18-19,51-61`).
- **The registration scan:** any `immatricul|RCCM` text carries a manifest anchor
  (`web/tests/registration-claim.test.ts:657-700`); the only hit is the kept anchor.
- `/support` is one of the five, not a salon path, so sentence 2's link passes (`toSalons`, `:55-56`).

## 4. `LEGAL_UPDATED_AT` and its manifest rule

The rule (`web/lib/legal.ts:89-126`): one date for the four documents, bumped by any substantive change —
« a privacy policy whose substance moved while its date stood still is the version a regulator reads as
concealment » (`:113-116`). B0.23 is substantive. Today `iso: '2026-11-13'`, `label: '13 novembre 2026'`
(`:127-130`). While `registered` is `false`, `legalDateProblems` requires the manifest's
`legalUpdatedAtWhenPending` (`infra/legal/registration-manifest.json:82`) to **equal** the iso
(`registration-claim.test.ts:169-191`, asserted `:492-499`). **PR checklist:** set `legal.ts` (`iso`,
`label`) and the manifest in the **last commit before merge**, to the merge day (Abidjan = UTC); if the
merge slips, set both again. The docstring gains the « Bumped » note #785 left out (2026-11-13) and
B0.23's. Four of the five serve new HTML (`LegalPage.tsx:54,85` reads the date); `/support` and the
footer do not change.

## 5. play-store-forms §4: the « Historique des recherches » row (`play-store-forms.md:386`)

> | Activité dans les applis → **Historique des recherches via une appli** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | le texte cherché dans « Clients » (`?query=`) : gardé 30 jours dans les journaux de requêtes de Google Cloud, **et** enregistré dans le journal des actions de l'équipe du salon (`provider_audit_log`, action `clients.list`, avec le filtre d'étiquette et la page), qui sert à savoir qui a consulté quel client (T39, T46), **sans durée fixée à ce jour**, y compris après la suppression du compte (décision 138 ; une purge sera décidée par B0.24) — *ajouté le 2026-10-28 ; corrigé le {date} (B0.23, décisions 137 et 143)* |

The added purpose: the copy lives in a security audit trail (`backend/lib/src/clients/provider_audit_log.dart:1-4`;
T39, T46). The Play console answer gains that purpose at step 7. Until this PR, a dated note on the row
says so (decision 144 declares the same data on the App Store label, app-store-forms §7.3).

## 6. Tests — each watched red once by its mutation

| Test | Change | Mutation that turns it red |
|---|---|---|
| `web/tests/legal.test.tsx`, new describe « B0.23 » | « Vos droits » holds « Mon compte pour un compte client », « Profil → Compte une fois connecté avec votre compte professionnel », « l’export y est réservé au propriétaire du salon »; **not** `/sur le web, depuis Mon compte\./` (unanchored: `section()` joins every sibling up to the next h2, `:229-241`) | restore « sur le web, depuis Mon compte. » |
| same | R2 (b): « nous vous répondrons pour vérifier » and an `a[href="/support"]` inside « Vos droits » | drop the paragraph; point it at `mailto:` |
| same | « Vos droits » does not match `/poste par poste/` | restore « poste par poste » |
| same | the Pro paragraph: « une photo de votre visage et un justificatif d’adresse », « un document que vous remplacez l’est dès son remplacement », « au mieux », « chaque salon dont vous êtes propriétaire est retiré du public », « ainsi que son point sur la carte » | drop the replacement sentence |
| same | « Conservation »: « restent accessibles à leur adresse existante », « Le journal des décisions de notre équipe », « Restent aussi, jusqu’à ce qu’ils soient retirés », « une invitation qu’un autre salon vous avait envoyée », « recherches faites dans sa liste de clients », « Le texte recherché peut être le nom ou le numéro d’un client », « Aucune durée de conservation n’est fixée à ce jour » | drop option A; drop option B |
| same | a floor: `LEGAL_UPDATED_AT.iso >= '<B0.23's date>'` | revert the bump |
| `registration-claim.test.ts:492-499` | unchanged; the manifest moves with `legal.ts` | bump one, not the other |
| `legal.test.tsx:274-280`, `:340-354`, `:297-322`, `:59-67` | unchanged; they run on the new text | glue two words across a JSX line break |
| `store-linked-pages.test.tsx:213-245`, `e2e/store-linked-pages.spec.ts:51-90` | unchanged; the ban check on the new text | write « Espace pro » into sentence 1 |
| `registration-claim.test.ts` scan | unchanged | reword the anchor (« documents d’immatriculation ») |
| `mobile/test/infra/play_store_forms_test.dart:235-243` | unchanged: it reads §4's type cell, which §5 keeps | — |

## 7. Preconditions and the merge window

B0.23 merges only when all hold (decision 143):
1. **B0.22 merged, deployed and read back** ([pro-deletion-erase-gaps.md](pro-deletion-erase-gaps.md) §9).
2. **B0.22's O1 settled:** a read-only count, on the owner's yes, of salons with no owner and a pin; if
   not 0, those pins erased once on the owner's yes, or the gap accepted in writing (then §2's variant).
3. **B0.22's O2 settled:** the read-only R2 listing of `kyc/`, or the owner's word that no submission was
   rejected and re-submitted before the deploy.
4. **R1 deployed and read back, and the support procedure approved** (decisions 141, 142;
   [admin-pro-account-erase.md](admin-pro-account-erase.md) §9 steps 3–5; the deploy's place before B0.23 is
   an engineering consequence, not part of decision 143), because sentence 2 sends people to it from day one.
5. **Outside the merge hold** of android-play-release step 3 (c) **and outside any Apple review**: the
   merge changes four of the five pages. Then S1 (web spec §11).
6. **The owner's answer on sentence 2's wording** (raised by a review of the built branch,
   2026-11-14; the words are decision 143's, so only the owner changes them). Sentence 2 tells
   anyone who « ne pouvez plus vous connecter » that we will reply « pour vérifier qu’il s’agit bien
   de votre compte et confirmer sa suppression, aux mêmes conditions que si vous la faisiez
   vous-même ». A Pro who can still read the account's address signs in with « Continuer avec
   e-mail », so a Pro who cannot sign in has, in practice, lost that mailbox, and R1 erases nothing
   without a code confirmed from it ([admin-pro-account-erase.md](admin-pro-account-erase.md)
   §10.1, « No phone callback »: that person gets T4 and nothing is erased). For a lost address,
   `/pro/suppression-compte` promises only a reply « pour vérifier qu’il s’agit bien de votre
   compte »; for a removed access, a reply « pour confirmer la suppression ». The choices:
   (a) keep sentence 2 as approved; (b) *(recommended)* « Si vous ne pouvez plus vous connecter à
   votre compte, ou si votre accès à l’équipe d’un salon vous a été retiré, écrivez-nous depuis la
   page Aide & Support : nous vous répondrons pour vérifier, depuis l’adresse e-mail de votre
   compte, qu’il s’agit bien de votre compte ; cette vérification faite, nous confirmerons sa
   suppression, aux mêmes conditions que si vous la faisiez vous-même. »; (c) two sentences, as the
   Pro page has them: a removed access gets « confirmer », a lost sign-in « vérifier » only. Until
   the answer, the page keeps the approved words. A changed sentence updates §2's quote, the B0.23
   pin of `web/tests/legal.test.tsx` and the page in this PR, each watched red first.
   **✅ Answered 2026-11-14, decision 145: (b), « Verify first »**, the recommendation. §2's quote, the
   page and the « Vos droits » pin of `web/tests/legal.test.tsx` now carry it; the pin was watched red on
   the approved sentence before the page changed.

Then the live read: the policy fetched raw shows the new sentences and date, zero `/pro` href, zero
`SALON_WORDS`; `/cgu`, `/mentions-legales` and `/suppression-compte` differ by the date only.
