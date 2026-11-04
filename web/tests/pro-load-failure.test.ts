import { describe, expect, it } from 'vitest';

import { loadFailure, loadFailureMessage } from '../lib/api/load-failure';
import { NO_CONNECTION_MESSAGE } from '../lib/pro/team';

/// docs/design/web-pro-no-connection-copy.md §2 — why a Pro read failed, as
/// the page's error state needs it. Status 0 is « no usable answer » (the
/// lib/api/pro.ts wrappers, web-pro-network-failure.md §2): the person's
/// connection, in the app's sentence. Anything else is the server's answer:
/// the page's own sentence, or ErrorState's default (undefined).

describe('loadFailure — the reads that just ran', () => {
  it.each([
    [[0], 'offline'],
    [[200, 0], 'offline'],
    [[0, 200], 'offline'],
    [[500, 0], 'offline'],
    [[500], 'failed'],
    [[503], 'failed'],
    [[404], 'failed'],
    [[403], 'failed'],
    // A 200 the page could not use (no profile in it) is the server's answer.
    [[200], 'failed'],
    [[200, 500], 'failed'],
  ] as const)('%j → %s', (statuses, expected) => {
    expect(loadFailure(...statuses)).toBe(expected);
  });
});

describe('loadFailureMessage — the error state’s sentence', () => {
  it('offline → the app’s « Pas de connexion. Réessayez. », over the page’s own sentence', () => {
    expect(NO_CONNECTION_MESSAGE).toBe('Pas de connexion. Réessayez.');
    expect(loadFailureMessage('offline')).toBe(NO_CONNECTION_MESSAGE);
    expect(loadFailureMessage('offline', 'Chargement impossible.')).toBe(
      NO_CONNECTION_MESSAGE,
    );
  });

  it('failed → the page’s own sentence, or undefined (ErrorState’s default, untouched)', () => {
    expect(loadFailureMessage('failed', 'Chargement impossible.')).toBe(
      'Chargement impossible.',
    );
    expect(loadFailureMessage('failed')).toBeUndefined();
  });
});
