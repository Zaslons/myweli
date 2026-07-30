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

export const metadata = legalMetadata('/cgu');

/// The document three app screens have referenced since they shipped, in dead
/// unlinked text, while it did not exist (docs/design/legal-l1.md §1).
///
/// The single most load-bearing sentence here is the first one: **Myweli is an
/// intermediary.** The salon provides the service and sets its own deposit and
/// cancellation policy; we never hold funds. Everything else follows from that,
/// and it is also what makes the deposit model defensible — see
/// `docs/design/deposit-*.md` and PRD §18.
export default function Page() {
  return (
    <LegalPage slug="/cgu">
      <Lead>
        Myweli est un service de mise en relation. Nous vous aidons à trouver un
        salon et à réserver&nbsp;; la prestation, elle, est fournie par le salon,
        qui en est seul responsable.
      </Lead>

      <H2>1. Objet</H2>
      <P>
        Les présentes conditions régissent l’utilisation de l’application et du
        site Myweli, qui mettent en relation des clients et des professionnels de
        la beauté et du bien-être en Côte d’Ivoire. En créant un compte ou en
        confirmant une réservation, vous les acceptez.
      </P>

      <H2>2. Notre rôle, et ses limites</H2>
      <P>
        Myweli fournit l’outil de découverte et de réservation. Nous ne sommes ni
        le prestataire, ni l’employeur du salon, ni partie au contrat conclu entre
        vous et lui. Le salon fixe ses prestations, ses prix, ses horaires, sa
        politique d’acompte et sa politique d’annulation, et répond de la qualité
        de ce qu’il exécute.
      </P>

      <H2>3. Votre compte</H2>
      <P>
        Vous devez avoir la capacité juridique de contracter. Les informations que
        vous fournissez doivent être exactes, et vous êtes responsable de l’usage
        fait de votre compte. Vous pouvez le supprimer à tout moment —{' '}
        <A href="/suppression-compte">voici comment, et ce que cela efface</A>.
      </P>

      <H2>4. Réservations et acomptes</H2>
      <P>
        Une réservation vous engage envers le salon. Lorsque le salon demande un
        acompte, <strong>vous le payez directement au salon</strong> par Mobile
        Money et transmettez la capture d’écran comme preuve&nbsp;:{' '}
        <strong>Myweli n’encaisse, ne détient et ne rembourse aucun fonds</strong>,
        et n’est pas partie au paiement.
      </P>
      <P>
        Toute contestation portant sur un acompte — versement, remboursement,
        montant — se règle donc avec le salon. Nous pouvons vous aider à les
        joindre et, en cas de litige signalé, consulter la preuve transmise&nbsp;;
        nous ne pouvons pas procéder à un remboursement.
      </P>

      <H2>5. Annulation et absence</H2>
      <P>
        Les conditions d’annulation et le délai applicable sont ceux affichés par
        le salon au moment de la réservation. Une absence répétée sans prévenir
        peut conduire un salon à refuser vos réservations ultérieures.
      </P>

      <H2>6. Avis</H2>
      <P>
        Vous ne pouvez déposer un avis qu’après une prestation réellement
        effectuée. Un avis doit être sincère et ne contenir ni propos injurieux,
        ni contenu illicite, ni donnée personnelle concernant un tiers. Nous
        pouvons masquer un avis signalé qui contrevient à ces règles.
      </P>
      <P>
        Si vous supprimez votre compte, vos avis restent publiés{' '}
        <strong>sans votre nom</strong> — la note appartient à l’évaluation du
        salon, qui l’a méritée.
      </P>

      <H2>7. Pour les professionnels</H2>
      <Ul>
        <Li>
          vous garantissez être habilité à exercer et à publier les informations
          de votre établissement&nbsp;;
        </Li>
        <Li>
          les pièces d’identité et d’immatriculation que vous transmettez servent
          uniquement à vérifier votre compte&nbsp;;
        </Li>
        <Li>
          vous êtes responsable de l’exactitude de vos prestations, prix,
          disponibilités et politiques affichées&nbsp;;
        </Li>
        <Li>
          les données de vos clients accessibles via Myweli ne peuvent servir
          qu’à la relation avec eux, et jamais être cédées.
        </Li>
      </Ul>

      <H2>8. Disponibilité</H2>
      <P>
        Nous faisons notre possible pour que le service soit disponible, sans le
        garantir sans interruption&nbsp;: maintenance, panne d’un prestataire
        technique ou coupure réseau peuvent l’affecter.
      </P>

      <H2>9. Responsabilité</H2>
      <P>
        Notre responsabilité ne peut être engagée pour l’exécution de la
        prestation par le salon, pour un paiement effectué en dehors du service,
        ni pour un dommage résultant d’informations inexactes fournies par un
        utilisateur ou un salon.
      </P>

      <H2>10. Résiliation</H2>
      <P>
        Vous pouvez cesser d’utiliser Myweli et supprimer votre compte à tout
        moment. Nous pouvons suspendre ou fermer un compte en cas de manquement
        aux présentes conditions ou d’usage frauduleux.
      </P>

      <H2>11. Données personnelles</H2>
      <P>
        Le traitement de vos données est décrit dans la{' '}
        <A href="/politique-confidentialite">politique de confidentialité</A>,
        qui fait partie intégrante des présentes conditions.
      </P>

      <H2>12. Droit applicable</H2>
      <P>
        Les présentes conditions sont soumises au droit ivoirien. L’identité de
        l’éditeur figure dans les{' '}
        <A href="/mentions-legales">mentions légales</A>.
      </P>
    </LegalPage>
  );
}
