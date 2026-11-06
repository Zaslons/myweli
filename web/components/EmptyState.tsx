import type { ReactNode } from 'react';
import { Icon, type IconName } from './Icon';

/// The shared empty state (§12, B6) — the web twin of mobile's `EmptyState`
/// (widgets/common/empty_state.dart), anatomy mirrored: icon at
/// `iconXL`/`textTertiary` → French title → a description that says WHY it's
/// empty → an action wherever one can fix it. "« Aucun résultat » alone is a
/// dead end."
///
/// Before B6, ~20 empty sites existed and NOT ONE had an icon; most were bare
/// dead-end sentences.
///
/// `action` is a ReactNode, not a callback — TaxonomyLandingView is a SERVER
/// component, and a `<Link>` (or a `<Button>` from a client caller) passes
/// through both worlds.
///
/// The emptiness LINE (web-b6-components.md): this component is for PAGE- or
/// PANEL-level emptiness. Sub-section emptiness — a slot grid's « Aucun
/// créneau disponible », a field's « Aucune date bloquée » — stays an inline
/// one-liner: a 64px icon between a date picker and its slot grid would be
/// noise, not guidance.
export function EmptyState({
  icon,
  title,
  description,
  action,
  plain = false,
  align = 'center',
  className = '',
}: {
  icon?: IconName;
  title: string;
  description?: string;
  action?: ReactNode;
  /** No card chrome — for embedding inside an already-boxed host (DataTable). */
  plain?: boolean;
  /**
   * `start`: flush left on the page's edge, with no box and no padding, for the
   * public pages (docs/design/web-swiss-cards.md §5). `plain` alone would keep
   * `p-xl` and break that edge.
   */
  align?: 'center' | 'start';
  className?: string;
}) {
  const start = align === 'start';
  const shell = start
    ? ''
    : `${plain ? 'p-xl' : 'rounded-xl border border-border bg-secondary p-xl'} text-center`;
  return (
    <div className={`${shell} ${className}`}>
      {icon ? (
        <Icon
          name={icon}
          size="iconXL"
          // The search glyph starts 3/24 inside its 64px box, so the lens would stand
          // 8px right of the title. Both `start` callers use `search`.
          className={start ? '-ml-s text-textTertiary' : 'mx-auto text-textTertiary'}
        />
      ) : null}
      <p className={`text-titleLarge font-medium text-textSecondary ${icon ? 'mt-l' : ''}`}>
        {title}
      </p>
      {/* B8: the WHY is reading copy — §4's bodyLarge, like every sentence
          standing as content. */}
      {description ? (
        <p className="mt-s text-bodyLarge text-textTertiary">{description}</p>
      ) : null}
      {action ? (
        <div className={start ? 'mt-l flex' : 'mt-l flex justify-center'}>{action}</div>
      ) : null}
    </div>
  );
}
