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
import { COMPANY } from '../../lib/legal';

export const metadata = legalMetadata('/mentions-legales');

/// **This page is deliberately incomplete, and says so.**
///
/// MyWeli is not registered yet (owner decision, docs/design/legal-l1.md §12),
/// so the RCCM, the siège social, the capital and the legal representative do not
/// exist to publish. The choice was between leaving blanks — which read as an
/// oversight — and stating the situation. It states it, and `COMPANY` in
/// `lib/legal.ts` is the one edit that completes it at registration.
export default function Page() {
  return (
    <LegalPage slug="/mentions-legales">
      <Lead>
        Informations sur l’éditeur du service MyWeli, sur son hébergement, et sur
        la propriété des contenus qui y sont publiés.
      </Lead>

      <H2>Éditeur</H2>
      <P>
        <strong>{COMPANY.tradingName}</strong> — {COMPANY.registration}.
      </P>

      <Callout>
        <P>
          <strong>Immatriculation en cours.</strong> Les mentions suivantes seront
          publiées ici dès que l’immatriculation sera effective&nbsp;:{' '}
          {COMPANY.pendingFacts.join(', ')}. Nous préférons le dire plutôt que
          laisser des champs vides.
        </P>
      </Callout>

      <H2>Directeur de la publication</H2>
      <P>
        Le représentant légal de {COMPANY.tradingName}, dont l’identité sera
        publiée avec les mentions d’immatriculation ci-dessus.
      </P>

      <H2>Nous contacter</H2>
      <P>
        Depuis l’application, <strong>Profil → Aide &amp; Support</strong> ouvre
        une conversation avec notre équipe. C’est aujourd’hui le canal de contact
        de référence&nbsp;: l’adresse d’expédition de nos e-mails automatiques
        n’est pas relevée.
      </P>

      <H2>Hébergement</H2>
      <P>
        Le service s’appuie sur trois hébergeurs, dans deux juridictions&nbsp;:
      </P>
      <Ul>
        {COMPANY.hosts.map((h) => (
          <Li key={h}>{h}</Li>
        ))}
      </Ul>
      <P>
        Les conséquences de cet hébergement sur vos données — et notamment le
        transfert hors de Côte d’Ivoire — sont décrites dans la{' '}
        <A href="/politique-confidentialite">politique de confidentialité</A>.
      </P>

      <H2>Propriété intellectuelle</H2>
      <P>
        La marque MyWeli, son logo, l’interface et les contenus éditoriaux du
        service sont protégés. Les contenus publiés par un salon — textes,
        photographies, prestations — restent la propriété de ce salon, qui nous
        autorise à les afficher dans le cadre du service.
      </P>
      <P>
        Les fonds de carte sont fournis par CARTO à partir des données
        OpenStreetMap, sous leurs licences respectives.
      </P>

      <H2>Signaler un contenu</H2>
      <P>
        Un avis ou une fiche qui vous semble illicite peut être signalé depuis la
        page concernée. Les conditions d’utilisation sont détaillées dans les{' '}
        <A href="/cgu">CGU</A>.
      </P>
    </LegalPage>
  );
}
