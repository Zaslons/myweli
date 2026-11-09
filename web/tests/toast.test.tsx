import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Toast } from '../components/Toast';
import { useToast } from '../lib/useToast';

/// B5 — §7's live-region contract + §15's kind durations, pinned.

afterEach(cleanup);

function Harness() {
  const { toast, show } = useToast();
  return (
    <div>
      <button type="button" onClick={() => show('Enregistré.', 'success')}>
        save
      </button>
      <button type="button" onClick={() => show('Échec.', 'error')}>
        fail
      </button>
      <Toast toast={toast} />
    </div>
  );
}

describe('Toast + useToast', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('the live region exists BEFORE any message lands (§7)', () => {
    render(<Toast toast={null} />);
    const region = screen.getByRole('status');
    expect(region).toBeInTheDocument();
    expect(region).toHaveAttribute('aria-live', 'polite');
    expect(region.className).toContain('z-toast');
    expect(region).toBeEmptyDOMElement();
  });

  it('text swaps inside the SAME persistent region', () => {
    const { rerender } = render(<Toast toast={null} />);
    const region = screen.getByRole('status');
    rerender(<Toast toast={{ message: 'Rôle mis à jour.', kind: 'info' }} />);
    expect(screen.getByRole('status')).toBe(region); // not remounted
    expect(region).toHaveTextContent('Rôle mis à jour.');
  });

  it('success dismisses after 3 s (§15)', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('save'));
    expect(screen.getByRole('status')).toHaveTextContent('Enregistré.');
    act(() => vi.advanceTimersByTime(2999));
    expect(screen.getByRole('status')).toHaveTextContent('Enregistré.');
    act(() => vi.advanceTimersByTime(1));
    expect(screen.getByRole('status')).toBeEmptyDOMElement();
  });

  it('error holds for 6 s — time to read (§15)', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('fail'));
    act(() => vi.advanceTimersByTime(3000));
    expect(screen.getByRole('status')).toHaveTextContent('Échec.');
    act(() => vi.advanceTimersByTime(3000));
    expect(screen.getByRole('status')).toBeEmptyDOMElement();
  });

  it('re-show resets the clock instead of inheriting the old timer', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('save'));
    act(() => vi.advanceTimersByTime(2500));
    fireEvent.click(screen.getByText('save'));
    act(() => vi.advanceTimersByTime(2500)); // old timer would have fired at 3000
    expect(screen.getByRole('status')).toHaveTextContent('Enregistré.');
    act(() => vi.advanceTimersByTime(500));
    expect(screen.getByRole('status')).toBeEmptyDOMElement();
  });

  it('error kind wears bg-error; the others the brand pill', () => {
    const { rerender } = render(
      <Toast toast={{ message: 'x', kind: 'error' }} />,
    );
    expect(screen.getByText('x').className).toContain('bg-error');
    rerender(<Toast toast={{ message: 'x', kind: 'success' }} />);
    expect(screen.getByText('x').className).toContain('bg-primary');
  });
});
