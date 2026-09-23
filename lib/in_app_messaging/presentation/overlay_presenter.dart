import 'dart:async';

import 'package:flutter/material.dart';

import '../iam_log.dart';
import '../models/in_app_message.dart';
import 'in_app_message_fullscreen.dart';
import 'in_app_message_modal.dart';
import 'in_app_message_slideup.dart';
import 'message_presenter.dart';
import 'message_view_metrics.dart';
import 'visibility_gate.dart';

/// Presents messages in an [OverlayEntry] above every route.
///
/// An overlay entry is not a route, so host navigation can neither cover the
/// message nor pop it — which is the point. It also needs no extra permission,
/// unlike drawing into a window of the module's own.
class OverlayPresenter implements GameballMessagePresenter {
  OverlayPresenter(this.navigatorKey, {this.widgetUrlBuilder});

  /// Supplies the overlay. The host assigns this to `MaterialApp.navigatorKey`.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Composes the reward-campaign URL for a widget message's `openDetail`.
  ///
  /// Injected because building it needs the api key, the customer id, the
  /// locale and the session token — SDK state this layer has no business
  /// holding. Null when the host never started messaging through the SDK, in
  /// which case a widget campaign simply cannot be drawn.
  final String Function(String openDetail)? widgetUrlBuilder;

  OverlayEntry? _entry;
  Timer? _autoDismissTimer;
  VoidCallback? _onDismissed;

  @override
  bool get isShowing => _entry != null;

  @override
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onMessagePressed,
    required VoidCallback onDismissed,
  }) {
    if (_entry != null) {
      iamLog('presenter busy: a message is already showing');
      return false;
    }

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      iamLog(
          'no overlay available yet — is navigatorKey wired to MaterialApp?');
      return false;
    }

    if (!_orientationAllows(message, overlay.context)) {
      // Returning false hands it back to the service, which holds it as pending
      // and retries at the next display opportunity. A poster designed for
      // portrait has its copy baked into the artwork, so showing it sideways is
      // worse than showing it later.
      iamLog('message "${message.id}" needs ${message.orientation.name} '
          'orientation; deferring');
      return false;
    }

    // Resolved before anything is inserted: a widget campaign with no way to
    // compose its url cannot be drawn, and finding that out after the overlay
    // is up would mean flashing an empty card.
    String? widgetUrl;
    if (message.isWidget) {
      final build = widgetUrlBuilder;
      if (build == null) {
        iamLog('message "${message.id}" is a reward campaign, but no widget '
            'url builder is available — is messaging started through the SDK?');
        return false;
      }
      widgetUrl = build(message.widget!.openDetail);
    }

    _onDismissed = onDismissed;
    late final OverlayEntry entry;

    /// Counts the impression and starts the auto-dismiss clock.
    ///
    /// Called a frame after insertion for an ordinary message, and only once
    /// the widget has finished drawing for a reward campaign — which is the
    /// whole point: the contract below defines an impression as "when the
    /// message becomes visible", and a reward campaign is not visible for two
    /// to three seconds after its page reports itself loaded.
    void markShown() {
      if (_entry != entry) return; // dismissed before it ever painted

      onShown();

      final autoDismissAfter = message.autoDismissAfter;
      if (autoDismissAfter != null) {
        _autoDismissTimer = Timer(autoDismissAfter, dismiss);
      }
    }

    entry = OverlayEntry(
      // `opaque: false` either way, but the layer itself decides whether it
      // covers the screen: a modal blocks, a slideup does not.
      builder: (context) => switch (message.type) {
        GameballMessageType.slideup => _SlideupLayer(
            message: message,
            onMessagePressed: onMessagePressed,
            onDismiss: dismiss,
          ),
        GameballMessageType.fullscreen => _FullscreenLayer(
            message: message,
            onButtonPressed: onButtonPressed,
            onMessagePressed: onMessagePressed,
            onDismiss: dismiss,
          ),
        _ => _MessageLayer(
            message: message,
            onButtonPressed: onButtonPressed,
            onMessagePressed: onMessagePressed,
            onDismiss: dismiss,
            widgetUrl: widgetUrl,
            onWidgetReady: markShown,
            // Takes the message away having never shown it. onShown was never
            // called, so no impression is logged and the frequency cap is
            // untouched — the campaign gets another go at its next trigger
            // rather than being burned by a slow network.
            onWidgetFailed: dismiss,
          ),
      },
    );
    _entry = entry;
    overlay.insert(entry);

    // `insert` only schedules a frame; nothing is on screen until that frame is
    // painted. This interface's contract defines an impression as "when the
    // message becomes visible", so the callback waits for the paint. Firing at
    // insert time counts an impression for a message the
    // user may never see — if the app is backgrounded in that instant, frames stop
    // and the callback correctly never runs.
    //
    // A reward campaign is the one message for which a painted frame is *not*
    // visibility: the layer mounts invisible so its WebView can lay out at the
    // real size, and stays that way for the two to three seconds the widget
    // needs to draw. It calls markShown itself, from onWidgetReady.
    if (!message.isWidget) {
      WidgetsBinding.instance.addPostFrameCallback((_) => markShown());
    }
    return true;
  }

  @override
  void dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;

    final entry = _entry;
    if (entry == null) {
      return; // already gone; makes dismissal idempotent
    }
    // Cleared before removing so a re-entrant call cannot double-remove.
    _entry = null;
    entry.remove();

    final onDismissed = _onDismissed;
    _onDismissed = null;
    onDismissed?.call();
  }
}

/// Whether [message] may display in the current orientation.
///
/// Only fullscreen campaigns can insist; the other types are small enough to work
/// either way, and enforcing it for them would suppress messages for no benefit.
bool _orientationAllows(GameballInAppMessage message, BuildContext context) {
  if (message.type != GameballMessageType.fullscreen) return true;
  return switch (message.orientation) {
    GameballMessageOrientation.any => true,
    GameballMessageOrientation.portrait =>
      MediaQuery.orientationOf(context) == Orientation.portrait,
    GameballMessageOrientation.landscape =>
      MediaQuery.orientationOf(context) == Orientation.landscape,
  };
}

/// A fullscreen message: edge to edge, with no scrim because nothing shows past
/// it.
///
/// Back-button handling matters more here than anywhere else — a message covering
/// the entire app with only a small close glyph is the one most likely to feel
/// like a trap.
class _FullscreenLayer extends StatelessWidget {
  const _FullscreenLayer({
    required this.message,
    required this.onButtonPressed,
    required this.onMessagePressed,
    required this.onDismiss,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onMessagePressed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final layer = GameballInAppMessageFullscreen(
      message: message,
      onButtonPressed: onButtonPressed,
      onMessagePressed: onMessagePressed,
      onClosePressed: onDismiss,
    );

    if (Router.maybeOf(context) == null) return layer;
    return BackButtonListener(
      onBackButtonPressed: () async {
        onDismiss();
        return true;
      },
      child: layer,
    );
  }
}

/// A slideup, drawn without a scrim so the app underneath stays usable.
///
/// The contrast with [_MessageLayer] is the whole point of the type. A modal fills
/// the overlay with a scrim that swallows every tap; this occupies only the band
/// its banner needs, so anything outside it reaches the app. No back-button
/// handling either — a non-blocking banner has no claim on the back gesture, and
/// intercepting it would break navigation for a message the user is entitled to
/// ignore.
class _SlideupLayer extends StatelessWidget {
  const _SlideupLayer({
    required this.message,
    required this.onMessagePressed,
    required this.onDismiss,
  });

  final GameballInAppMessage message;
  final VoidCallback onMessagePressed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GameballInAppMessageSlideup(
      message: message,
      onMessagePressed: onMessagePressed,
      onDismissRequested: onDismiss,
    );
  }
}

/// The scrim plus the modal, with back-button handling where it is available.
class _MessageLayer extends StatefulWidget {
  const _MessageLayer({
    required this.message,
    required this.onButtonPressed,
    required this.onMessagePressed,
    required this.onDismiss,
    this.widgetUrl,
    this.onWidgetReady,
    this.onWidgetFailed,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onMessagePressed;
  final VoidCallback onDismiss;
  final String? widgetUrl;
  final VoidCallback? onWidgetReady;
  final VoidCallback? onWidgetFailed;

  @override
  State<_MessageLayer> createState() => _MessageLayerState();
}

class _MessageLayerState extends State<_MessageLayer> {
  /// Whether the layer may be seen and touched yet.
  ///
  /// False only while a reward campaign loads. Every other message is visible
  /// from its first frame.
  late bool _visible = !widget.message.isWidget;

  void _onReady() {
    if (!mounted) return;
    setState(() => _visible = true);
    widget.onWidgetReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;

    final layer = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Absorbs the tap either way — the scrim's job is to block the app
            // beneath — but only dismisses when the campaign allows it. A
            // `closeBehaviour` of `button` means the close glyph is the only way
            // out, so a tap outside must do nothing rather than nothing visible.
            onTap: message.dismissOnScrimTap ? widget.onDismiss : null,
            child: ColoredBox(
              color: message.style.scrimColor ?? MessageMetrics.defaultScrim,
            ),
          ),
        ),
        GameballInAppMessageModal(
          message: message,
          onButtonPressed: widget.onButtonPressed,
          onMessagePressed: widget.onMessagePressed,
          onClosePressed: widget.onDismiss,
          widgetUrl: widget.widgetUrl,
          onWidgetReady: _onReady,
          onWidgetFailed: widget.onWidgetFailed,
        ),
      ],
    );

    return _gate(_withBackButton(context, layer));
  }

  /// Hides the layer while a reward campaign loads, without unmounting it.
  ///
  /// [Opacity] rather than [Offstage] or an invisible [Visibility]: both of
  /// those collapse the subtree to zero size, and a WebView laid out at 0x0
  /// computes its page against a zero viewport — which is exactly the layout the
  /// widget needs in order to draw. It has to be measured correctly *while*
  /// invisible, so the first thing the customer sees is the finished wheel.
  ///
  /// [IgnorePointer] as well, so the scrim does not silently swallow taps for
  /// the seconds before anything is on screen. Without it the app would appear
  /// to freeze for no visible reason.
  Widget _gate(Widget layer) =>
      VisibilityGate(visible: _visible, child: layer);

  /// Lets the system back gesture dismiss the message where that is possible.
  ///
  /// BackButtonListener asserts when there is no Router ancestor, which a plain
  /// MaterialApp does not provide. Only attach it where it works; the scrim and
  /// close button are always available, so the message is never undismissable.
  Widget _withBackButton(BuildContext context, Widget layer) {
    if (Router.maybeOf(context) == null) {
      return layer;
    }
    return BackButtonListener(
      onBackButtonPressed: () async {
        widget.onDismiss();
        return true; // handled; do not pop the host's route
      },
      child: layer,
    );
  }
}
