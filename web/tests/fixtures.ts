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
  // The REAL wire shape (2024-01-01 carrier date + isAvailable) — a bare
  // '09:00' fixture is how the raw-ISO Hours render stayed green. Monday is
  // a split day, Tuesday holds an UNAVAILABLE slot, the rest are closed.
  availability: {
    providerId: 'p1',
    weeklySchedule: {
      '0': [
        {
          startTime: '2024-01-01T09:00:00.000Z',
          endTime: '2024-01-01T12:00:00.000Z',
          isAvailable: true,
        },
        {
          startTime: '2024-01-01T14:00:00.000Z',
          endTime: '2024-01-01T18:00:00.000Z',
          isAvailable: true,
        },
      ],
      '1': [
        {
          startTime: '2024-01-01T09:00:00.000Z',
          endTime: '2024-01-01T18:00:00.000Z',
          isAvailable: false,
        },
      ],
    },
    blockedDates: [],
    bufferMinutes: 0,
    bookingHorizonDays: 365,
    minimumNoticeMinutes: 60,
  },
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
