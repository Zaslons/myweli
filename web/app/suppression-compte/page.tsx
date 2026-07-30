import {
  A,
  Callout,
  H2,
  Lead,
  LegalPage,
  Li,
  P,
  Ul,
  legalMetadata,
} from '../../components/legal/LegalPage';
import { faqJsonLd } from '../../lib/seo/jsonld';

export const metadata = legalMetadata('/suppression-compte');

/// The page Google Play takes as a submission field, and the one a store
/// reviewer actually opens.
///
/// **Its three sections are a transcription of the backend**, not a summary of
/// it: `openapi.yaml`'s `/me` `delete:` description and
/// `docs/design/account-deletion-erasure.md` §4 carry the same table. Three
/// surfaces, one set of promises — and a page that listed only what is deleted
/// would be describing an erasure the code does not perform.
///
/// The FAQ is rendered as headings and paragraphs from the same array that feeds
/// the JSON-LD, deliberately **not** through `components/provider/Faq.tsx`: its
/// `<summary>` is `py-s` with no min-height (≈35px), under §13.2's 48px floor —
/// a survivor of WEB-SYSTEM §15 row 7h, filed rather than inherited.
const FAQ = [
  {
    question: 'Comment supprimer mon compte Myweli ?',
    answer:
      'Annulez d’abord vos rendez-vous à venir, puis : dans l’application, ' +
      'Profil → Supprimer mon compte et saisissez SUPPRIMER pour confirmer ; ' +
      'sur le web, Mon compte → Supprimer mon compte. La suppression est ' +
      'ensuite immédiate et définitive.',
  },
  {
    question: 'Pourquoi dois-je annuler mes rendez-vous avant ?',
    answer:
      'Parce qu’un salon vous garde un créneau. Un compte qui disparaît sans ' +
      'prévenir lui laisse une réservation qu’il ne peut ni joindre ni ' +
      'remplacer. C’est la même règle pour les comptes professionnels.',
  },
  {
    question: 'Que devient l’historique de mes rendez-vous ?',
    answer:
      'Le rendez-vous reste dans le livre du salon, mais votre nom, votre ' +
      'téléphone et vos notes en sont retirés. Le salon garde une trace ' +
      'comptable de la prestation, sans vous identifier.',
  },
  {
    question: 'Mes avis sont-ils supprimés ?',
    answer:
      'Non : ils sont anonymisés. La note appartient à l’évaluation du salon, ' +
      'qui l’a méritée — la retirer modifierait injustement sa réputation. ' +
      'Votre nom, lui, disparaît.',
  },
  {
    question: 'Puis-je supprimer mon compte sans installer l’application ?',
    answer:
      'Oui. Connectez-vous sur myweli.com, ouvrez Mon compte, et utilisez ' +
      'Supprimer mon compte en bas de la page.',
  },
];

export default function Page() {
  return (
    <LegalPage slug="/suppression-compte" extraJsonLd={faqJsonLd(FAQ)}>
      <Lead>
        Vous pouvez supprimer votre compte Myweli vous-même, à tout moment, sans
        nous écrire. Voici comment — et exactement ce que cela efface.
      </Lead>

      <Callout>
        <P>
          <strong>Annulez d’abord vos rendez-vous à venir.</strong> Tant qu’un
          rendez-vous confirmé ou en attente est devant vous, la suppression est
          refusée&nbsp;: un salon vous garde un créneau, et un compte qui
          disparaît sans prévenir lui laisse une réservation qu’il ne peut ni
          joindre ni remplacer. Annulez depuis <strong>Mes rendez-vous</strong>,
          puis revenez ici.
        </P>
      </Callout>

      <H2>Comment faire</H2>
      <P>
        <strong>Dans l’application</strong> — ouvrez <strong>Profil</strong>, puis{' '}
        <strong>Supprimer mon compte</strong>, et saisissez{' '}
        <strong>SUPPRIMER</strong> pour confirmer.
      </P>
      <P>
        <strong>Sur le web</strong> — connectez-vous, ouvrez{' '}
        <A href="/mon-compte">Mon compte</A>, et utilisez{' '}
        <strong>Supprimer mon compte</strong> en bas de la page.
      </P>

      <Callout>
        <P>
          <strong>Avant de supprimer, pensez à exporter vos données.</strong>{' '}
          Depuis <strong>Profil → Exporter mes données</strong> dans l’application, ou{' '}
          <A href="/mon-compte/donnees">Mes données</A> sur le web. La suppression
          est définitive et nous ne pouvons rien restaurer.
        </P>
      </Callout>

      <H2>Ce qui est supprimé</H2>
      <Ul>
        <Li>votre profil et vos identifiants de connexion&nbsp;;</Li>
        <Li>vos favoris&nbsp;;</Li>
        <Li>
          vos préférences et votre historique de notifications&nbsp;;
        </Li>
        <Li>
          les identifiants de vos appareils —{' '}
          <strong>vos notifications s’arrêtent</strong>&nbsp;;
        </Li>
        <Li>les signalements d’avis que vous avez déposés&nbsp;;</Li>
        <Li>vos codes de connexion et toutes vos sessions&nbsp;;</Li>
        <Li>
          les photos que vous aviez jointes à vos avis — leur adresse contenait
          votre identifiant&nbsp;;
        </Li>
        <Li>
          les captures d’écran d’acompte que vous aviez transmises. Ces deux
          effacements de fichiers sont effectués <strong>au mieux</strong>&nbsp;:
          si notre stockage est indisponible à cet instant précis, la suppression
          de votre compte aboutit quand même, et un fichier peut subsister.
        </Li>
      </Ul>

      <H2>Ce qui est anonymisé</H2>
      <P>
        Certaines traces ne vous appartiennent pas seules&nbsp;: les effacer
        retirerait quelque chose à un tiers. Elles restent, sans vous.
      </P>
      <Ul>
        <Li>
          <strong>Vos avis</strong> restent en ligne sans votre nom, et sans les
          photos que vous y aviez jointes. La note appartient à l’évaluation d’un
          salon, qui l’a méritée&nbsp;: la retirer modifierait sa réputation
          parce que vous avez fermé un compte. Les photos, elles, sont les
          vôtres.
        </Li>
        <Li>
          <strong>Vos rendez-vous</strong> perdent votre nom, votre téléphone et
          vos notes. Le salon conserve la trace comptable de la prestation.
        </Li>
        <Li>
          <strong>Votre fiche client</strong> chez chaque salon est déliée de
          votre compte, et son nom et son téléphone sont effacés.
        </Li>
      </Ul>

      <H2>Ce qui est conservé, et pourquoi</H2>
      <Ul>
        <Li>
          <strong>Le journal d’envoi</strong> de nos SMS et messages WhatsApp
          transactionnels. Il est indexé par numéro de téléphone et non par
          compte&nbsp;; les numéros étant réattribués, l’effacer par compte
          reviendrait à effacer l’historique de quelqu’un d’autre.
        </Li>
        <Li>
          <strong>Votre opposition à être recontacté</strong>, si vous en aviez
          exprimé une — précisément pour qu’elle continue de vous protéger après
          la suppression. L’effacer vous rendrait à nouveau contactable.
        </Li>
        <Li>
          <strong>Les étiquettes et notes qu’un salon a écrites</strong> sur sa
          fiche client. Elles lui appartiennent — c’est son carnet — et restent
          attachées à une fiche désormais anonyme, sans votre nom ni votre
          téléphone.
        </Li>
      </Ul>

      <H2>Si vous êtes professionnel</H2>
      <P>
        La même règle s’applique, dans l’autre sens&nbsp;: terminez ou annulez
        d’abord vos rendez-vous à venir — nous ne voulons pas annuler d’office
        les réservations de vos clients. Vos salons sont ensuite{' '}
        <strong>dépubliés</strong> plutôt que détruits, pour que les
        réservations, avis et fiches passés continuent de se résoudre, et vos
        pièces d’identité sont effacées.
      </P>

      {/* Each question IS an h2 — no « Questions fréquentes » wrapper heading
          above them, which would put an h2 under an h2 and read as a section
          containing sections. `LegalPage` exports no H3 on purpose: a legal
          document that needs one needs shorter sections instead. */}
      {FAQ.map((f) => (
        <div key={f.question}>
          <H2>{f.question}</H2>
          <P>{f.answer}</P>
        </div>
      ))}

      <P>
        Pour le détail de ce que nous traitons et pourquoi, voir la{' '}
        <A href="/politique-confidentialite">politique de confidentialité</A>.
      </P>
    </LegalPage>
  );
}
