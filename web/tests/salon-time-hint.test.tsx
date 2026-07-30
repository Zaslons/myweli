import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { SalonTimeHint } from '../components/SalonTimeHint';

/// The « heure du salon » viewer hint (docs/design/timezone-salon-time.md §2):
/// visible ONLY when the device offset differs from the salon's (UTC+0) —
/// visitors in Côte d'Ivoire never see it. Offsets are injected so the suite
/// is deterministic on any machine TZ.

const COPY = /Heures affichées : heure du salon \(Côte d’Ivoire\)/;

afterEach(cleanup);

describe('SalonTimeHint', () => {
  it('a foreign device sees the hint', () => {
    render(
      <SalonTimeHint date="2026-07-13T10:00:00.000Z" deviceOffsetMin={60} />,
    );
    expect(screen.getByText(COPY)).toBeTruthy();
  });

  it('a device on salon time sees NOTHING', () => {
    render(
      <SalonTimeHint date="2026-07-13T10:00:00.000Z" deviceOffsetMin={0} />,
    );
    expect(screen.queryByText(COPY)).toBeNull();
  });

  it('a per-salon tz drives the predicate; the country label is dynamic (MP3)', () => {
    // The device sits at UTC+0 — that IS Abidjan time, but NOT Libreville's.
    render(
      <SalonTimeHint
        date="2026-07-13T10:00:00.000Z"
        tz="Africa/Libreville"
        countryLabel="Gabon"
        deviceOffsetMin={0}
      />,
    );
    expect(
      screen.getByText(/Heures affichées : heure du salon \(Gabon\)/),
    ).toBeTruthy();
  });

  it('a device on the SALON zone offset sees nothing, even abroad (MP3)', () => {
    render(
      <SalonTimeHint
        date="2026-07-13T10:00:00.000Z"
        tz="Africa/Libreville"
        countryLabel="Gabon"
        deviceOffsetMin={60}
      />,
    );
    expect(screen.queryByText(/heure du salon/)).toBeNull();
  });
});
