import type { Provider } from '../lib/api/providers';

/// A representative provider for tests.
export const providerFixture: Provider = {
  id: 'p1',
  slug: 'beaute-divine',
  name: 'Beauté Divine',
  description: 'Salon de coiffure à Cocody.',
  address: 'Rue des Jardins, Cocody',
  city: 'Abidjan',
  commune: 'Cocody',
  latitude: 5.35,
  longitude: -3.99,
  imageUrls: ['https://cdn.example/hero.jpg'],
  rating: 4.8,
  reviewCount: 12,
  phoneNumber: '+2250700000000',
  whatsapp: '+2250700000000',
  category: 'salon',
  services: [
    {
      id: 's1',
      name: 'Tresses',
      description: '',
      price: 15000,
      priceMax: 25000,
      durationMinutes: 120,
      providerId: 'p1',
      active: true,
    },
  ],
  reviews: [
    {
      id: 'r1',
      providerId: 'p1',
      userId: 'u1',
      userName: 'Awa',
      rating: 5,
      text: 'Service impeccable.',
      createdAt: '2026-06-01T10:00:00.000Z',
    },
  ],
};
