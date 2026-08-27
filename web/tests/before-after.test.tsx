import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { BeforeAfter } from '../components/provider/BeforeAfter';
import { BeforeAfterViewer } from '../components/provider/BeforeAfterViewer';

/// The drag-reveal comparator (web-provider-before-after.md §5) — the app's
/// slider, plus the keyboard path the app never had. The control is a native
/// range, so most behaviour is the browser's; what THESE pin is our wiring:
/// the centre start, the clip that tracks the value, the aria surface, the
/// thumbs, and the fullscreen contract.
const PAIR_1 = {
  before: 'https://cdn/b1.jpg',
  after: 'https://cdn/a1.jpg',
  caption: 'Tresses collées',
};
const PAIR_2 = { before: 'https://cdn/b2.jpg', after: 'https://cdn/a2.jpg' };

const slider = () =>
  screen.getByRole('slider', { name: 'Comparateur avant/après' });

afterEach(cleanup);

describe('BeforeAfterViewer', () => {
  it('starts dead centre — the state the SSR renders', () => {
    render(<BeforeAfterViewer pairs={[PAIR_1]} />);
    expect(slider()).toHaveProperty('value', '50');
  });

  it('the reveal clip tracks the value', () => {
    const { container } = render(<BeforeAfterViewer pairs={[PAIR_1]} />);
    fireEvent.change(slider(), { target: { value: '80' } });
    const clipped = container.querySelector('[style*="clip-path"]');
    expect(clipped).not.toBeNull();
    // value 80 → the BEFORE layer keeps [0, 80%]: inset clips 20% from the
    // right. A constant clip — or one wired to the wrong side — fails here.
    expect((clipped as HTMLElement).style.clipPath).toBe('inset(0 20% 0 0)');
  });

  it('the tags are painted but OUT of the accessible tree', () => {
    render(<BeforeAfterViewer pairs={[PAIR_1]} />);
    // The slider's own label already says avant/après — the app's
    // ExcludeSemantics reasoning, verbatim.
    expect(screen.getByText('Avant')).toHaveAttribute('aria-hidden', 'true');
    expect(screen.getByText('Après')).toHaveAttribute('aria-hidden', 'true');
  });

  it('caption and hint render; the hint is the app copy minus its tap half', () => {
    render(<BeforeAfterViewer pairs={[PAIR_1]} />);
    screen.getByText('Tresses collées');
    screen.getByText('Glisser pour comparer');
  });

  it('no thumbnails for a single pair', () => {
    render(<BeforeAfterViewer pairs={[PAIR_1]} />);
    expect(screen.queryByRole('button', { name: /Comparaison/ })).toBeNull();
  });

  it('thumbnails switch the pair and say which is active', () => {
    const { container } = render(
      <BeforeAfterViewer pairs={[PAIR_1, PAIR_2]} />,
    );
    const thumb2 = screen.getByRole('button', { name: 'Comparaison 2' });
    expect(thumb2).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(thumb2);
    expect(thumb2).toHaveAttribute('aria-pressed', 'true');
    expect(
      screen.getByRole('button', { name: 'Comparaison 1' }),
    ).toHaveAttribute('aria-pressed', 'false');
    // Pair 2 has no caption — pair 1's must be gone from the figure.
    expect(container.textContent).not.toContain('Tresses collées');
  });

  it('a pair missing either image cannot compare — skipped', () => {
    const { container } = render(
      <BeforeAfterViewer
        pairs={[{ before: '', after: 'https://cdn/a.jpg' }, PAIR_1]}
      />,
    );
    // One valid pair remains → no thumbs, one slider.
    expect(screen.queryByRole('button', { name: /Comparaison/ })).toBeNull();
    expect(container.querySelectorAll('input[type="range"]')).toHaveLength(1);
  });

  it('« Agrandir » opens the fullscreen dialog and Escape closes it', () => {
    render(<BeforeAfterViewer pairs={[PAIR_1]} />);
    fireEvent.click(screen.getByRole('button', { name: 'Agrandir' }));
    const dialog = screen.getByRole('dialog', { name: 'Tresses collées' });
    expect(dialog).toBeInTheDocument();
    fireEvent.keyDown(dialog, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).toBeNull();
  });
});

describe('BeforeAfter (the server shell)', () => {
  it('renders heading + viewer; nothing at all without pairs', () => {
    const { container } = render(<BeforeAfter pairs={[PAIR_1]} />);
    screen.getByRole('heading', { name: 'Avant / Après' });
    expect(container.querySelector('input[type="range"]')).not.toBeNull();
    const empty = render(<BeforeAfter pairs={[]} />);
    expect(empty.container.textContent).toBe('');
  });
});
