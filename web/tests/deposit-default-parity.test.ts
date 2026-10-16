import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { DEFAULT_DEPOSIT_PERCENT } from '../lib/pro/deposit';

/// The percentage both Acompte forms propose when none has been chosen yet —
/// a stored 0 (docs/design/acompte-off-parity.md decision 2). The app's
/// `kDefaultDepositPercentage` (a fraction) and the web's
/// `DEFAULT_DEPOSIT_PERCENT` (a percent) are two hand-written constants; read
/// the mobile source and hold them to one value.
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DART_DEPOSIT = readFileSync(
  join(REPO_ROOT, 'mobile/lib/core/utils/deposit.dart'),
  'utf-8',
)
  // Comments out: a constant quoted in a comment is not the constant —
  // block comments first, then line comments.
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/\/\/.*$/gm, '');

describe('the proposed deposit percentage — app/web parity', () => {
  it('kDefaultDepositPercentage is DEFAULT_DEPOSIT_PERCENT as a fraction', () => {
    // Exactly ONE definition left once comments are out: Dart block comments
    // NEST, which a regex strip cannot follow — a leftover inside one, next
    // to a changed real constant, would otherwise be the one matched.
    expect(
      [...DART_DEPOSIT.matchAll(/kDefaultDepositPercentage\s*=/g)],
      'one definition of kDefaultDepositPercentage',
    ).toHaveLength(1);
    const m = /const\s+double\s+kDefaultDepositPercentage\s*=\s*([0-9.]+)\s*;/.exec(
      DART_DEPOSIT,
    );
    expect(m, 'kDefaultDepositPercentage in deposit.dart').not.toBeNull();
    expect(Number((m as RegExpExecArray)[1])).toBe(DEFAULT_DEPOSIT_PERCENT / 100);
  });

  it('is the owner’s 30 %', () => {
    expect(DEFAULT_DEPOSIT_PERCENT).toBe(30);
  });
});
