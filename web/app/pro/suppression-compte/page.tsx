import type { Metadata } from 'next';
import {
  A,
  Callout,
  Cta,
  DocumentPage,
  Email,
  H2,
  Lead,
  Li,
  Ol,
  P,
  Step,
  Ul,
  documentMetadata,
} from '../../../components/legal/LegalPage';
import { signInMethods } from '../../../lib/pro/signInMethods';
import {
  PRO_ACCOUNT_DELETION,
  PRO_ACCOUNT_DELETION_UPDATED_AT,
} from '../../../lib/proAccountDeletion';
import { faqJsonLd } from '../../../lib/seo/jsonld';
import { SUPPORT } from '../../../lib/support';

/// Indexed, unlike every other `/pro` page (decision 140): a salon that
/// uninstalled the app finds this by searching « supprimer compte MyWeli Pro »,
/// the only door besides Google Play. docs/WEB.md §4 records the exception.
export const metadata: Metadata = {
  ...documentMetadata(PRO_ACCOUNT_DELETION),
  robots: { index: true, follow: true },
};

/// `/pro/suppression-compte` — how a salon account is deleted on the web, and
/// what that deletion does. The URL Google Play's Data safety form takes as
/// « URL de suppression » for MyWeli Pro.
///
/// Spec: docs/design/web-pro-account-deletion.md (B0.19, decisions 137–140).
/// **Every sentence is the owner's, word for word** (§5.1, approved as written
/// on 2026-11-13), and every claim maps to the code that makes it true (§5.2,
/// §2.3); `tests/pro-account-deletion-page.test.tsx` and the « B0.19 » block of
/// `tests/legal.test.tsx` hold them. A change to a sentence is a new sign-off.
///
/// **Not one of the five pages the apps open** (decision 73): it may lead to
/// `/pro/connexion`, and none of the five may lead here. It is not in
/// `LEGAL_ROUTES`, so no footer links to it. Static, outside `(dash)`: it reads
/// no session, so it cannot fail and caches whole. No `className` here —
/// `LegalPage.tsx` carries them all (WEB-SYSTEM §15 row 25), and its date is
/// its own, never `LEGAL_UPDATED_AT`.
///
/// No install banner: `SiteChrome` gives `/pro/…` the Pro header, and a person
/// leaving is not pushed to install (WEB-SYSTEM §13, the declared exception).
const FAQ = [
  {
    question: 'Puis-je supprimer mon compte MyWeli Pro sans l’application\u00a0?',
    answer:
      'Oui, si vous pouvez vous connecter à l’Espace Pro\u00a0: sur myweli.com, ' +
      'ouvrez Profil, puis Supprimer mon compte en bas de la page. Sinon, ' +
      `écrivez-nous à ${SUPPORT.email}.`,
  },
  {
    question: 'Pourquoi la suppression de mon compte est-elle refusée\u00a0?',
    answer:
      'Parce qu’un rendez-vous confirmé ou en attente est encore à venir dans ' +
      'un salon dont vous êtes propriétaire. Terminez-le ou annulez-le, puis ' +
      'recommencez.',
  },
];

/// A FAQ answer as the page shows it: the support address printed by `Email`,
/// which breaks after « @ » at doubled text; the JSON-LD keeps the plain text.
function Answer({ text }: { text: string }) {
  const [before, ...rest] = text.split(SUPPORT.email);
  return (
    <P>
      {before}
      {rest.map((after, i) => (
        <span key={i}>
          <Email />
          {after}
        </span>
      ))}
    </P>
  );
}

/// Step 1 names only the buttons `/pro/connexion` draws in this build, from
/// the helper `ProLoginOptions` reads (§5.1). E-mail is always drawn.
function methods(): string[] {
  const { google, apple } = signInMethods();
  return [
    ...(google ? ['Continuer avec Google'] : []),
    ...(apple ? ['Continuer avec Apple'] : []),
    'Continuer avec e-mail',
  ];
}

function Methods() {
  const names = methods();
  return (
    <>
      {names.map((name, i) => (
        <span key={name}>
          {i === 0 ? null : i === names.length - 1 ? ' ou ' : ', '}
          <strong>{name}</strong>
        </span>
      ))}
    </>
  );
}

export default function Page() {
  return (
    <DocumentPage
      route={PRO_ACCOUNT_DELETION}
      updatedAt={PRO_ACCOUNT_DELETION_UPDATED_AT}
      extraJsonLd={faqJsonLd(FAQ)}
    >
      <Lead>
        Cette page concerne l’application{' '}
        <strong>MyWeli Pro — Gestion de salon</strong> et l’Espace Pro de
        myweli.com. Vous pouvez supprimer votre compte vous-même, sur le web,
        sans l’application et sans nous écrire. Si vous ne pouvez plus ouvrir
        l’Espace Pro, voyez plus bas.
      </Lead>
      <P>
        Vous avez aussi un compte client MyWeli, sur myweli.com&nbsp;? Votre
        compte client est un compte distinct&nbsp;: supprimer l’un ne supprime
        pas l’autre. Il se supprime depuis une autre page,{' '}
        <A href="/suppression-compte">Supprimer votre compte</A>, celle du lien
        «&nbsp;Supprimer mon compte&nbsp;» en bas de page.
      </P>

      <Callout>
        <P>
          <strong>
            Propriétaire d’un salon&nbsp;: terminez ou annulez d’abord ses
            rendez-vous à venir.
          </strong>{' '}
          Tant qu’un rendez-vous confirmé ou en attente est à venir dans un salon
          dont vous êtes propriétaire, la suppression est refusée et vous
          lisez&nbsp;: «&nbsp;Terminez ou annulez vos rendez-vous à venir avant
          de supprimer votre compte.&nbsp;» Nous ne voulons pas annuler d’office
          les réservations de vos clients.
        </P>
      </Callout>

      <H2>Sur le web, sans l’application</H2>
      <Ol>
        <Step>
          Connectez-vous à l’Espace Pro avec la même méthode que dans
          l’application&nbsp;: <Methods />.
          <Cta href="/pro/connexion?suite=profil">Se connecter à l’Espace Pro</Cta>
        </Step>
        <Step>
          Après la connexion, vous arrivez sur <strong>Profil</strong>. Sinon,
          ouvrez <strong>Profil</strong> dans le menu.
        </Step>
        <Step>
          En bas de la page, dans <strong>Compte</strong>, choisissez{' '}
          <strong>Supprimer mon compte</strong>.
        </Step>
        <Step>
          Tapez <strong>SUPPRIMER</strong>, puis choisissez{' '}
          <strong>Supprimer définitivement</strong>.
        </Step>
      </Ol>
      <P>
        La suppression est immédiate et définitive&nbsp;: vous êtes aussitôt
        déconnecté.
      </P>

      <H2>Dans l’application MyWeli Pro</H2>
      <P>
        Ouvrez <strong>Profil</strong>&nbsp;: l’icône de compte en haut de
        l’<strong>Accueil</strong>, ou l’onglet <strong>Profil</strong>. Puis
        choisissez <strong>Supprimer mon compte</strong> en bas de l’écran.
        Tapez <strong>SUPPRIMER</strong> et confirmez avec{' '}
        <strong>Supprimer définitivement</strong>.
      </P>

      <Callout>
        <P>
          <strong>
            Propriétaire d’un salon&nbsp;? Pensez à exporter vos données avant
          </strong>
          &nbsp;: dans l’application, <strong>Profil → Mes données</strong>
          &nbsp;; sur le web, <strong>Profil → Compte → Exporter (JSON)</strong>.
        </P>
      </Callout>

      <H2>Ce qui est supprimé</H2>
      <Ul>
        <Li>
          votre compte MyWeli Pro&nbsp;: votre nom, votre adresse e-mail et le
          lien avec votre compte Google ou Apple&nbsp;;
        </Li>
        <Li>toutes vos sessions et vos codes de connexion&nbsp;;</Li>
        <Li>votre place dans chaque équipe dont vous faisiez partie&nbsp;;</Li>
        <Li>
          les identifiants de vos appareils —{' '}
          <strong>vos notifications s’arrêtent</strong> — et votre historique de
          notifications&nbsp;;
        </Li>
        <Li>
          si vous utilisiez Apple, l’autorisation de connexion donnée à MyWeli
          Pro&nbsp;: nous demandons à Apple de la révoquer&nbsp;;
        </Li>
        <Li>
          vos pièces d’identité et justificatifs envoyés pour la vérification du
          compte. Leur effacement est fait <strong>au mieux</strong>&nbsp;: si
          notre stockage est indisponible lors de la suppression, ou lorsque vous
          avez remplacé ou renvoyé un document, un fichier peut subsister dans
          notre stockage privé, jamais publié.
        </Li>
      </Ul>

      <H2>Ce que devient votre salon</H2>
      <P>
        Chaque salon dont vous êtes propriétaire est retiré du public en quelques
        minutes&nbsp;: il n’apparaît plus dans les recherches et ne peut plus
        être réservé. Il est <strong>dépublié</strong> plutôt que détruit, pour
        que les réservations, avis et fiches passés continuent de se résoudre.
        Chaque salon garde son nom et son historique&nbsp;; ses numéros de
        téléphone, WhatsApp et Mobile Money, son adresse et son point sur la
        carte sont effacés, et l’acompte est désactivé. Une demande de mise en
        ligne «&nbsp;En cours de validation&nbsp;» est retirée. Les autres
        membres de son équipe gardent leur accès au salon dans MyWeli Pro, selon
        leur rôle. Les salons dont vous êtes seulement membre de l’équipe ne
        changent pas.
      </P>

      <H2>Ce qui est conservé, et combien de temps</H2>
      <Ul>
        <Li>
          l’historique de chaque salon dont vous étiez propriétaire — son nom, sa
          description, ses prestations, ses horaires, son équipe, ses
          rendez-vous, son fichier clients et ses avis — reste dans notre base,
          caché du public, et les membres de son équipe y gardent accès. Aucune
          durée de conservation n’est fixée à ce jour&nbsp;: il n’est pas effacé
          automatiquement&nbsp;;
        </Li>
        <Li>sa commune et sa ville restent avec lui, cachées du public&nbsp;;</Li>
        <Li>
          ses photos (galerie, logo, avant/après, photos de l’équipe) ne sont
          plus affichées au public sur MyWeli (les membres de l’équipe les voient
          toujours dans MyWeli Pro), mais restent accessibles à leur adresse
          existante pour qui la connaît. Aucune durée n’est fixée à ce
          jour&nbsp;;
        </Li>
        <Li>
          le journal des actions de l’équipe garde des identifiants techniques,
          les rôles, la date de chaque action et les recherches faites dans{' '}
          <strong>Clients</strong>, sans votre nom ni votre adresse e-mail.
          Aucune durée n’est fixée à ce jour&nbsp;;
        </Li>
        <Li>
          le journal des décisions de notre équipe sur votre compte et vos
          salons — vérification d’identité acceptée ou refusée, avec le motif
          écrit d’un refus, suspension d’un salon avec son motif. Aucune durée
          n’est fixée à ce jour&nbsp;;
        </Li>
        <Li>
          les e-mails reçus par notre équipe lorsqu’un salon validé a changé
          d’adresse, de téléphone ou de point sur la carte restent dans notre
          messagerie. Aucune durée n’est fixée à ce jour&nbsp;;
        </Li>
        <Li>
          votre fiche de collaborateur dans l’équipe d’un salon dont vous êtes
          seulement membre (nom, photo) appartient à ce salon et reste affichée
          tant qu’il ne la retire pas&nbsp;;
        </Li>
        <Li>
          les invitations qu’un autre salon vous avait envoyées et que vous
          n’aviez pas acceptées restent dans sa liste, avec votre adresse e-mail,
          jusqu’à ce que ce salon les retire&nbsp;;
        </Li>
        <Li>
          les journaux de requêtes de notre hébergeur sont supprimés
          automatiquement au bout de <strong>30 jours</strong>.
        </Li>
      </Ul>

      <H2>Vous ne pouvez plus vous connecter avec Google ou Apple&nbsp;?</H2>
      <P>
        Saisissez l’adresse e-mail de votre compte dans{' '}
        <strong>Votre e-mail</strong>, puis choisissez{' '}
        <strong>Continuer avec e-mail</strong>&nbsp;: nous envoyons un code à 6
        chiffres à cette adresse. Si vous n’avez plus accès à cette adresse,
        écrivez-nous à <Email /> avec le nom de votre salon&nbsp;: nous vous
        répondrons pour vérifier qu’il s’agit bien de votre compte.
      </P>

      <H2>Votre accès à l’équipe d’un salon a été retiré&nbsp;?</H2>
      <P>
        Sans accès à un salon, l’Espace Pro vous déconnecte (ou ne vous montre
        que vos invitations) avant que vous ne puissiez ouvrir{' '}
        <strong>Profil</strong>. Écrivez-nous à <Email /> depuis l’adresse
        e-mail de votre compte&nbsp;: nous vous répondrons pour confirmer la
        suppression.
      </P>

      {/* Each question IS an h2, as on /suppression-compte: the same array
          feeds the JSON-LD, so the two cannot disagree. */}
      {FAQ.map((f) => (
        <div key={f.question}>
          <H2>{f.question}</H2>
          <Answer text={f.answer} />
        </div>
      ))}

      <P>
        Pour le détail de ce que nous traitons et pourquoi, voir la{' '}
        <A href="/politique-confidentialite">politique de confidentialité</A>.
      </P>
    </DocumentPage>
  );
}
