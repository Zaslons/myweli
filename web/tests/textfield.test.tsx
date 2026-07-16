import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { TextField } from '../components/TextField';

/// B4 — the shared field's §6 contract (docs/design/web-b4-controls.md).
/// Every assertion here is a register row that measured ZERO before B4:
/// htmlFor (row 9), aria-invalid + aria-describedby (row 10).

afterEach(cleanup);

describe('TextField', () => {
  it('the label is REAL — htmlFor resolves, getByLabelText finds the control', () => {
    render(<TextField label="Votre e-mail" type="email" />);
    const input = screen.getByLabelText('Votre e-mail');
    expect(input).toBeInTheDocument();
    expect(input.tagName).toBe('INPUT');
    expect(input.getAttribute('type')).toBe('email');
  });

  it('hideLabel keeps the accessible name (sr-only, not absent)', () => {
    render(<TextField label="Service ou salon" hideLabel />);
    expect(screen.getByLabelText('Service ou salon')).toBeInTheDocument();
  });

  it('an error is announced AND associated — role=alert, aria-invalid, describedby resolves', () => {
    render(
      <TextField label="E-mail" error="Saisissez une adresse e-mail valide." />,
    );
    const input = screen.getByLabelText('E-mail');
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('Saisissez une adresse e-mail valide.');
    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(input.getAttribute('aria-describedby')).toBe(alert.id);
  });

  it('error + hint chain in describedby — error id FIRST, both resolve', () => {
    render(
      <TextField label="Code" error="Code invalide." hint="Reçu par SMS." />,
    );
    const input = screen.getByLabelText('Code');
    const ids = input.getAttribute('aria-describedby')!.split(' ');
    expect(ids).toHaveLength(2);
    expect(document.getElementById(ids[0])).toHaveTextContent('Code invalide.');
    expect(document.getElementById(ids[1])).toHaveTextContent('Reçu par SMS.');
  });

  it('no error → no aria-invalid, no alert; hint alone still referenced', () => {
    render(<TextField label="Nom" hint="Tel qu’affiché aux clients." />);
    const input = screen.getByLabelText('Nom');
    expect(input).not.toHaveAttribute('aria-invalid');
    expect(screen.queryByRole('alert')).toBeNull();
    const hintId = input.getAttribute('aria-describedby')!;
    expect(document.getElementById(hintId)).toHaveTextContent(
      'Tel qu’affiché aux clients.',
    );
  });

  it('multiline renders a real <textarea> with the same wiring', () => {
    render(<TextField label="Note (optionnelle)" multiline rows={3} />);
    const field = screen.getByLabelText('Note (optionnelle)');
    expect(field.tagName).toBe('TEXTAREA');
  });

  it('a caller-supplied id wins over useId', () => {
    render(<TextField label="Téléphone" id="phone" />);
    expect(screen.getByLabelText('Téléphone').id).toBe('phone');
  });

  it('disabled passes through', () => {
    render(<TextField label="E-mail" disabled />);
    expect(screen.getByLabelText('E-mail')).toBeDisabled();
  });
});
