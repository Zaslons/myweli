import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { useRef, useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Modal } from '../components/Modal';

/// B5 — §8's contract, pinned: labelled dialog, focus in / trapped / restored,
/// Escape, scroll lock, scrim dismiss.

afterEach(cleanup);

function Harness({ withInitialFocus = false }: { withInitialFocus?: boolean }) {
  const [open, setOpen] = useState(false);
  const cancelRef = useRef<HTMLButtonElement>(null);
  return (
    <div>
      <button type="button" onClick={() => setOpen(true)}>
        ouvrir
      </button>
      {open ? (
        <Modal
          title="Révoquer l’accès"
          onClose={() => setOpen(false)}
          initialFocusRef={withInitialFocus ? cancelRef : undefined}
        >
          <button type="button">Confirmer</button>
          <button type="button" ref={cancelRef}>
            Annuler
          </button>
        </Modal>
      ) : null}
    </div>
  );
}

describe('Modal', () => {
  it('is a labelled dialog — aria-labelledby resolves to the h2 title', () => {
    render(
      <Modal title="Ajouter un client" onClose={() => {}}>
        <p>corps</p>
      </Modal>,
    );
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAccessibleName('Ajouter un client');
    expect(
      screen.getByRole('heading', { level: 2, name: 'Ajouter un client' }),
    ).toBeInTheDocument();
  });

  it('label replaces the title for a title-less dialog (the Lightbox)', () => {
    render(
      <Modal label="Photo du salon" onClose={() => {}}>
        <img alt="Photo du salon" src="x.jpg" />
      </Modal>,
    );
    expect(screen.getByRole('dialog')).toHaveAccessibleName('Photo du salon');
    expect(screen.queryByRole('heading')).not.toBeInTheDocument();
  });

  it('focuses the first focusable on open, the opener again on close', () => {
    render(<Harness />);
    const opener = screen.getByText('ouvrir');
    opener.focus();
    fireEvent.click(opener);
    expect(screen.getByText('Confirmer')).toHaveFocus();
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(opener).toHaveFocus();
  });

  it('initialFocusRef wins — the cancel path gets focus (SYSTEM §15)', () => {
    render(<Harness withInitialFocus />);
    fireEvent.click(screen.getByText('ouvrir'));
    expect(screen.getByText('Annuler')).toHaveFocus();
  });

  it('Tab at the last focusable wraps to the first; Shift+Tab at the first wraps to the last', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('ouvrir'));
    const confirmer = screen.getByText('Confirmer');
    const annuler = screen.getByText('Annuler');
    annuler.focus();
    fireEvent.keyDown(document, { key: 'Tab' });
    expect(confirmer).toHaveFocus();
    fireEvent.keyDown(document, { key: 'Tab', shiftKey: true });
    expect(annuler).toHaveFocus();
  });

  it('focus that escaped the panel is pulled back in', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('ouvrir'));
    screen.getByText('ouvrir').focus(); // simulate an escape
    fireEvent.keyDown(document, { key: 'Tab' });
    expect(screen.getByText('Confirmer')).toHaveFocus();
  });

  it('locks body scroll while open and restores it on close', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('ouvrir'));
    expect(document.body.style.overflow).toBe('hidden');
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(document.body.style.overflow).toBe('');
  });

  it('the scrim click closes; it is decoration to AT', () => {
    const onClose = vi.fn();
    render(
      <Modal title="T" onClose={onClose}>
        <button type="button">x</button>
      </Modal>,
    );
    const scrim = screen
      .getByRole('dialog')
      .querySelector('[aria-hidden="true"]')!;
    fireEvent.click(scrim);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('a restore target that unmounted is skipped without throwing', () => {
    function Gone() {
      const [phase, setPhase] = useState<'a' | 'open' | 'closed'>('a');
      return (
        <div>
          {phase === 'a' ? (
            <button type="button" onClick={() => setPhase('open')}>
              éphémère
            </button>
          ) : null}
          {phase === 'open' ? (
            <Modal title="T" onClose={() => setPhase('closed')}>
              <button type="button">x</button>
            </Modal>
          ) : null}
          <p>fin</p>
        </div>
      );
    }
    render(<Gone />);
    const opener = screen.getByText('éphémère');
    opener.focus();
    fireEvent.click(opener); // the opener unmounts as the modal opens
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.getByText('fin')).toBeInTheDocument(); // no throw
  });
});
