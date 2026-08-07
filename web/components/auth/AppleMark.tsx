/// Apple's own mark, at the 25:31 aspect the official plugin draws it.
///
/// The geometry is Apple's, mechanically derived from `AppleLogoPainter` in the
/// `sign_in_with_apple` package — the same vector the apps render — rather than
/// redrawn by hand or lifted from a third-party icon set.
///
/// **Deliberately NOT added to `Icon.tsx`**: that registry declares its paths
/// are Material Design icons under Apache 2.0, and dropping a brand trademark
/// into it would quietly falsify that statement.
///
/// `fill="currentColor"` so it inherits the button's label colour — one colour
/// to keep in sync instead of two. `aria-hidden` because the button's label
/// already says « Apple » (the web twin of the app's `ExcludeSemantics`).
export function AppleMark({ height = 18 }: { height?: number }) {
  return (
    <svg
      viewBox="0 0 25 31"
      height={height}
      width={(height * 25) / 31}
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M 12.695 8.907 C 11.482 8.907 9.606 7.515 7.63 7.565 C 5.022 7.599 2.631 9.092 1.286 11.457 C -1.421 16.204 0.589 23.215 3.229 27.073 C 4.524 28.952 6.052 31.065 8.078 30.998 C 10.021 30.914 10.752 29.724 13.11 29.724 C 15.451 29.724 16.116 30.998 18.175 30.948 C 20.267 30.914 21.596 29.036 22.875 27.14 C 24.352 24.96 24.967 22.846 25.0 22.729 C 24.95 22.712 20.931 21.152 20.881 16.455 C 20.849 12.53 24.053 10.652 24.203 10.568 C 22.376 7.867 19.57 7.565 18.59 7.498 C 16.032 7.297 13.89 8.907 12.695 8.907 Z M 17.012 4.948 C 18.092 3.64 18.806 1.812 18.607 0.0 C 17.062 0.067 15.202 1.04 14.09 2.348 C 13.093 3.506 12.23 5.368 12.462 7.146 C 14.173 7.28 15.933 6.257 17.012 4.948 Z" />
    </svg>
  );
}
