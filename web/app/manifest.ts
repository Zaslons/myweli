import type { MetadataRoute } from 'next';

/// PWA web manifest (served at /manifest.webmanifest). Brand icons from the
/// launch-asset kit; monochrome theme matches the app tokens.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'MyWeli',
    short_name: 'MyWeli',
    description: 'Réservation beauté & bien-être en Côte d’Ivoire',
    start_url: '/',
    display: 'standalone',
    // The splash background is the scaffold `background` — NOT brand black, which
    // made the installed PWA flash black before revealing a near-white app.
    background_color: '#F6F7F9',
    theme_color: '#000000', // status-bar tint = brand black (correct)
    icons: [
      { src: '/android-chrome-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/android-chrome-512.png', sizes: '512x512', type: 'image/png' },
      {
        src: '/maskable-192.png',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'maskable',
      },
      {
        src: '/maskable-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
  };
}
