import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/// The web never promises what the product does not do — the twin of the
/// app's `mobile/test/infra/promise_honesty_pin_test.dart`.
///
/// The promo-video honesty sweep (2026-10-19) found the Pro offer selling
/// « Rappels automatiques WhatsApp/SMS », the home page promising
/// « Confirmations WhatsApp » and `llms.txt` telling AI engines about
/// "WhatsApp/SMS reminders" — while production runs
/// `MESSAGING_PROVIDER=disabled`. Reminders exist, as notifications of the
/// MyWeli app. Design: docs/design/promise-honesty-sweep.md §5.
///
/// Each promise stands on a fact about the product, and this file READS that
/// fact: when messaging is switched on, or the salon's reschedule event is
/// removed (salon-client-reschedule-notify.md §6), the matching test goes red
/// and says what to re-decide — the pin never relaxes, or stays, in silence.
const WEB = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = join(WEB, '..');

/// The false promises, by the fact that makes them false. Lower-case.
const FORBIDDEN: Record<string, string[]> = {
  // MESSAGING_PROVIDER=disabled until company registration.
  'messaging channel': [
    'whatsapp/sms',
    'sms/whatsapp',
    'rappels automatiques whatsapp',
    'rappels whatsapp',
    'rappels sms',
    'rappel par sms',
    'rappel par whatsapp',
    'confirmations whatsapp',
    'confirmation whatsapp',
    'confirmation par whatsapp',
    'whatsapp reminders',
    'sms reminders',
  ],
  // No-custody, permanently: Mobile Money straight to the salon + a screenshot.
  'online payment': [
    'payé en ligne',
    'payée en ligne',
    'paiement en ligne',
    'payez en ligne',
    'réglé en ligne',
    'pay online',
    'paid online',
    'online payment',
  ],
};

/// Source as the copy it renders. Comments are removed only where they
/// cannot be code: a `//` or `/*` that opens a line (or a JSX `{/*`). A
/// general stripper would eat `'image/*'` up to the next `*/`, or a URL's
/// `//` — removing CODE, the one direction a "must not contain" pin must
/// never err in. A comment left in place can only make the pin stricter.
/// Then `'a' + 'b'` is joined, whitespace collapsed (JSX text wraps), the
/// apostrophe compared in one spelling, case ignored.
function asCopy(source: string): string {
  return source
    .replace(/(^|\{)[ \t]*\/\*[\s\S]*?\*\//gm, '$1')
    .replace(/^[ \t]*\/\/.*$/gm, '')
    .replace(/['"`]\s*\+\s*['"`]/g, '')
    .replace(/\s+/g, ' ')
    .replace(/\\'/g, "'")
    .replace(/’/g, "'")
    .toLowerCase();
}

function hits(files: Record<string, string>): string[] {
  const out: string[] = [];
  for (const [path, text] of Object.entries(files)) {
    for (const [family, phrases] of Object.entries(FORBIDDEN)) {
      for (const phrase of phrases) {
        if (text.includes(phrase)) out.push(`${path}: « ${phrase} » (${family})`);
      }
    }
  }
  return out;
}

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

/// The `MESSAGING_PROVIDER` value in the Cloud Run manifest; throws when the
/// entry is missing, so an unread fact never passes as « disabled ».
function messagingProvider(manifest: string): string {
  const m = [...manifest.matchAll(/-\s*name:\s*MESSAGING_PROVIDER\s*\n\s*value:\s*(\S+)/g)];
  if (m.length !== 1) throw new Error(`MESSAGING_PROVIDER found ${m.length}×`);
  return m[0][1];
}

/// The members of `enum SalonEvent` in the backend notifier; throws when the
/// enum is not found.
function salonEvents(dart: string): string[] {
  const body = /enum\s+SalonEvent\s*\{([^}]*)\}/.exec(
    dart.replace(/^\s*\/\/.*$/gm, ''),
  )?.[1];
  if (body == null) throw new Error('enum SalonEvent not found');
  const members = body
    .split(/[,;]/)
    .map((s) => /^\s*([A-Za-z_]\w*)/.exec(s)?.[1])
    .filter((s): s is string => !!s);
  if (members.length === 0) throw new Error('enum SalonEvent has no member');
  return members;
}

const isReschedule = (e: string) => /resched|moved|modif|report/i.test(e);

describe('the facts the pins stand on', () => {
  it('production messaging (WhatsApp/SMS) is still off', () => {
    expect(
      messagingProvider(readFileSync(join(REPO, 'infra/gcp/service.yaml'), 'utf-8')),
      'infra/gcp/service.yaml no longer runs MESSAGING_PROVIDER=disabled — ' +
        'messaging may be ON: re-decide the « messaging channel » pin here ' +
        'and in mobile/test/infra/promise_honesty_pin_test.dart',
    ).toBe('disabled');
  });

  it('the salon IS told when a client reschedules — the Pro app promises it', () => {
    // Re-decided 2026-10-19 (docs/design/salon-client-reschedule-notify.md §6):
    // SalonEvent.clientRescheduled exists and the Pro app says « reporte ».
    // Remove the event and that copy lies again.
    const events = salonEvents(
      readFileSync(join(REPO, 'backend/lib/src/messaging/salon_notifier.dart'), 'utf-8'),
    );
    expect(
      events.filter(isReschedule),
      `SalonEvent has no reschedule event any more (${events}) but the Pro ` +
        'app promises « …réserve, reporte, annule… » — restore the event or the copy',
    ).not.toEqual([]);
  });
});

describe('no web text promises what the product does not do', () => {
  it('app/, components/, lib/ and llms.txt: none of the false phrases', () => {
    const files: Record<string, string> = {};
    for (const dir of ['app', 'components', 'lib']) {
      for (const p of walk(join(WEB, dir))) {
        const rel = relative(WEB, p);
        // Generated from openapi.yaml — API docs, not copy.
        if (rel === join('lib', 'api', 'schema.ts')) continue;
        if (!/\.(ts|tsx)$/.test(p)) continue;
        files[rel] = asCopy(readFileSync(p, 'utf-8'));
      }
    }
    files['public/llms.txt'] = asCopy(readFileSync(join(WEB, 'public/llms.txt'), 'utf-8'));
    // Proof the scan reached the surfaces it claims to.
    expect(Object.keys(files)).toEqual(
      expect.arrayContaining([
        join('lib', 'pro', 'subscription-plans.ts'),
        join('app', 'page.tsx'),
        'public/llms.txt',
      ]),
    );
    expect(
      hits(files),
      'a sentence promises what the product does not do — say what it does ' +
        'today (docs/design/promise-honesty-sweep.md §2)',
    ).toEqual([]);
  });
});

describe('the pin can fail', () => {
  it('each family catches its phrase in code', () => {
    for (const [family, phrases] of Object.entries(FORBIDDEN)) {
      for (const phrase of phrases) {
        expect(hits({ probe: asCopy(`const s = '${phrase}';`) }), `${family}: ${phrase}`)
          .not.toEqual([]);
      }
    }
  });

  it('the shipped sentences are caught — split, wrapped, any case', () => {
    for (const source of [
      "      'Rappels automatiques WhatsApp/SMS (24 h / 2 h)',",
      "['Confirmations WhatsApp', 'Rappels avant votre rendez-vous.'],",
      'spa — online, 24/7, in French. Salons manage bookings, deposits and automated\nWhatsApp/SMS reminders.',
      // A string concatenation and a JSX text wrap.
      "'Rappels automatiques ' +\n  'WhatsApp/SMS (24 h / 2 h)'",
      '<p>\n  Acompte payé\n  en ligne\n</p>',
      // A phrase after `image/*` is still seen (the stripper must not eat it).
      'accept="image/*" />\n<p>Paiement en ligne</p>\n{/* x */}',
    ]) {
      expect(hits({ probe: asCopy(source) }), source).not.toEqual([]);
    }
  });

  it('a whole-line comment quoting the old copy is not a hit', () => {
    expect(
      hits({ probe: asCopy("  // was « Rappels automatiques WhatsApp/SMS »\nconst s = 1;") }),
    ).toEqual([]);
    expect(hits({ probe: asCopy('{/* « Acompte payé en ligne » */}') })).toEqual([]);
  });

  it('the fact readers read what they claim to', () => {
    expect(
      messagingProvider('            - name: MESSAGING_PROVIDER\n              value: termii\n'),
    ).toBe('termii');
    expect(() => messagingProvider('- name: PUSH_PROVIDER\n  value: fcm\n')).toThrow();
    const events = salonEvents(
      'enum SalonEvent { newBooking, clientRescheduled, clientCancelled }',
    );
    expect(events).toEqual(['newBooking', 'clientRescheduled', 'clientCancelled']);
    expect(events.filter(isReschedule)).toEqual(['clientRescheduled']);
    expect(() => salonEvents('class Nope {}')).toThrow();
  });
});
