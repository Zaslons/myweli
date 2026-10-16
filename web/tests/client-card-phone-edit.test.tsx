import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the card's load callback depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ClientCardClient } from '../components/pro/ClientCardClient';
import type { SalonClientCard } from '../lib/pro/clients';

/// « Modifier le numéro d'une fiche client » on the web Pro card
/// (docs/design/phone-leftovers.md §8, decided 2026-10-15): a GUEST card's
/// number is edited in a `Modal` with the shared `PhoneField`; the history
/// follows the number server-side, so a saved number reloads the whole card
/// (visits included). A card LINKED to an account keeps the account's number,
/// read-only. A number already on another card is refused with a way to it.
///
/// What crosses is `PATCH /api/pro/clients/{id}` with `{ providerId, phone }`
/// — the number normalized (separators stripped), never the tags.

const GUEST: SalonClientCard = {
  id: 'sc1',
  displayName: 'Koffi',
  phone: '+2250700000101',
  tags: ['VIP'],
  lastVisitAt: null,
  linked: false,
  // The server's word that its PATCH takes a number for this card: not
  // linked, and a number to change (docs/design/phone-leftovers.md §11).
  phoneEditable: true,
  createdAt: '2026-10-01T09:00:00.000Z',
  stats: { visits: 3, spentFcfa: 45000, noShows: 0, cancellations: 0 },
  notes: [],
};

/// The same guest card read from a server older than the number edit: it
/// says nothing of `phoneEditable`, and its PATCH answers `invalid_tags` to a
/// body that is only `{ phone }` — a « Modifier » there could never succeed.
const { phoneEditable: _absent, ...OLD_SERVER_GUEST } = GUEST;

/// The card that already holds a number — the 409 `client_exists` points here.
const OTHER: SalonClientCard = { ...GUEST, id: 'sc7', displayName: 'Awa', phone: '+2250707123456' };

type Patch = { status: number; body: Record<string, unknown> };

const patched: Record<string, unknown>[] = [];
const cardReads: string[] = [];
const visitReads: string[] = [];
/// The audited reads of the OTHER card (the one a `client_exists` names).
const otherReads: string[] = [];

/// `patch`: what PATCH /api/pro/clients/sc1 answers. On a 200 the card the
/// server holds takes the sent number — so a reload shows it. On a 409
/// `client_linked` the card IS linked now (an account claimed it between the
/// read and the save) — so a reload shows it read-only. `hold`: the PATCH
/// answers only once it settles (a save still in flight).
function mockFetch(
  initial: SalonClientCard,
  patch: Patch = { status: 200, body: {} },
  hold?: Promise<unknown>,
) {
  patched.length = 0;
  cardReads.length = 0;
  visitReads.length = 0;
  otherReads.length = 0;
  let card = initial;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              timezone: 'Africa/Abidjan',
              currency: 'XOF',
            },
          }),
          { status: 200 },
        );
      }
      if (u === `/api/pro/clients/${card.id}` && init?.method === 'PATCH') {
        const b = JSON.parse(String(init.body ?? '{}'));
        patched.push(b);
        if (hold) await hold;
        if (patch.status === 200) card = { ...card, phone: b.phone };
        if (patch.body.error === 'client_linked') {
          card = { ...card, linked: true, phoneEditable: false };
        }
        return new Response(
          JSON.stringify(patch.status === 200 ? card : patch.body),
          { status: patch.status },
        );
      }
      if (u.startsWith(`/api/pro/clients/${card.id}/visits`)) {
        visitReads.push(u);
        return new Response(JSON.stringify({ items: [], total: 0 }), { status: 200 });
      }
      if (u.startsWith(`/api/pro/clients/${card.id}?`)) {
        cardReads.push(u);
        return new Response(JSON.stringify(card), { status: 200 });
      }
      if (u.startsWith(`/api/pro/clients/${OTHER.id}?`)) {
        otherReads.push(u);
        return new Response(JSON.stringify(OTHER), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

async function renderCard(
  card: SalonClientCard,
  patch?: Patch,
  hold?: Promise<unknown>,
) {
  mockFetch(card, patch, hold);
  const view = render(<ClientCardClient clientId={card.id} />);
  // A prefix: a linked card's `<h1>` also holds the « MyWeli » chip.
  await screen.findByRole('heading', {
    level: 1,
    name: new RegExp(`^${card.displayName}`),
  });
  return view;
}

/// A save kept in flight until `release()`.
function inFlight() {
  let release!: () => void;
  const hold = new Promise<void>((r) => {
    release = r;
  });
  return { hold, release };
}

/// Opens « Modifier le numéro » and returns the dialog + its phone input.
function openEdit() {
  fireEvent.click(screen.getByRole('button', { name: 'Modifier le numéro' }));
  const dialog = screen.getByRole('dialog', { name: 'Modifier le numéro' });
  const phone = within(dialog).getByLabelText('Numéro de téléphone') as HTMLInputElement;
  return { dialog, phone };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('ClientCardClient — « Modifier » the number of a GUEST card', () => {
  it('« Modifier » sits in the phone row and opens the shared PhoneField, prefilled', async () => {
    await renderCard(GUEST);

    const edit = screen.getByRole('button', { name: 'Modifier le numéro' });
    // Label in name (WCAG 2.5.3): the visible word is « Modifier ».
    expect(edit).toHaveTextContent(/^Modifier$/);
    // Directly under the number (§8: « sous le numéro »), not elsewhere on the
    // card — and NOT inside its row. jsdom has no layout, so the reason is
    // pinned by classes: at 320px the column is ~174px, and a third item in
    // the row dropped alone under « Appeler · WhatsApp », its 48px box
    // (`-my-sm`) overlapping theirs across the row's 12px gap. On its own line
    // `mt-xl` (32px) leaves 32 − 12 − 12 = 8px between the two hit areas, the
    // minimum SYSTEM.md §13.2 asks of adjacent targets.
    const row = screen.getByText('+225 07 00 00 01 01').parentElement!;
    expect(row.contains(edit)).toBe(false);
    const line = row.nextElementSibling!;
    expect(line.contains(edit)).toBe(true);
    expect(line.className.split(/\s+/)).toContain('mt-xl');
    expect(edit.className.split(/\s+/)).toEqual(
      expect.arrayContaining(['-my-sm', 'min-h-12']),
    );

    const { phone } = openEdit();
    expect(phone.value.replace(/\s/g, '')).toBe('+2250700000101');
    expect(screen.queryByText('Numéro du compte client')).toBeNull();
  });

  it('a saved number crosses normalized, closes the dialog, reloads the card and says so', async () => {
    await renderCard(GUEST);
    const { dialog, phone } = openEdit();

    // The placeholder's own spaced format — separators never cross.
    fireEvent.change(phone, { target: { value: '+225 05 05 12 34 56' } });
    const save = within(dialog).getByRole('button', { name: 'Enregistrer' });
    expect(save).not.toBeDisabled();
    fireEvent.click(save);

    await waitFor(() => expect(patched).toHaveLength(1));
    // Exactly: the number and the salon — never the tags (they are not this
    // form's to send, and a stale copy would undo a concurrent tag edit).
    expect(patched[0]).toEqual({ providerId: 'p1', phone: '+2250505123456' });

    expect(await screen.findByText('Numéro mis à jour')).toBeTruthy();
    expect(screen.queryByRole('dialog')).toBeNull();
    // The history follows the number server-side: the card AND its visits are
    // read again, and the new number is what the card shows.
    await screen.findByText('+225 05 05 12 34 56');
    expect(cardReads).toHaveLength(2);
    expect(visitReads).toHaveLength(2);
    expect(screen.getByRole('link', { name: 'Appeler' })).toHaveAttribute(
      'href',
      'tel:+2250505123456',
    );
  });

  it('a short number is refused UNDER the field — nothing is sent', async () => {
    await renderCard(GUEST);
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250700000' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    const alert = await within(dialog).findByText(
      'Le numéro doit comporter 10 chiffres après +225.',
    );
    expect(alert).toHaveAttribute('role', 'alert');
    expect(phone).toHaveAttribute('aria-invalid', 'true');
    expect(phone.getAttribute('aria-describedby')).toContain(alert.id);
    expect(patched).toHaveLength(0);
    expect(screen.getByRole('dialog', { name: 'Modifier le numéro' })).toBeTruthy();
  });

  it('an emptied field asks for a number — a guest card exists only by it', async () => {
    await renderCard(GUEST);
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    expect(
      await within(dialog).findByText('Saisissez un numéro de téléphone.'),
    ).toHaveAttribute('role', 'alert');
    expect(patched).toHaveLength(0);
  });

  it('a server invalid_phone lands under the field, and the dialog stays', async () => {
    await renderCard(GUEST, { status: 400, body: { error: 'invalid_phone' } });
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250505123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    const alert = await within(dialog).findByText(
      'Saisissez un numéro de téléphone valide.',
    );
    expect(alert).toHaveAttribute('role', 'alert');
    expect(phone).toHaveAttribute('aria-invalid', 'true');
    expect(phone.getAttribute('aria-describedby')).toContain(alert.id);
    expect(screen.queryByText('Numéro mis à jour')).toBeNull();
    expect(cardReads).toHaveLength(1);
  });

  it('a number already on another card names that card and leads to it', async () => {
    await renderCard(GUEST, {
      status: 409,
      body: { error: 'client_exists', clientId: OTHER.id },
    });
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250707123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    const sentence = await within(dialog).findByText(
      'Ce numéro est déjà sur la fiche d’Awa.',
    );
    expect(sentence).toHaveAttribute('role', 'alert');
    expect(within(dialog).getByRole('link', { name: 'Ouvrir la fiche' })).toHaveAttribute(
      'href',
      `/pro/clients/${OTHER.id}`,
    );
    // Not a format fault: the number is valid, it is taken.
    expect(phone).not.toHaveAttribute('aria-invalid');
    expect(screen.queryByText('Numéro mis à jour')).toBeNull();

    // A different number makes the sentence stale — it goes with its link.
    fireEvent.change(phone, { target: { value: '+2250505123456' } });
    expect(within(dialog).queryByText('Ce numéro est déjà sur la fiche d’Awa.')).toBeNull();
    expect(within(dialog).queryByRole('link', { name: 'Ouvrir la fiche' })).toBeNull();
  });

  it('the same number again is nothing to do — nothing is sent, the dialog closes', async () => {
    await renderCard(GUEST);
    const { dialog } = openEdit();

    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
    expect(patched).toHaveLength(0);
    expect(screen.queryByText('Numéro mis à jour')).toBeNull();
  });

  it('a card linked meanwhile (409 client_linked) closes and reloads into its read-only state', async () => {
    // The mock's card IS linked after this 409, as the server's would be.
    await renderCard(GUEST, { status: 409, body: { error: 'client_linked' } });
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250505123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
    expect(
      await screen.findByText(
        'Ce client a un compte MyWeli : son numéro est celui du compte.',
      ),
    ).toBeTruthy();
    // Read again — and what came back is the read-only card: the account's
    // number, said so, and no way to edit it.
    expect(await screen.findByText('Numéro du compte client')).toBeTruthy();
    expect(cardReads).toHaveLength(2);
    expect(screen.queryByRole('button', { name: 'Modifier le numéro' })).toBeNull();
    expect(screen.getByText('+225 07 00 00 01 01')).toBeTruthy();
  });

  it('after a client_linked, focus is on the card’s heading — not lost on <body> with « Modifier »', async () => {
    // The dialog hands focus back to its opener, « Modifier » — which the
    // reloaded, linked card no longer has. Focus must land somewhere a
    // keyboard or screen-reader user can carry on from.
    await renderCard(GUEST, { status: 409, body: { error: 'client_linked' } });
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250505123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    await screen.findByText('Numéro du compte client');
    const heading = screen.getByRole('heading', { level: 1, name: /^Koffi/ });
    await waitFor(() => expect(document.activeElement).toBe(heading));
    // Focusable by script only: not a new tab stop.
    expect(heading).toHaveAttribute('tabindex', '-1');
  });

  it('while saving, Escape and the scrim do not close the dialog — the refusal is still shown', async () => {
    // « Annuler » is disabled while saving; Escape and the scrim were not, and
    // a refusal then landed in a dialog that was gone.
    const { hold, release } = inFlight();
    await renderCard(
      GUEST,
      { status: 409, body: { error: 'client_exists', clientId: OTHER.id } },
      hold,
    );
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250707123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(patched).toHaveLength(1));

    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.getByRole('dialog', { name: 'Modifier le numéro' })).toBeTruthy();
    // The scrim: the dialog's aria-hidden first child carries the dismiss.
    const scrim = dialog.firstElementChild as HTMLElement;
    expect(scrim).toHaveAttribute('aria-hidden', 'true');
    fireEvent.click(scrim);
    expect(screen.getByRole('dialog', { name: 'Modifier le numéro' })).toBeTruthy();

    release();
    expect(
      await within(dialog).findByText('Ce numéro est déjà sur la fiche d’Awa.'),
    ).toBeTruthy();
    // Done saving: Escape closes again.
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('a dialog gone mid-save does not read the other card', async () => {
    // Naming the other card costs an AUDITED read of it — true only when its
    // name is shown. Nothing is shown once the page is gone.
    const { hold, release } = inFlight();
    const view = await renderCard(
      GUEST,
      { status: 409, body: { error: 'client_exists', clientId: OTHER.id } },
      hold,
    );
    const { dialog, phone } = openEdit();

    fireEvent.change(phone, { target: { value: '+2250707123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(patched).toHaveLength(1));

    view.unmount();
    release();
    // Long enough for the 409 to be read and acted on.
    await new Promise((r) => setTimeout(r, 50));
    expect(otherReads).toHaveLength(0);
  });
});

describe('ClientCardClient — « Modifier » only where the server says the number is editable', () => {
  it('a guest card from a server that does not say phoneEditable: no « Modifier »', async () => {
    // The web ships on merge, the backend by a manual dispatch: until the new
    // server runs, the old PATCH refuses `{ phone }` with `invalid_tags`, and
    // a « Modifier » would fail on every try. An absent flag means « no ».
    await renderCard(OLD_SERVER_GUEST);

    // The card itself is whole — only the edit is withheld.
    expect(screen.getByText('+225 07 00 00 01 01')).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Appeler' })).toHaveAttribute(
      'href',
      'tel:+2250700000101',
    );
    expect(screen.queryByRole('button', { name: 'Modifier le numéro' })).toBeNull();
    // Not a linked card: no « account number » caption either.
    expect(screen.queryByText('Numéro du compte client')).toBeNull();
  });

  it('a guest card the server marks phoneEditable: false — no « Modifier »', async () => {
    await renderCard({ ...GUEST, phoneEditable: false });

    expect(screen.getByText('+225 07 00 00 01 01')).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Modifier le numéro' })).toBeNull();
  });
});

describe('ClientCardClient — a LINKED card keeps the account number', () => {
  it('no « Modifier »; the number says whose it is', async () => {
    await renderCard({ ...GUEST, linked: true, phoneEditable: false });

    expect(screen.queryByRole('button', { name: 'Modifier le numéro' })).toBeNull();
    expect(screen.queryByRole('button', { name: /^Modifier$/ })).toBeNull();
    // Under the number, in the slot « Modifier » holds on a guest card — and
    // `mt-sm` clear of the 12px the row's links reach below their line, so no
    // invisible hit area lies over it.
    const caption = screen.getByText('Numéro du compte client');
    expect(screen.getByText('+225 07 00 00 01 01').parentElement!.nextElementSibling).toBe(
      caption,
    );
    expect(caption.className.split(/\s+/)).toContain('mt-sm');
    // Still dialable — read-only is not hidden.
    expect(screen.getByRole('link', { name: 'Appeler' })).toHaveAttribute(
      'href',
      'tel:+2250700000101',
    );
  });
});
