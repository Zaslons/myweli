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
    background_color: '#000000',
    theme_color: '#000000',
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
