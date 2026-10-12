import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The status bar's style wherever no screen states one: the dark icons every
/// `AppBar` in the app already sends (`AppTheme`'s
/// `appBarTheme.systemOverlayStyle`).
///
/// ## Why the app root needs one
///
/// Flutter sends a status-bar style only when an `AnnotatedRegion` sits under
/// the status bar — `RenderView._updateSystemChrome` returns early when it
/// finds none, and the platform keeps whatever it was sent last. `MaterialApp`
/// sends dark once, when it builds its light theme, and never on a route
/// change. A screen with an `AppBar` states its own (the bar is a region); a
/// screen without one — the consumer home, among others — states nothing. So
/// once a screen that sent LIGHT icons is popped (the salon cover,
/// salon-cover-photo.md §2.1; the story viewer), its white icons stayed on the
/// near-white home: time and battery invisible.
///
/// Installed in each phone app root's `MaterialApp.router(builder:)`, so it
/// sits under every route. **The deepest region still wins**
/// (`AnnotatedRegionLayer.findAnnotations` asks its children first): the
/// cover, the story viewer and the lightboxes keep their light icons while
/// they are on screen, and this answers only where nothing else does.
/// `test/widget/default_status_bar_style_test.dart` holds the behaviour and
/// the installation.
class DefaultStatusBarStyle extends StatelessWidget {
  const DefaultStatusBarStyle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    // The AppBars' own style, so a screen with a bar and one without agree.
    value:
        Theme.of(context).appBarTheme.systemOverlayStyle ??
        SystemUiOverlayStyle.dark,
    child: child,
  );
}
