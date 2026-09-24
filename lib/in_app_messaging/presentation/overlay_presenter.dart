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
    void Function(Map<String, dynamic> event)? onWidgetEvent,
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
      builder: (context) => _ReadinessGate(
        // Only a reward campaign waits. Everything else is visible from its
        // first frame and counts its impression from the post-frame callback
        // below.
        gated: message.isWidget,
        onShown: markShown,
        // `opaque: false` either way, but the layer itself decides whether it
        // covers the screen: a modal blocks, a slideup does not.
        build: (onContentReady) => switch (message.type) {
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
              widgetUrl: widgetUrl,
              onWidgetReady: onContentReady,
              onWidgetFailed: dismiss,
              onWidgetEvent: onWidgetEvent,
            ),
          _ => _MessageLayer(
              message: message,
              onButtonPressed: onButtonPressed,
              onMessagePressed: onMessagePressed,
              onDismiss: dismiss,
              widgetUrl: widgetUrl,
              onWidgetReady: onContentReady,
              // Takes the message away having never shown it. onShown was never
              // called, so no impression is logged and the frequency cap is
              // untouched — the campaign gets another go at its next trigger
              // rather than being burned by a slow network.
              onWidgetFailed: dismiss,
              onWidgetEvent: onWidgetEvent,
            ),
        },
      ),
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
    this.widgetUrl,
    this.onWidgetReady,
    this.onWidgetFailed,
    this.onWidgetEvent,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onMessagePressed;
  final VoidCallback onDismiss;
  final String? widgetUrl;
  final VoidCallback? onWidgetReady;
  final VoidCallback? onWidgetFailed;
  final void Function(Map<String, dynamic> event)? onWidgetEvent;

  @override
  Widget build(BuildContext context) => withBackButton(
        context,
        GameballInAppMessageFullscreen(
          message: message,
          onButtonPressed: onButtonPressed,
          onMessagePressed: onMessagePressed,
          onClosePressed: onDismiss,
          widgetUrl: widgetUrl,
          onWidgetReady: onWidgetReady,
          onWidgetFailed: onWidgetFailed,
          onWidgetEvent: onWidgetEvent,
        ),
        onDismiss,
      );
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

/// Holds a layer invisible until whatever it contains reports itself drawn.
///
/// Shared by the modal and the fullscreen layers rather than implemented in
/// each. Only a reward campaign needs gating — every other message is visible
/// from its first frame — but the two surfaces need identical behaviour, and two
/// copies of a timing-sensitive gate is how they stop being identical.
class _ReadinessGate extends StatefulWidget {
  const _ReadinessGate({
    required this.gated,
    required this.onShown,
    required this.build,
  });

  /// Whether to wait. False for an ordinary message.
  final bool gated;

  /// Called once the content is drawn and the layer has become visible, which
  /// is the moment the impression is counted.
  final VoidCallback onShown;

  /// Builds the layer, handed the callback its content invokes when drawn.
  final Widget Function(VoidCallback onContentReady) build;

  @override
  State<_ReadinessGate> createState() => _ReadinessGateState();
}

class _ReadinessGateState extends State<_ReadinessGate> {
  late bool _visible = !widget.gated;

  void _onContentReady() {
    if (!mounted) return;
    setState(() => _visible = true);
    widget.onShown();
  }

  @override
  Widget build(BuildContext context) => VisibilityGate(
        visible: _visible,
        child: widget.build(_onContentReady),
      );
}

/// The scrim plus the modal, with back-button handling where it is available.
class _MessageLayer extends StatelessWidget {
  const _MessageLayer({
    required this.message,
    required this.onButtonPressed,
    required this.onMessagePressed,
    required this.onDismiss,
    this.widgetUrl,
    this.onWidgetReady,
    this.onWidgetFailed,
    this.onWidgetEvent,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onMessagePressed;
  final VoidCallback onDismiss;
  final String? widgetUrl;
  final VoidCallback? onWidgetReady;
  final VoidCallback? onWidgetFailed;
  final void Function(Map<String, dynamic> event)? onWidgetEvent;

  @override
  Widget build(BuildContext context) {
    final layer = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Absorbs the tap either way — the scrim's job is to block the app
            // beneath — but only dismisses when the campaign allows it. A
            // `closeBehaviour` of `button` means the close glyph is the only way
            // out, so a tap outside must do nothing rather than nothing visible.
            onTap: message.dismissOnScrimTap ? onDismiss : null,
            child: ColoredBox(
              color: message.style.scrimColor ?? MessageMetrics.defaultScrim,
            ),
          ),
        ),
        GameballInAppMessageModal(
          message: message,
          onButtonPressed: onButtonPressed,
          onMessagePressed: onMessagePressed,
          onClosePressed: onDismiss,
          widgetUrl: widgetUrl,
          onWidgetReady: onWidgetReady,
          onWidgetFailed: onWidgetFailed,
          onWidgetEvent: onWidgetEvent,
        ),
      ],
    );

    return withBackButton(context, layer, onDismiss);
  }
}

/// Lets the system back gesture dismiss the message where that is possible.
///
/// BackButtonListener asserts when there is no Router ancestor, which a plain
/// MaterialApp does not provide. Only attach it where it works; the scrim and
/// close button are always available, so the message is never undismissable.
Widget withBackButton(
  BuildContext context,
  Widget layer,
  VoidCallback onDismiss,
) {
  if (Router.maybeOf(context) == null) return layer;
  return BackButtonListener(
    onBackButtonPressed: () async {
      onDismiss();
      return true; // handled; do not pop the host's route
    },
    child: layer,
  );
}
