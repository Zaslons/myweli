import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import * as V from '../lib/pro/salon-validation';
import {
  type GoLiveState,
  type SalonValidation,
  REFUSAL_SENTENCES,
  RESUBMIT_SENTENCE,
  STATE_LINE,
  goLiveState,
  previewBanner,
  refusalLines,
  requestSentLine,
  stateBanner,
  validationForExport,
} from '../lib/pro/salon-validation';

/// B0.18 on the website — docs/design/web-salon-validation.md §2, §3, §6
/// (parent: salon-go-live-approval.md §6.1). The pure half: the state derived
/// once, the approved words, the export's key.

const pending: SalonValidation = {
  state: 'pending',
  submittedAt: '2026-11-13T09:30:00Z',
  wentLive: false,
};
const refused = (code: NonNullable<SalonValidation['refusal']>['code'], note?: string): SalonValidation => ({
  state: 'refused',
  submittedAt: '2026-11-12T09:30:00Z',
  decidedAt: '2026-11-13T09:30:00Z',
  wentLive: false,
  refusal: {
    code,
    final: code === 'outside_ci' || code === 'test_salon',
    ...(note === undefined ? {} : { note }),
  },
});
const approved = (wentLive: boolean, offerLive?: boolean): SalonValidation => ({
  state: 'approved',
  decidedAt: '2026-11-13T09:30:00Z',
  wentLive,
  ...(offerLive === undefined ? {} : { offerLive }),
});

describe('goLiveState — §2’s table, first match wins', () => {
  const rows: [string, string | undefined, SalonValidation | null | undefined, GoLiveState][] = [
    ['no key (a server before B0.18), draft', 'draft', undefined, 'legacy'],
    ['no key, active', 'active', undefined, 'legacy'],
    ['no key, suspended', 'suspended', undefined, 'legacy'],
    ['suspended beats a pending request', 'suspended', pending, 'suspended'],
    ['suspended, never asked', 'suspended', null, 'suspended'],
    ['active beats any row (a rollback)', 'active', refused('photos'), 'live'],
    ['active, never asked (an older image published it)', 'active', null, 'live'],
    ['no status reads live, as the preview does', undefined, null, 'live'],
    ['draft, never asked', 'draft', null, 'neverAsked'],
    ['draft, pending', 'draft', pending, 'pending'],
    ['draft, validated but not live yet (finishing)', 'draft', approved(false), 'pending'],
    ['draft, refused for a fixable reason', 'draft', refused('photos', 'Floues.'), 'refused'],
    ['draft, refused outside Côte d’Ivoire (final)', 'draft', refused('outside_ci'), 'refusedFinal'],
    ['draft, refused as a test salon (final)', 'draft', refused('test_salon'), 'refusedFinal'],
    ['was live, offer live → republish', 'draft', approved(true, true), 'offlineRepublish'],
    ['was live, offer lapsed → billing', 'draft', approved(true, false), 'offlineUnpaid'],
    ['was live, offerLive absent (not the owner)', 'draft', approved(true), 'offline'],
  ];
  for (const [name, status, validation, want] of rows) {
    it(name, () => expect(goLiveState(status, validation)).toBe(want));
  }

  it('a state this client does not know never claims one', () => {
    expect(
      goLiveState('draft', { state: 'archived', wentLive: false } as unknown as SalonValidation),
    ).toBe('neverAsked');
  });
});

describe('the refusal sentences ARE the backend’s (salon_validation_copy.dart)', () => {
  // The three channels (push, feed, e-mail) say the backend's words; the
  // card must say the same, or the salon reads two different reasons.
  const dart = readFileSync(
    join(__dirname, '..', '..', 'backend', 'lib', 'src', 'validation', 'salon_validation_copy.dart'),
    'utf8',
  )
    // Code only: a sentence quoted in a comment is not one the server says.
    .split('\n')
    .filter((l) => !l.trim().startsWith('//'))
    .join('\n');

  function dartMap(name: string): Record<string, string | null> {
    const start = dart.indexOf(`${name} = {`);
    expect(start, name).toBeGreaterThan(-1);
    const body = dart.slice(start, dart.indexOf('};', start));
    const out: Record<string, string | null> = {};
    const entry = /'([a-z_]+)':\s*((?:'[^']*'\s*)+|null)\s*,/g;
    for (const m of body.matchAll(entry)) {
      out[m[1]] =
        m[2].trim() === 'null'
          ? null
          : [...m[2].matchAll(/'([^']*)'/g)].map((x) => x[1]).join('');
    }
    return out;
  }

  function dartConst(name: string): string {
    const m = new RegExp(`${name}\\s*=\\s*((?:'[^']*'\\s*)+);`).exec(dart);
    expect(m, name).not.toBeNull();
    return [...m![1].matchAll(/'([^']*)'/g)].map((x) => x[1]).join('');
  }

  it('the six codes, word for word', () => {
    const backend = dartMap('kRefusalSentences');
    expect(Object.keys(backend).sort()).toEqual(Object.keys(REFUSAL_SENTENCES).sort());
    expect(REFUSAL_SENTENCES).toEqual(backend);
  });

  it('the resubmit sentence', () => {
    expect(RESUBMIT_SENTENCE).toBe(dartConst('kResubmitSentence'));
  });
});

describe('the words of §6.1 (approved word for word)', () => {
  it('the « Mes salons » line of each state', () => {
    expect(STATE_LINE).toEqual({
      neverAsked: 'Brouillon — pas encore en ligne',
      pending: 'En cours de validation',
      refused: 'Mise en ligne refusée',
      refusedFinal: 'Mise en ligne refusée',
      live: 'En ligne',
      offlineRepublish: 'Plus en ligne',
      offlineUnpaid: 'Plus en ligne',
      offline: 'Plus en ligne',
      suspended: 'Suspendu',
    });
  });

  it('pending: the banner promises no delay (Q4)', () => {
    expect(stateBanner('pending', pending)).toEqual({
      tone: 'neutral',
      title: 'En cours de validation',
      lines: [
        'Nous examinons votre salon avant sa mise en ligne. Nous vous préviendrons dès que c’est fait.',
      ],
    });
  });

  it('refused (fixable): the sentence, the note on its own line, then what to do', () => {
    expect(stateBanner('refused', refused('photos', '  Plus de lumière, svp.  '))).toEqual({
      tone: 'error',
      title: 'Mise en ligne refusée',
      lines: [
        'Les photos ne montrent pas assez clairement le salon et son travail.',
        'Plus de lumière, svp.',
        'Modifiez votre salon, puis renvoyez-le pour validation.',
      ],
    });
  });

  it('refused « other »: the note alone, then what to do', () => {
    expect(stateBanner('refused', refused('other', 'Le nom ne correspond pas.'))?.lines).toEqual([
      'Le nom ne correspond pas.',
      'Modifiez votre salon, puis renvoyez-le pour validation.',
    ]);
  });

  it('refused for good: the sentence and the note — never « renvoyez »', () => {
    const b = stateBanner('refusedFinal', refused('outside_ci', 'Pin à Dakar.'));
    expect(b?.lines).toEqual([
      'MyWeli n’est pas encore disponible dans votre pays. Si votre salon est en Côte d’Ivoire, écrivez-nous depuis « Aide & Support ».',
      'Pin à Dakar.',
    ]);
    expect(b?.lines.join(' ')).not.toMatch(/renvoy/i);
  });

  it('no longer online: the billing sentence, or « Vous pouvez le remettre en ligne. »', () => {
    expect(stateBanner('offlineUnpaid', approved(true, false))).toEqual({
      tone: 'warning',
      title: 'Votre salon n’est plus en ligne',
      lines: [
        'Votre salon n’est plus visible des clients. Contactez-nous pour réactiver — vos données sont intactes.',
      ],
    });
    expect(stateBanner('offlineRepublish', approved(true, true))?.lines).toEqual([
      'Vous pouvez le remettre en ligne.',
    ]);
  });

  it('suspended: §6.1’s words', () => {
    expect(stateBanner('suspended', null)).toEqual({
      tone: 'error',
      title: 'Votre salon est suspendu',
      lines: ['Contactez MyWeli pour en savoir plus.'],
    });
  });

  it('no banner where the card keeps its heading, or has none', () => {
    for (const s of ['legacy', 'neverAsked', 'live', 'offline'] as const) {
      expect(stateBanner(s, null), s).toBeNull();
    }
  });

  it('a refusal with neither sentence nor note says nothing of its own', () => {
    expect(refusalLines(undefined)).toEqual([]);
    expect(refusalLines({ code: 'other', final: false })).toEqual([]);
    expect(refusalLines({ code: 'other', final: false, note: '   ' })).toEqual([]);
  });

  it('« Demande envoyée le … »: the salon’s clock, the long date; nothing without a time', () => {
    // 23:30 UTC on the 12th is already the 13th in Libreville (UTC+1).
    expect(requestSentLine('2026-11-12T23:30:00Z', 'Africa/Libreville')).toBe(
      'Demande envoyée le 13 novembre 2026',
    );
    expect(requestSentLine('2026-11-12T23:30:00Z', 'Africa/Abidjan')).toBe(
      'Demande envoyée le 12 novembre 2026',
    );
    expect(requestSentLine('2026-11-12T23:30:00Z', null)).toBe(
      'Demande envoyée le 12 novembre 2026',
    );
    expect(requestSentLine(undefined, 'Africa/Abidjan')).toBeNull();
    expect(requestSentLine('not a date', 'Africa/Abidjan')).toBeNull();
  });
});

describe('« Aperçu de ma page » (owner, 2026-11-13 — §4.4, §9 Q1)', () => {
  it('a server before B0.18 keeps today’s three sentences', () => {
    expect(previewBanner('draft', undefined)).toBe(
      'Aperçu — votre salon n’est pas encore en ligne. Voici ce que verront vos clients.',
    );
    expect(previewBanner('active', undefined)).toBe(
      'Votre salon est en ligne — ceci est votre page publique.',
    );
    expect(previewBanner('suspended', undefined)).toBe(
      'Votre salon est suspendu. Contactez MyWeli pour le réactiver — vos rendez-vous sont intacts.',
    );
  });

  it('with the new server, one sentence per state', () => {
    expect(previewBanner('draft', null)).toBe(
      'Aperçu — votre salon n’est pas encore en ligne. Voici ce que verront vos clients.',
    );
    expect(previewBanner('draft', pending)).toBe(
      'Aperçu — votre salon est en cours de validation. Voici ce que verront vos clients.',
    );
    expect(previewBanner('draft', approved(false))).toBe(
      'Aperçu — votre salon est en cours de validation. Voici ce que verront vos clients.',
    );
    expect(previewBanner('draft', refused('photos'))).toBe(
      'Aperçu — la mise en ligne de votre salon a été refusée. Voici ce que verront vos clients une fois votre salon validé.',
    );
    expect(previewBanner('draft', refused('test_salon'))).toBe(
      'Aperçu — la mise en ligne de votre salon a été refusée.',
    );
    for (const v of [approved(true, true), approved(true, false), approved(true)]) {
      expect(previewBanner('draft', v)).toBe(
        'Aperçu — votre salon n’est plus en ligne. Voici ce que verront vos clients.',
      );
    }
    expect(previewBanner('suspended', pending)).toBe(
      'Votre salon est suspendu. Contactez MyWeli pour en savoir plus.',
    );
    expect(previewBanner('active', approved(true))).toBe(
      'Votre salon est en ligne — ceci est votre page publique.',
    );
  });
});

describe('the Pro data export’s `validation` (§6)', () => {
  it('never asked → null', () => {
    expect(validationForExport(null)).toBeNull();
  });

  it('pending → the wire’s values, no refusal', () => {
    expect(validationForExport(pending)).toEqual({
      state: 'pending',
      submittedAt: '2026-11-13T09:30:00Z',
      decidedAt: null,
      wentLive: false,
      refusal: null,
    });
  });

  it('refused → the code, final, the note and the sentence the salon reads', () => {
    expect(validationForExport(refused('outside_ci', 'Pin à Dakar.'))?.refusal).toEqual({
      code: 'outside_ci',
      final: true,
      note: 'Pin à Dakar.',
      reason: REFUSAL_SENTENCES.outside_ci,
    });
    expect(validationForExport(refused('other', 'Autre chose.'))?.refusal).toEqual({
      code: 'other',
      final: false,
      note: 'Autre chose.',
      reason: null,
    });
  });

  it('billing state (`offerLive`) stays out of the file', () => {
    expect(validationForExport(approved(true, false))).not.toHaveProperty('offerLive');
  });

  it('a validation from the 0044 backfill (no request time) → submittedAt null', () => {
    expect(validationForExport(approved(true))?.submittedAt).toBeNull();
  });
});

describe('no « vérif » in the validation copy (parent §6.1 — that word is KYC’s)', () => {
  // Every string the module exports, and every sentence it builds for every
  // state — not a sample.
  function strings(value: unknown): string[] {
    if (typeof value === 'string') return [value];
    if (value && typeof value === 'object') return Object.values(value).flatMap(strings);
    return [];
  }
  const states: GoLiveState[] = [
    'legacy', 'suspended', 'live', 'neverAsked', 'pending', 'refused',
    'refusedFinal', 'offlineRepublish', 'offlineUnpaid', 'offline',
  ];
  const validations: (SalonValidation | null | undefined)[] = [
    undefined, null, pending, approved(false), approved(true), approved(true, true),
    approved(true, false),
    ...(['incomplete_info', 'photos', 'unconfirmed', 'outside_ci', 'test_salon', 'other'] as const).map(
      (c) => refused(c, 'note'),
    ),
  ];
  const said = [
    ...strings(V),
    ...states.flatMap((s) => validations.flatMap((v) => strings(stateBanner(s, v)))),
    ...['draft', 'active', 'suspended'].flatMap((st) =>
      validations.map((v) => previewBanner(st, v)),
    ),
    requestSentLine('2026-11-13T09:00:00Z', 'Africa/Abidjan') ?? '',
  ];

  it('covers what the module says (the ban is not empty)', () => {
    expect(said.length).toBeGreaterThan(40);
    expect(said).toContain('En cours de validation');
  });

  it('none of it contains « vérif »', () => {
    expect(said.filter((s) => /v[ée]rif/i.test(s))).toEqual([]);
  });
});
