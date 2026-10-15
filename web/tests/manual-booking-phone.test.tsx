import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { ManualBookingDialog } from '../components/pro/ManualBookingDialog';
import type { ProProfile } from '../lib/api/pro';

/// The manual-booking PHONE boundary (plan « fix/manual-booking-phone »).
///
/// Every earlier test fed a pre-formed E.164 string to a helper or the API
/// client, so the actual defect — the dialog sending raw field text that the
/// backend refuses as `invalid_phone`, surfaced as « Création impossible.
/// Réessayez. » — was invisible to 700+ green tests. These cross the REAL
/// form boundary: what a receptionist types is what must become E.164.
const PROFILE = {
  account: { id: 'acc-1', email: 'x@salon.test' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [
      {
        id: 's1',
        name: 'Tresses',
        description: '',
        price: 15000,
        durationMinutes: 120,
        providerId: 'p1',
        active: true,
      },
    ],
  },
} as unknown as ProProfile;

/// Every POST /api/pro/appointments body, in order.
const posted: Record<string, unknown>[] = [];

function mockFetch({
  createStatus = 200,
  createBody = '{}',
  clients = [] as Record<string, unknown>[],
} = {}) {
  posted.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (String(url).startsWith('/api/pro/clients')) {
        return new Response(JSON.stringify({ items: clients }), { status: 200 });
      }
      if (url === '/api/pro/appointments') {
        posted.push(JSON.parse(String(init?.body ?? '{}')));
        return new Response(createBody, { status: createStatus });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

function renderDialog(initialClient?: {
  id: string;
  name: string;
  phone?: string;
}) {
  const onCreated = vi.fn();
  render(
    <ManualBookingDialog
      providerId="p1"
      profile={PROFILE}
      dateTimeIso="2027-01-15T14:30:00.000Z"
      initialClient={initialClient}
      onClose={() => {}}
      onCreated={onCreated}
    />,
  );
  return onCreated;
}

/// Name the client (reveals the new-client phone field), pick the service.
function fillBasics() {
  fireEvent.change(
    screen.getByLabelText('Rechercher ou nommer le client'),
    { target: { value: 'Awa' } },
  );
  fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('ManualBookingDialog — the phone crosses as E.164', () => {
  it('the field\'s E.164 output IS the payload — raw text never crosses', async () => {
    // The login-options idiom: in international mode jsdom fires the full
    // value (live, the field shows +225 and the user types the national
    // digits after it — libphonenumber keeps CI's trunk 0 either way).
    mockFetch();
    const onCreated = renderDialog();
    fillBasics();

    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '+2250708091011' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientPhone).toBe('+2250708091011');
    await waitFor(() => expect(onCreated).toHaveBeenCalled());
  });

  it('an impossible number is refused AT THE FIELD — nothing is sent', async () => {
    mockFetch();
    renderDialog();
    fillBasics();

    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '12' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await screen.findByText('Saisissez un numéro de téléphone valide.');
    expect(posted).toHaveLength(0);
  });

  it('a +225 number short of 10 digits says how many — nothing is sent', async () => {
    // docs/design/phone-national-length.md: 7 digits after +225 is the number
    // the app accepted on 2026-10-15. The message says what to do (§14 rule 4).
    mockFetch();
    renderDialog();
    fillBasics();

    const field = screen.getByLabelText('Téléphone (pour retrouver ce client)');
    fireEvent.change(field, { target: { value: '+2250700000' } });
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await screen.findByText('Le numéro doit comporter 10 chiffres après +225.');
    expect(field).toHaveAttribute('aria-invalid', 'true');
    expect(posted).toHaveLength(0);
  });

  it("a server invalid_phone names the fault — never « Création impossible »", async () => {
    // Defence in depth: if a bypass ever reaches the server, the 400 must
    // name the field, not invite a retry that cannot succeed.
    mockFetch({
      createStatus: 400,
      createBody: JSON.stringify({ error: 'invalid_phone' }),
    });
    renderDialog();
    fillBasics();
    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '+2250708091011' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await screen.findByText(
      'Numéro invalide (format international, ex. +2250700000000).',
    );
    expect(screen.queryByText(/Création impossible/)).toBeNull();
  });
});

/// docs/design/phone-leftovers.md §7 — a PICKED client's number is shown, not
/// editable here, and crosses as stored. A short number stored before the
/// national-length rule earns the server's `invalid_phone`, and the sentence
/// above (« format international ») sends the salon looking for a field this
/// dialog does not have. The fault is on the client's card: say so, lead there.
describe('ManualBookingDialog — a picked client whose stored number is refused', () => {
  const STALE = 'Le numéro enregistré sur la fiche de ce client est invalide.';
  const REFUSED = {
    createStatus: 400,
    createBody: JSON.stringify({ error: 'invalid_phone' }),
  };

  it('pre-picked (the client card entry): names the card and links to it', async () => {
    mockFetch(REFUSED);
    renderDialog({ id: 'sc1', name: 'Koffi', phone: '+22507000001' });
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      /^Le numéro enregistré sur la fiche de ce client est invalide\.$/,
    );
    expect(screen.getByRole('link', { name: 'Ouvrir la fiche' })).toHaveAttribute(
      'href',
      '/pro/clients/sc1',
    );
    // Not the new-client sentence: there is no field here to fix.
    expect(screen.queryByText(/format international/)).toBeNull();
    // The stored number crossed as stored — it is how the server finds them.
    expect(posted[0].clientPhone).toBe('+22507000001');
  });

  it('picked from the search: the same sentence, the link to THAT client', async () => {
    mockFetch({
      ...REFUSED,
      clients: [
        {
          id: 'sc7',
          displayName: 'Awa Koné',
          phone: '+22507000007',
          tags: [],
          visits: 1,
          noShows: 0,
        },
      ],
    });
    renderDialog();
    fireEvent.change(screen.getByLabelText('Rechercher ou nommer le client'), {
      target: { value: 'Awa' },
    });
    fireEvent.click(await screen.findByRole('button', { name: /Awa Koné/ }));
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(STALE);
    expect(screen.getByRole('link', { name: 'Ouvrir la fiche' })).toHaveAttribute(
      'href',
      '/pro/clients/sc7',
    );
  });

  it('« Changer » drops the sentence with the client it was about', async () => {
    mockFetch(REFUSED);
    renderDialog({ id: 'sc1', name: 'Koffi', phone: '+22507000001' });
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));
    await screen.findByText(STALE);

    fireEvent.click(screen.getByRole('button', { name: 'Changer' }));
    expect(screen.queryByText(STALE)).toBeNull();
    expect(screen.queryByRole('link', { name: 'Ouvrir la fiche' })).toBeNull();
  });

  it('another refusal for a picked client keeps its own sentence — no link', async () => {
    mockFetch({
      createStatus: 409,
      createBody: JSON.stringify({ error: 'slot_unavailable' }),
    });
    renderDialog({ id: 'sc1', name: 'Koffi', phone: '+2250700000001' });
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await screen.findByText('Ce créneau est déjà pris.');
    expect(screen.queryByRole('link', { name: 'Ouvrir la fiche' })).toBeNull();
  });
});

/// The SMS promise is gone (docs/design/amounts-that-fit.md §2 « Web »; the
/// app's twin guard is `mobile/test/widget/manual_booking_phone_test.dart`).
///
/// The dialog used to offer « Envoyer la confirmation par SMS », ticked by
/// default, under « Le client reçoit un lien vers l’app (bientôt disponible) »,
/// and posted `sendSmsInvite: true` whenever a phone was present — a message
/// nothing sends: the backend never reads the field, and messaging waits for
/// company registration. The app hid its switch in build 569 and sends `false`;
/// the web has no flag mechanism, so the control is removed outright and the
/// field is sent `false`, explicitly.
///
/// `toBe(false)` and not `not.toBe(true)`: an omitted field is `undefined`, and
/// « the form sends false » is what the app does and what is asserted here.
describe('ManualBookingDialog — no SMS promise, and sendSmsInvite is false', () => {
  /// The three things a person could read or tick. Each is asserted on its own
  /// line so a regression names what came back.
  function expectNoSmsControl() {
    expect(screen.queryByText('Envoyer la confirmation par SMS')).toBeNull();
    expect(screen.queryByText(/bientôt disponible/)).toBeNull();
    expect(screen.queryByText(/SMS/)).toBeNull();
    // The only checkboxes left are the service rows (one service here).
    expect(screen.getAllByRole('checkbox')).toHaveLength(1);
  }

  it('shows no SMS control and no « bientôt disponible » — no phone yet', () => {
    // Without a phone the old control was rendered dimmed and disabled.
    mockFetch();
    renderDialog();
    expectNoSmsControl();
  });

  it('shows no SMS control — a pre-picked client who has a phone', () => {
    // With a phone the old control was ENABLED and ticked: the state a
    // receptionist opening the dialog from a client card saw every time.
    mockFetch();
    renderDialog({ id: 'sc1', name: 'Koffi', phone: '+2250700000001' });
    expectNoSmsControl();
  });

  it('a phone typed for a new client sends sendSmsInvite false', async () => {
    mockFetch();
    const onCreated = renderDialog();
    fillBasics();
    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '+2250708091011' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientPhone).toBe('+2250708091011');
    expect(posted[0].sendSmsInvite).toBe(false);
    await waitFor(() => expect(onCreated).toHaveBeenCalled());
  });

  it('a pre-picked client who has a phone sends sendSmsInvite false', async () => {
    // The client-card entry point (`ClientCardClient` → `initialClient`): the
    // phone is known from the first render, so this is the path on which every
    // booking carried `true`.
    mockFetch();
    const onCreated = renderDialog({
      id: 'sc1',
      name: 'Koffi',
      phone: '+2250700000001',
    });
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    // The stored number still crosses raw — it is how the server finds the
    // client again.
    expect(posted[0].clientName).toBe('Koffi');
    expect(posted[0].clientPhone).toBe('+2250700000001');
    expect(posted[0].sendSmsInvite).toBe(false);
    await waitFor(() => expect(onCreated).toHaveBeenCalled());
  });

  it('a client with no phone sends sendSmsInvite false too — never omitted', async () => {
    mockFetch();
    renderDialog();
    fillBasics();
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientPhone).toBeUndefined();
    expect(posted[0].sendSmsInvite).toBe(false);
  });
});
