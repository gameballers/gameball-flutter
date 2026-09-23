import 'package:flutter/widgets.dart';

/// Hides a subtree without unmounting it, and without disturbing its state.
///
/// Exists because the obvious spelling is wrong in a way that is invisible
/// until it costs you. Returning the child bare when visible and a wrapped
/// child when not — `if (visible) return child;` — changes the *shape* of the
/// tree at the moment visibility flips. Flutter cannot match the elements
/// across that rebuild, so it tears the subtree down and builds a fresh one.
/// Anything stateful inside starts over: a WebView reloads its page, and
/// whatever it reports on load is reported a second time.
///
/// So the wrappers are unconditional and only their values change.
///
/// Distinct from [Offstage] and from [Visibility] with `visible: false`: both
/// of those stop laying the child out, which collapses it to zero size. A
/// WebView measured at 0x0 lays its page out against a zero viewport, which is
/// the one thing a hidden-while-loading widget must not do — the whole point is
/// that it is measured correctly while invisible, so it is finished the instant
/// it is shown.
/// The opacity used to hide, which is deliberately not zero.
///
/// `Opacity` short-circuits at zero — `RenderOpacity` skips painting its child
/// entirely — and an unpainted platform view is one WebKit does not composite.
/// It then suspends the page's rendering loop and throttles its timers, so a
/// widget that drives itself from `requestAnimationFrame` never finishes
/// loading. Measured on iOS: hidden at zero, the page sat on its loading
/// skeleton for the full twelve-second timeout and the poll interval stretched
/// from 250ms to about a second; at this value it loads normally.
///
/// 1/255 is the smallest alpha the compositor can represent, so this is the
/// least visible value that still counts as painting.
const double _hiddenOpacity = 1 / 255;

class VisibilityGate extends StatelessWidget {
  const VisibilityGate({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Not merely cosmetic: a modal's scrim absorbs every tap, so leaving it
      // live while invisible makes the app appear frozen for no visible reason.
      ignoring: !visible,
      child: Opacity(opacity: visible ? 1 : _hiddenOpacity, child: child),
    );
  }
}
