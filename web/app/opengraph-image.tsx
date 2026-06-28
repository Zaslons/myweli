import { ImageResponse } from 'next/og';

// Site-wide social share card (og:image + twitter:image). On-brand monochrome.
// Next statically generates this at build; per-route images can override later.
export const alt = 'Myweli — Réservation beauté & bien-être en Côte d’Ivoire';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'flex-start',
          justifyContent: 'center',
          background: '#000000',
          color: '#FFFFFF',
          padding: '80px',
        }}
      >
        <div style={{ fontSize: 130, fontWeight: 700, letterSpacing: '-4px' }}>
          Myweli
        </div>
        <div style={{ display: 'flex', fontSize: 46, marginTop: 24, color: '#E5E5E5' }}>
          Réservation beauté &amp; bien-être en Côte d’Ivoire
        </div>
        <div style={{ display: 'flex', fontSize: 30, marginTop: 18, color: '#9A9A9A' }}>
          Coiffure · Barbier · Onglerie · Spa — réservez en ligne, 24/7
        </div>
      </div>
    ),
    { ...size },
  );
}
