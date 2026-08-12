import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import ErrorBoundary from '../app/error';
import GlobalErrorBoundary from '../app/global-error';
import { scrubEvent } from '../lib/sentry-scrub';

/// The two error boundaries, and what leaves the browser
/// (docs/design/observability-error-reporting.md §5).
///
/// **Neither boundary existed.** A thrown render or data error showed Next's
/// default page — English, no way out, nothing reported.

// `globals` is off in `vitest.config.ts`, so RTL's auto-cleanup never runs and
// each `render` STACKS in the same document (the house idiom — see legal.test).
afterEach(cleanup);

vi.mock('@sentry/nextjs', () => ({
  captureException: vi.fn(),
}));

describe('scrubEvent', () => {
  /// The security-critical part, and the least visible: if it is wrong, the
  /// session cookie and PII go to a third party and *nothing notices* — no test
  /// fails, no page breaks, no log line appears.
  const loaded = () =>
    ({
      request: {
        method: 'POST',
        url: 'https://myweli.com/reserver?token=abc&phone=%2B2250707010101',
        cookies: { session: 'httpOnly-session-value' },
        headers: { Authorization: 'Bearer a-real-access-token' },
        data: { phoneNumber: '+2250707010101', code: '123456' },
      },
      user: { id: 'u1', email: 'awa@example.ci', ip_address: '196.200.1.1' },
      breadcrumbs: [{ message: 'otp for +2250707010101' }],
      extra: { note: 'Awa Koné' },
      contexts: { os: { name: 'iOS' } },
    }) as never;

  it('keeps only the method and the path-less URL', () => {
    const e = scrubEvent(loaded());
    expect(e.request?.method).toBe('POST');
    expect(e.request?.url).toBe('https://myweli.com/reserver');
    // Everything else on the request is gone by reconstruction, not deletion.
    expect((e.request as Record<string, unknown>).cookies).toBeUndefined();
    expect((e.request as Record<string, unknown>).headers).toBeUndefined();
    expect((e.request as Record<string, unknown>).data).toBeUndefined();
  });

  it('clears user, breadcrumbs and extra', () => {
    const e = scrubEvent(loaded());
    expect(e.user).toBeUndefined();
    expect(e.breadcrumbs).toBeUndefined();
    expect(e.extra).toBeUndefined();
  });

  it('KEEPS contexts — runtime metadata, no user data', () => {
    // The most useful thing left once the request is stripped. Clearing it would
    // trade real debugging value for no privacy gain.
    expect(scrubEvent(loaded()).contexts).toEqual({ os: { name: 'iOS' } });
  });

  it('no forbidden value survives anywhere in the serialised event', () => {
    // The per-field assertions above can each pass while a value escapes through
    // a field nobody thought to check. This asserts on what actually goes over
    // the wire.
    const json = JSON.stringify(scrubEvent(loaded()));
    for (const forbidden of [
      'httpOnly-session-value',
      'a-real-access-token',
      '+2250707010101',
      '2250707010101',
      '123456',
      'awa@example.ci',
      '196.200.1.1',
      'Awa Koné',
    ]) {
      expect(json, `"${forbidden}" reached the serialised event`).not.toContain(
        forbidden,
      );
    }
  });

  it('an event without a request is passed through', () => {
    expect(scrubEvent({} as never)).toBeDefined();
  });
});

describe('app/error.tsx — the route boundary', () => {
  const err = Object.assign(new Error('boom'), { digest: 'abc123' });

  it('renders one h1, in French, and offers the way out', () => {
    // §12/B6: "an error state without a way out is a crash with better
    // manners." Next's `reset` IS that retry.
    render(<ErrorBoundary error={err} reset={vi.fn()} />);
    const headings = screen.getAllByRole('heading', { level: 1 });
    expect(headings).toHaveLength(1);
    expect(headings[0]).toHaveTextContent('Une erreur est survenue');
    expect(
      screen.getByRole('button', { name: 'Réessayer' }),
    ).toBeInTheDocument();
  });

  it('the retry control actually calls reset', () => {
    // The house idiom (b6-states.test.tsx clicks this exact label).
    const reset = vi.fn();
    render(<ErrorBoundary error={err} reset={reset} />);
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(reset).toHaveBeenCalledOnce();
  });

  it('never shows the raw error to the user', () => {
    // The message is ours; the exception text is for Sentry and the server log.
    render(
      <ErrorBoundary
        error={Object.assign(new Error('PostgresException: row data here'), {
          digest: 'd',
        })}
        reset={vi.fn()}
      />,
    );
    expect(document.body.textContent).not.toContain('PostgresException');
    expect(document.body.textContent).not.toContain('row data here');
  });
});

describe('app/global-error.tsx — the last boundary', () => {
  // It replaces the ROOT LAYOUT, so it renders its own <html>/<body> and cannot
  // use ErrorState, the header, or anything the layout provides — the thing that
  // failed is the thing those come from.
  const err = Object.assign(new Error('layout blew up'), { digest: 'x' });

  it('renders a French heading and a retry, standing alone', () => {
    render(<GlobalErrorBoundary error={err} reset={vi.fn()} />);
    expect(
      screen.getByRole('heading', { level: 1, name: 'Une erreur est survenue' }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Réessayer' }),
    ).toBeInTheDocument();
  });

  it('never shows the raw error', () => {
    render(<GlobalErrorBoundary error={err} reset={vi.fn()} />);
    expect(document.body.textContent).not.toContain('layout blew up');
  });
});
