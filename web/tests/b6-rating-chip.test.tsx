import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Chip, ChipButton, chipLinkClasses } from '../components/Chip';
import { Rating, ratingFr } from '../components/Rating';

/// B6 — Rating (§3.5) + Chip (§11.3/§16) contracts, pinned.

afterEach(cleanup);

describe('Rating', () => {
  it('renders « ★ 4,8 (32 avis) » — FRENCH comma, glyph as decoration', () => {
    render(<Rating value={4.8} count={32} />);
    const el = screen.getByText(/4,8/);
    expect(el).toHaveTextContent('★ 4,8 (32 avis)');
    expect(el.querySelector('[aria-hidden]')!.textContent).toBe('★');
  });

  it('suffix form: « ★ 4,5 sur 5 »', () => {
    render(<Rating value={4.5} suffix="sur 5" />);
    expect(screen.getByText(/4,5/)).toHaveTextContent('★ 4,5 sur 5');
  });

  it('ratingFr always shows one decimal, comma-separated', () => {
    expect(ratingFr(5)).toBe('5,0');
    expect(ratingFr(4.75)).toBe('4,8');
  });
});

describe('Chip', () => {
  it('outlined wears borderStrong — §16 names outlined chips in the mandatory rule', () => {
    render(<Chip variant="outlined">Tag</Chip>);
    expect(screen.getByText('Tag').className).toContain('border-borderStrong');
  });

  it('tinted takes the semantic kind (the no-show idiom)', () => {
    render(<Chip variant="tinted" tint="error">2 no-shows</Chip>);
    const el = screen.getByText('2 no-shows');
    expect(el.className).toContain('bg-error/10');
    expect(el.className).toContain('text-error');
  });

  it('dense is the list-row micro-badge tier', () => {
    render(<Chip dense>MyWeli</Chip>);
    expect(screen.getByText('MyWeli').className).toContain('text-labelSmall');
  });

  it('ChipButton is a real 48px-floored control; selection = filled', () => {
    const onClick = vi.fn();
    const { rerender } = render(<ChipButton onClick={onClick}>Coiffure</ChipButton>);
    const btn = screen.getByRole('button', { name: 'Coiffure' });
    expect(btn.className).toContain('min-h-12');
    expect(btn.className).toContain('border-borderStrong');
    fireEvent.click(btn);
    expect(onClick).toHaveBeenCalled();
    rerender(<ChipButton selected onClick={onClick}>Coiffure</ChipButton>);
    expect(screen.getByRole('button', { name: 'Coiffure' }).className).toContain('bg-primary');
  });

  it('chipLinkClasses mirrors ChipButton for anchor chips', () => {
    expect(chipLinkClasses(false)).toContain('border-borderStrong');
    expect(chipLinkClasses(false)).toContain('min-h-12');
    expect(chipLinkClasses(true)).toContain('bg-primary');
  });
});
