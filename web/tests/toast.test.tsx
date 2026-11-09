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
    rerender(<Toast toast={{ id: 1, message: 'Rôle mis à jour.', kind: 'info' }} />);
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
      <Toast toast={{ id: 1, message: 'x', kind: 'error' }} />,
    );
    expect(screen.getByText('x').className).toContain('bg-error');
    rerender(<Toast toast={{ id: 2, message: 'x', kind: 'success' }} />);
    expect(screen.getByText('x').className).toContain('bg-primary');
  });

  // docs/design/web-pro-upload-resize.md — the review of 2026-11-09: two
  // unreadable files picked in a row in Médias showed the same sentence, and
  // re-rendering the same text in place changes nothing a screen reader hears.
  it('the same sentence shown again is a NEW node in the region, so it is read again', () => {
    render(<Harness />);
    fireEvent.click(screen.getByText('fail'));
    const first = screen.getByText('Échec.');
    const region = screen.getByRole('status');
    const changes: MutationRecord[] = [];
    const watcher = new MutationObserver((records) => changes.push(...records));
    watcher.observe(region, { childList: true, subtree: true, characterData: true });
    fireEvent.click(screen.getByText('fail'));
    const added = watcher.takeRecords().concat(changes);
    watcher.disconnect();
    expect(screen.getByText('Échec.')).not.toBe(first);
    expect(added.some((r) => r.addedNodes.length > 0)).toBe(true);
    expect(screen.getByRole('status')).toBe(region); // the region itself stays
  });

  // At 320 px a long sentence had half the screen to wrap in (left-1/2 +
  // translate): the region now spans the screen inside the side gutter and
  // centres the pill (the geometry is measured in pro-upload.spec.ts).
  it('the region spans the screen with the gutter; the pill is centred and capped', () => {
    render(<Toast toast={{ id: 1, message: 'x', kind: 'error' }} />);
    const region = screen.getByRole('status');
    for (const c of ['inset-x-0', 'flex', 'justify-center', 'px-m']) expect(region.className).toContain(c);
    expect(region.className).not.toContain('left-1/2');
    expect(screen.getByText('x').className).toContain('max-w-xl');
  });
});
