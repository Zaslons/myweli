import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { Icon, ICON_PATHS } from '../components/Icon';
import { Loading } from '../components/Loading';
import { Skeleton, SkeletonGrid, SkeletonRows } from '../components/Skeleton';
import { icon as iconSizes } from '../styles/tokens';

/// B6 — Icon/Loading/Skeleton contracts, pinned (web-b6-components.md).

afterEach(cleanup);

describe('Icon (§15 row 7i)', () => {
  it('sizes from the §7 token scale — width/height are the token px', () => {
    const { container } = render(<Icon name="bell" size="iconS" />);
    const svg = container.querySelector('svg')!;
    expect(svg.getAttribute('width')).toBe(iconSizes.iconS);
    expect(svg.getAttribute('height')).toBe(iconSizes.iconS);
  });

  it('defaults to iconM — §7 calls 24 "the default action icon"', () => {
    const { container } = render(<Icon name="spa" />);
    expect(container.querySelector('svg')!.getAttribute('width')).toBe(
      iconSizes.iconM,
    );
  });

  it('is decoration by default, a named image with label', () => {
    const { container, rerender } = render(<Icon name="star" />);
    expect(container.querySelector('svg')!.getAttribute('aria-hidden')).toBe('true');
    rerender(<Icon name="star" label="Note" />);
    expect(screen.getByRole('img', { name: 'Note' })).toBeInTheDocument();
  });

  it('every registry path is a plausible Material 24×24 path', () => {
    for (const [name, d] of Object.entries(ICON_PATHS)) {
      expect(d, `${name} path`).toMatch(/^M[\d.]/);
    }
  });
});

describe('Loading (§12 — the unknown-shape state)', () => {
  it('shows the default label and a decorative spinner', () => {
    render(<Loading />);
    expect(screen.getByText('Chargement…')).toBeInTheDocument();
    const spinner = screen.getByText('Chargement…').querySelector('[aria-hidden]');
    expect(spinner!.className).toContain('animate-spin');
    expect(spinner!.className).toContain('motion-reduce:animate-none');
  });

  it('contextual copy passes through', () => {
    render(<Loading label="Chargement des créneaux…" />);
    expect(screen.getByText('Chargement des créneaux…')).toBeInTheDocument();
  });
});

describe('Skeleton (§12 — the known-shape state)', () => {
  it('is aria-hidden and pulses (motion-reduce stilled)', () => {
    const { container } = render(<Skeleton className="h-8" />);
    const el = container.firstElementChild!;
    expect(el.getAttribute('aria-hidden')).toBe('true');
    expect(el.className).toContain('animate-pulse');
    expect(el.className).toContain('motion-reduce:animate-none');
  });

  it('Rows renders N list-shaped blocks, all hidden from AT', () => {
    const { container } = render(<SkeletonRows count={4} />);
    const root = container.firstElementChild!;
    expect(root.getAttribute('aria-hidden')).toBe('true');
    expect(root.children).toHaveLength(4);
  });

  it('Grid mirrors the real grid columns so nothing jumps on load', () => {
    const { container } = render(
      <SkeletonGrid count={3} className="grid-cols-1 sm:grid-cols-2 lg:grid-cols-3" />,
    );
    const root = container.firstElementChild!;
    expect(root.className).toContain('lg:grid-cols-3');
    expect(root.children).toHaveLength(3);
  });
});
