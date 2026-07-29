import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Tabs } from '../components/Tabs';

/// B9 — the shared tab strip.
///
/// **What this file can and cannot prove.** jsdom does no layout, so the two
/// properties B9 exists for — the row wraps, and each button clears 48px — are
/// unprovable here and are gated in the browser instead
/// (`tests/e2e/type-overflow.spec.ts` and `tests/e2e/tap-targets.spec.ts`). What
/// is worth pinning here is the contract those e2e subjects depend on: the class
/// strings that carry the fix, the group's accessible name, and the selection
/// behaviour. Said plainly rather than left for a reader to assume a green run
/// means the geometry was checked.
const ITEMS = [
  { key: 'a', label: 'Aujourd’hui' },
  { key: 'b', label: 'En attente' },
] as const;

describe('Tabs', () => {
  // `tests/setup.ts` loads jest-dom only — there is no auto-cleanup, so without
  // this every render in this file stacks in the same document and a
  // `getByRole` that should match one element matches four.
  afterEach(cleanup);

  it('renders every label and marks the selected one', () => {
    render(<Tabs label="Filtrer" items={ITEMS} value="a" onChange={() => {}} />);

    expect(screen.getByRole('button', { name: 'Aujourd’hui' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByRole('button', { name: 'En attente' })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
  });

  it('is a NAMED group — not an unlabelled pile of buttons', () => {
    render(<Tabs label="Filtrer" items={ITEMS} value="a" onChange={() => {}} />);
    // The name makes five identical-looking strips distinguishable to a screen
    // reader. **It is not, today, what keeps a Playwright subject on the right
    // element** — an earlier version of this comment claimed that, and the
    // review showed it was fiction: no spec scopes by `getByRole('group')`, and
    // the agenda toolbar's rival « Aujourd’hui » cannot co-exist with strip #2
    // (one renders in the `journal` branch, the other in the `list` branch). The
    // real guard there is `.first()` plus DOM order. The name IS what the
    // `/mon-compte` overflow subject anchors on, which is a genuine use.
    expect(screen.getByRole('group', { name: 'Filtrer' })).toBeInTheDocument();
  });

  it('reports the key, not the index', () => {
    const onChange = vi.fn();
    render(<Tabs label="Filtrer" items={ITEMS} value="a" onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: 'En attente' }));
    expect(onChange).toHaveBeenCalledWith('b');
  });

  it('carries the two classes the browser gates depend on', () => {
    render(<Tabs label="Filtrer" items={ITEMS} value="a" onChange={() => {}} />);

    // `flex-wrap` is the overflow fix: without it a `<button>` flex item's
    // `min-width: auto` pushes the page sideways (measured: 4 items needing
    // 340px of 327 on /pro/rendez-vous at 375).
    expect(screen.getByRole('group', { name: 'Filtrer' }).className).toContain(
      'flex-wrap',
    );
    // `min-h-12` is §13.2's floor. It is not optional and not separable: all
    // five strips measured 38px, and the ONE that measured 56 did so only
    // because it was broken — the overflow forced a label to wrap and
    // `align-items: stretch` grew its siblings to match. Fixing the wrap
    // without the floor would have turned that green subject red.
    for (const b of screen.getAllByRole('button')) {
      expect(b.className).toContain('min-h-12');
    }
  });
});
