import {
  A,
  H2,
  Lead,
  LegalPage,
  Li,
  P,
  Ul,
  legalMetadata,
} from '../../components/legal/LegalPage';

export const metadata = legalMetadata('/politique-confidentialite');

/// Every factual claim here is traceable to the code, not to the docs — the docs
/// were measured wrong in three places while this was written (see
/// docs/design/legal-l1.md §11). In particular: the PRD lists Crashlytics and
/// ~20 analytics events as V1 and **none of it exists**, so this page says the
/// opposite, truthfully.
export default function Page() {
  return (
    <LegalPage slug="/politique-confidentialite">
      <Lead>
        Myweli met en relation des clients et des salons de beauté en Côte
        d’Ivoire. Nous collectons le minimum nécessaire pour prendre et tenir un
        rendez-vous — et nous ne faisons ni publicité, ni profilage, ni analyse
        comportementale.
      </Lead>

      <H2>Ce que nous ne faisons pas</H2>
      <P>
        Cette liste est vérifiable dans notre code, et nous la plaçons en premier
        parce qu’elle répond à la plupart des questions&nbsp;:
      </P>
      <Ul>
        <Li>
          aucun outil de mesure d’audience — pas de Google Analytics, pas de
          PostHog, pas de Mixpanel&nbsp;;
        </Li>
        <Li>aucun rapport de plantage tiers — pas de Sentry, pas de Crashlytics&nbsp;;</Li>
        <Li>aucun SDK publicitaire, aucun traceur, aucun cookie publicitaire&nbsp;;</Li>
        <Li>
          aucun journal applicatif&nbsp;: notre serveur n’enregistre ni votre
          adresse IP, ni votre navigateur, ni le détail de vos requêtes&nbsp;;
        </Li>
        <Li>
          aucune donnée bancaire&nbsp;: Myweli ne détient jamais vos fonds.
          L’acompte se paie directement au salon par Mobile Money.
        </Li>
      </Ul>

      <H2>Les données que nous traitons</H2>
      <P>
        <strong>Votre identité</strong> — nom, téléphone, adresse e-mail, et la
        photo de profil transmise par Google si vous vous connectez ainsi. Elles
        servent à créer et sécuriser votre compte.
      </P>
      <P>
        <strong>Votre connexion</strong> — l’identifiant technique fourni par
        Google ou Apple, et les codes à usage unique — conservés sous forme
        d’empreinte irréversible, jamais en clair, et valables cinq minutes.
      </P>
      <P>
        <strong>Vos rendez-vous</strong> — date, salon, prestations, montants, et
        les notes que vous ajoutez à la réservation.
      </P>
      <P>
        <strong>Votre acompte</strong> — la capture d’écran que vous transmettez
        au salon comme preuve de paiement. Elle est conservée dans un espace privé
        et n’est consultable que par vous, par le salon concerné et, en cas de
        litige, par notre équipe. Cette image peut contenir votre numéro Mobile
        Money&nbsp;: nous ne le collectons pas comme donnée, mais il peut figurer
        dans le fichier que vous envoyez.
      </P>
      <P>
        <strong>Vos avis</strong> — votre nom d’affichage, votre note, votre texte
        et vos photos, publiés sur la page du salon.
      </P>
      <P>
        <strong>Votre fiche chez le salon</strong> — nom, téléphone, historique de
        visites, ainsi que les étiquettes et les notes que le salon rédige à votre
        sujet pour vous suivre d’une visite à l’autre.
      </P>
      <P>
        <strong>Vos notifications</strong> — l’identifiant technique de votre
        appareil et vos préférences, pour vous prévenir d’un rendez-vous.
      </P>
      <P>
        <strong>Nos messages</strong> — le numéro destinataire et le contenu des
        SMS et messages WhatsApp transactionnels que nous envoyons, comme preuve
        d’envoi et pour le support.
      </P>
      <P>
        <strong>Si vous êtes professionnel</strong>, vous nous transmettez en
        outre des pièces d’identité et d’immatriculation. Elles sont stockées dans
        un espace privé et séparé, ne sont jamais publiées, et ne sont
        consultables que par un administrateur Myweli au moyen d’un lien signé
        valable cinq minutes. Chaque consultation est journalisée.
      </P>

      <P>
        <strong>Votre position</strong> — si vous l’autorisez, l’application et le
        site l’utilisent pour centrer la carte et vous proposer les salons
        proches. <strong>Elle ne quitte jamais votre appareil</strong>&nbsp;:
        aucune coordonnée de client ne nous est transmise ni conservée. Vous
        pouvez refuser, ou la retirer à tout moment dans les réglages de votre
        téléphone — la recherche par commune continue de fonctionner. Un
        professionnel qui place le point de son salon nous transmet, lui, cette
        position&nbsp;: elle est publique, puisqu’elle sert à vous y conduire.
      </P>

      <H2>Ce qui est public</H2>
      <P>
        La fiche d’un salon — nom, adresse, téléphone, WhatsApp, coordonnées
        géographiques, photos, équipe, et le numéro Mobile Money servant à
        recevoir les acomptes — est consultable sans compte, y compris par les
        moteurs de recherche. Si vous exercez à domicile, ces informations peuvent
        vous identifier personnellement&nbsp;: n’y publiez que ce que vous
        acceptez de rendre public.
      </P>

      <H2>Où vos données sont hébergées</H2>
      <P>
        Nos serveurs applicatifs et notre base de données sont hébergés par Render
        à <strong>Francfort, en Allemagne</strong>&nbsp;; le site web par
        Vercel&nbsp;; les fichiers — photos, captures d’écran, pièces
        justificatives — par Cloudflare R2, dont les serveurs sont répartis
        mondialement. <strong>Vos données sortent donc de Côte d’Ivoire</strong>
        : la base de données et l’API sont dans l’Union européenne, le site est
        servi depuis les États-Unis, et les fichiers depuis le réseau de
        Cloudflare.
      </P>

      <H2>Qui d’autre les reçoit</H2>
      <P>
        Uniquement des prestataires techniques, chacun pour une fonction
        précise&nbsp;: Twilio (SMS et WhatsApp), Firebase Cloud Messaging
        (notifications), Resend (e-mails), Google et Apple (connexion), et CARTO
        pour les fonds de carte — l’affichage d’une carte transmet votre adresse
        IP à CARTO. <strong>Nous ne vendons ni ne louons aucune donnée.</strong>
      </P>

      <H2>Cookies</H2>
      <P>
        Le site dépose des cookies <strong>strictement nécessaires</strong>, et
        rien d’autre&nbsp;: deux pour une session client, trois pour une session
        professionnelle — jamais les deux à la fois. Ils sont ils sont inaccessibles au JavaScript, transmis uniquement
        en HTTPS, et limités à notre site. Il n’existe aucun cookie de mesure
        d’audience ni de publicité. C’est pourquoi vous ne voyez pas de bandeau de
        consentement&nbsp;: il n’y a rien à consentir. L’application, elle,
        conserve votre session dans le coffre-fort du système d’exploitation.
      </P>

      <H2>Vos droits</H2>
      <P>
        Vous pouvez à tout moment consulter, corriger, exporter ou supprimer vos
        données, sans nous écrire&nbsp;: dans l’application, depuis{' '}
        <strong>Profil → Exporter mes données</strong> et{' '}
        <strong>Profil → Supprimer mon compte</strong>&nbsp;; sur le web, depuis{' '}
        <A href="/mon-compte">Mon compte</A>.
      </P>
      <P>
        La page <A href="/suppression-compte">Supprimer votre compte</A> décrit
        poste par poste ce qui est supprimé, ce qui est anonymisé et ce qui est
        conservé — parce qu’une suppression décrite en une phrase serait
        inexacte. Une seule condition&nbsp;: annulez vos rendez-vous à venir
        avant, pour ne pas laisser un salon avec un créneau qu’il ne peut plus
        vous attribuer.
      </P>

      <H2>Conservation</H2>
      <P>
        Nous conservons vos données tant que votre compte existe. Certaines
        informations survivent volontairement à sa suppression — le journal
        d’envoi de nos messages, indexé par numéro de téléphone&nbsp;; votre
        éventuelle opposition à être recontacté, précisément pour qu’elle
        continue de vous protéger&nbsp;; et les étiquettes et notes qu’un salon a
        rédigées sur sa fiche client, qui lui appartiennent et restent attachées
        à une fiche désormais anonyme. La page ci-dessus les énumère.
      </P>

      <H2>Nous contacter</H2>
      <P>
        Pour toute question sur vos données, écrivez-nous depuis{' '}
        <strong>Profil → Aide &amp; Support</strong> dans l’application. Les
        coordonnées de l’éditeur figurent dans les{' '}
        <A href="/mentions-legales">mentions légales</A>.
      </P>
    </LegalPage>
  );
}
