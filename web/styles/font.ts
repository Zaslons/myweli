import localFont from 'next/font/local';

/// The brand font (docs/design/web-swiss-direction.md §5, WEB-SYSTEM §3).
///
/// Hanken Grotesk, committed so that the build needs no network and no visitor's
/// browser asks a third party for it. One file carries the three weights we use:
/// 400–600, trimmed from the full file, which cost 300 ms of LCP and went over
/// budget (`fonts/README.md` says how it was cut).
///
/// `swap`, because text is never hidden while the file loads (WEB.md §7), and
/// `adjustFontFallback`, so the swap does not move the page.
///
/// **Preloaded, deliberately.** Without it the score looks no better and first
/// paint gets 300 ms worse: 1,060 ms against 757 (web-swiss-direction.md §11).
///
/// **Not in this file, on purpose:** U+202F, the narrow no-break space in every
/// `Intl` French amount (« 5 000 FCFA »). The browser draws that one character from
/// the system stack behind it, as it does for ★ ♥ ✕ and the arrows.
export const brandFont = localFont({
  src: './fonts/hanken-grotesk-latin-400-600.woff2',
  weight: '400 600',
  style: 'normal',
  display: 'swap',
  variable: '--font-brand',
  adjustFontFallback: 'Arial',
});
