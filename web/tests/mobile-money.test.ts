import { describe, expect, it } from 'vitest';
import { emptyTree } from '../lib/api/localities';
import {
  deepLinkKindIsWave,
  findOperator,
  operatorLabel,
  waveDeepLink,
} from '../lib/mobile-money';
import { fixtureTree } from './localities.test';

/// Multi-pays MP3 — Mobile-Money helpers (the app's mobile_money.dart, web
/// mirror). Deep links come ONLY from the closed deepLinkKind vocabulary
/// (T56).

describe('findOperator / operatorLabel', () => {
  it('resolves by wire id, then by legacy label; unknown renders as-is', () => {
    expect(findOperator(fixtureTree, 'orangeMoney')?.label).toBe(
      'Orange Money',
    );
    expect(findOperator(fixtureTree, 'Orange Money')?.id).toBe('orangeMoney');
    expect(operatorLabel(fixtureTree, 'mtnMoMo')).toBe('MTN MoMo');
    expect(operatorLabel(fixtureTree, 'Opérateur Inconnu')).toBe(
      'Opérateur Inconnu',
    );
    expect(operatorLabel(emptyTree, 'wave')).toBe('wave');
    expect(findOperator(fixtureTree, null)).toBeNull();
  });

  it('reaches second-market catalogs too', () => {
    expect(findOperator(fixtureTree, 'airtelMoney')?.label).toBe(
      'Airtel Money',
    );
  });
});

describe('deepLinkKindIsWave / waveDeepLink (T56)', () => {
  it('only the closed `wave` kind builds a link', () => {
    expect(deepLinkKindIsWave('wave')).toBe(true);
    expect(deepLinkKindIsWave(null)).toBe(false);
    expect(deepLinkKindIsWave('https://evil.example')).toBe(false);
  });

  it('pre-fills digits + rounded amount; no digits → null', () => {
    expect(waveDeepLink('+225 07 01 02 03 04', 7500)).toBe(
      'https://pay.wave.com/?recipient=2250701020304&amount=7500',
    );
    expect(waveDeepLink('––', 7500)).toBeNull();
  });
});
