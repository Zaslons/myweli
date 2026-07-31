import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { MonthCalendar } from '../components/pro/MonthCalendar';

/// `MonthCalendar`'s out-of-month cells (A14c, WEB-SYSTEM §15 row 34).
///
/// **The defect was recorded in the mobile source and in no document.**
/// `myweli_month_grid.dart` says: *"Web's `MonthCalendar` draws them dimmed and
/// clickable, and that turned out to be a defect rather than a style: clicking
/// one selects a day the header does not name. A14c changes web to match this,
/// not the other way round."*
///
/// Mobile omits them for a second reason the web shares: `textTertiary` is
/// already spent on *disabled*, so a dimmed-but-active day and a disabled day
/// are the same grey.
describe('MonthCalendar — days outside the month', () => {
  // June 2026 starts on a Monday and ends Tuesday 30th, so the grid's last row
  // carries 1–5 July: real out-of-month cells, in a month whose first row has
  // none. That asymmetry is deliberate — a fixture padded on both sides could
  // hide a bug that only affects one end.
  const props = {
    items: [],
    focused: new Date('2026-06-15T00:00:00.000Z'),
    selected: '2026-06-15',
    onFocus: vi.fn(),
    onSelect: vi.fn(),
    tz: 'Africa/Abidjan',
  };

  it('renders exactly the days IN the month, and no others', () => {
    render(<MonthCalendar {...props} />);

    const days = screen
      .getAllByRole('button')
      .map((b) => b.textContent?.trim())
      .filter((t): t is string => !!t && /^\d+$/.test(t))
      .map(Number);

    // **Counting, not range-checking, and the first draft of this test got
    // that wrong.** It asserted `days.filter(d => d > 30)` was empty — but
    // June's trailing cells are 1–5 JULY, which render as « 1 »…« 5 » and pass
    // a `> 30` check untouched. The test was green against the very defect it
    // was written for. Identity, not the label: June has 30 days, so a correct
    // grid offers 30 buttons and a broken one offers 35.
    expect(days).toHaveLength(30);
    expect([...days].sort((a, b) => a - b)).toEqual(
      Array.from({ length: 30 }, (_, i) => i + 1),
    );
  });

  it('the trailing cells are blank, not absent — the grid stays rectangular', () => {
    const { container } = render(<MonthCalendar {...props} />);
    // The grid's children, whatever they are: 7 per week. If out-of-month days
    // were dropped rather than blanked, June's last row would be two cells wide
    // and the month would visibly reflow. `container.querySelectorAll('button')`
    // would not catch that — a blank cell is deliberately NOT a button.
    const grid = container.querySelector('[data-testid="month-grid"]');
    expect(grid, 'the grid needs a stable hook for this assertion').not.toBeNull();
    expect(grid!.children.length % 7).toBe(0);
    expect(grid!.children.length).toBeGreaterThan(30);
  });
});
