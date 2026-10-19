/// The agenda's address (docs/design/web-pro-agenda-url.md): what the salon is
/// looking at — the view, its day, the Liste's tab — so that coming back from a
/// booking (« ← Rendez-vous », Back) or a reload lands where it was, as the
/// app's journal does (its day lives for the session). Pure; unit-tested.
///
/// The words are the owner's (Q1, 2026-10-19): `vue`, `jour`, `filtre`, in
/// French without accents. The defaults — Journée, today, « Aujourd'hui » — are
/// never written, so the bare `/pro/rendez-vous` stays « now » and a kept
/// address never pins today to a date that will pass.

import type { ListTab } from './agenda';

export type AgendaView = 'journal' | 'calendar' | 'list';

export type AgendaState = {
  view: AgendaView;
  /// The Journée's salon day (AAAA-MM-JJ).
  journalDate: string;
  /// The Calendrier's chosen salon day.
  selected: string;
  listTab: ListTab;
};

/// Maps, not object literals: a plain object answers `toString`,
/// `constructor`, `__proto__`… through its prototype, and an address is
/// anyone's input.
const VIEW_SLUGS = new Map<string, AgendaView>([
  ['calendrier', 'calendar'],
  ['liste', 'list'],
]);
const VIEW_SLUG_OF: Record<AgendaView, string | null> = {
  journal: null,
  calendar: 'calendrier',
  list: 'liste',
};

const TAB_SLUGS = new Map<string, ListTab>([
  ['aujourdhui', 'today'],
  ['a-venir', 'upcoming'],
  ['en-attente', 'pending'],
  ['tous', 'all'],
]);
const TAB_SLUG_OF: Record<ListTab, string> = {
  today: 'aujourdhui',
  upcoming: 'a-venir',
  pending: 'en-attente',
  all: 'tous',
};

/// A real calendar day in the date field's own form. `2026-02-30` has the
/// shape and is not a day: the round trip through UTC catches it.
export function isDayKey(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const [y, m, d] = s.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return (
    date.getUTCFullYear() === y &&
    date.getUTCMonth() === m - 1 &&
    date.getUTCDate() === d
  );
}

/// The address → what to show. Each bad value is its default, silently: an
/// address someone typed or kept must never break the page. A value meant for
/// another view is not applied — `jour` is the Journée's or the Calendrier's,
/// `filtre` the Liste's. [today] is the SALON's day (the caller's seam).
export function readAgenda(search: string, today: string): AgendaState {
  const p = new URLSearchParams(search);
  const view = VIEW_SLUGS.get(p.get('vue') ?? '') ?? 'journal';
  const jour = p.get('jour') ?? '';
  const day = isDayKey(jour) ? jour : today;
  return {
    view,
    journalDate: view === 'journal' ? day : today,
    selected: view === 'calendar' ? day : today,
    listTab:
      view === 'list' ? (TAB_SLUGS.get(p.get('filtre') ?? '') ?? 'today') : 'today',
  };
}

/// What to show → the address (`''` or `?…`), the shown view's state only and
/// never a default. The order is fixed (vue, then jour or filtre) so the same
/// state is always the same address.
export function agendaQuery(state: AgendaState, today: string): string {
  const p = new URLSearchParams();
  const vue = VIEW_SLUG_OF[state.view];
  if (vue) p.set('vue', vue);
  if (state.view === 'journal' && state.journalDate !== today) {
    p.set('jour', state.journalDate);
  }
  if (state.view === 'calendar' && state.selected !== today) {
    p.set('jour', state.selected);
  }
  if (state.view === 'list' && state.listTab !== 'today') {
    p.set('filtre', TAB_SLUG_OF[state.listTab]);
  }
  const q = p.toString();
  return q ? `?${q}` : '';
}

/// What the booking page hands back to « ← Rendez-vous »: the agenda's own
/// parameters, each validated, and nothing else — no `salon`, nothing that
/// could make the link point anywhere but `/pro/rendez-vous`. The agenda never
/// writes a default, so there is none to drop here.
export function agendaParams(search: string): string {
  const p = new URLSearchParams(search);
  const out = new URLSearchParams();
  const vue = p.get('vue') ?? '';
  if (VIEW_SLUGS.has(vue)) out.set('vue', vue);
  const jour = p.get('jour') ?? '';
  if (isDayKey(jour)) out.set('jour', jour);
  const filtre = p.get('filtre') ?? '';
  if (TAB_SLUGS.has(filtre)) out.set('filtre', filtre);
  const q = out.toString();
  return q ? `?${q}` : '';
}
