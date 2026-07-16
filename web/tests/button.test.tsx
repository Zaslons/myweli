import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { Button } from '../components/Button';

/// B4 — Button's §13.2 floor and its two parity gaps (WEB-SYSTEM §10: the app's
/// AppButton has a `text` variant and a loading state; the web one had neither).

afterEach(cleanup);

describe('Button', () => {
  it('carries the 48px floor — min-h-12, mobile A3’s Size(0, 48) mirror', () => {
    render(<Button>Réserver</Button>);
    expect(screen.getByRole('button', { name: 'Réserver' }).className).toContain(
      'min-h-12',
    );
  });

  it('the text variant exists and is ink, not brand', () => {
    render(<Button variant="text">Renvoyer le code</Button>);
    const btn = screen.getByRole('button', { name: 'Renvoyer le code' });
    expect(btn.className).toContain('text-textPrimary');
    expect(btn.className).toContain('min-h-12');
  });

  it('isLoading: disabled + aria-busy, and the accessible name SURVIVES', () => {
    render(<Button isLoading>Enregistrer</Button>);
    // The name must survive the spinner swap — `text-transparent` keeps the
    // children in the accessibility tree; `invisible` would have erased them,
    // leaving a nameless busy button.
    const btn = screen.getByRole('button', { name: 'Enregistrer' });
    expect(btn).toBeDisabled();
    expect(btn).toHaveAttribute('aria-busy', 'true');
  });

  it('not loading → no aria-busy, not disabled', () => {
    render(<Button>Enregistrer</Button>);
    const btn = screen.getByRole('button', { name: 'Enregistrer' });
    expect(btn).not.toHaveAttribute('aria-busy');
    expect(btn).not.toBeDisabled();
  });
});
