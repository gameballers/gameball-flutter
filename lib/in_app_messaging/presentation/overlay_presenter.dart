import 'dart:async';

import 'package:flutter/material.dart';

import '../iam_log.dart';
import '../models/in_app_message.dart';
import 'in_app_message_modal.dart';
import 'message_presenter.dart';

/// Presents messages in an [OverlayEntry] above every route.
///
/// An overlay entry is not a route, so host navigation can neither cover the
/// message nor pop it — which is the point. Braze iOS achieves the same by
/// presenting into its own `UIWindow`; Braze Android draws into the host's view
/// hierarchy only because Android offers nothing better without permissions.
class OverlayPresenter implements GameballMessagePresenter {
  OverlayPresenter(this.navigatorKey);

  /// Supplies the overlay. The host assigns this to `MaterialApp.navigatorKey`.
  final GlobalKey<NavigatorState> navigatorKey;

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
      iamLog('no overlay available yet — is navigatorKey wired to MaterialApp?');
      return false;
    }

    _onDismissed = onDismissed;
    final entry = OverlayEntry(
      builder: (context) => _MessageLayer(
        message: message,
        onButtonPressed: onButtonPressed,
        onMessagePressed: onMessagePressed,
        onDismiss: dismiss,
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    // `insert` only schedules a frame; nothing is on screen until that frame is
    // painted. Both this interface's contract and Braze's definition of an
    // impression are "when the message becomes visible", so the callback waits
    // for the paint. Firing at insert time counts an impression for a message the
    // user may never see — if the app is backgrounded in that instant, frames stop
    // and the callback correctly never runs.
    //
    // The auto-dismiss timer starts here too, so a configured duration measures
    // time the message was actually visible rather than time since insertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_entry != entry) return; // dismissed before it ever painted

      onShown();

      final autoDismissAfter = message.autoDismissAfter;
      if (autoDismissAfter != null) {
        _autoDismissTimer = Timer(autoDismissAfter, dismiss);
      }
    });
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

/// The scrim plus the modal, with back-button handling where it is available.
class _MessageLayer extends StatelessWidget {
  const _MessageLayer({
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
    final layer = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(
              color: message.style.scrimColor ?? const Color(0x99000000),
            ),
          ),
        ),
        GameballInAppMessageModal(
          message: message,
          onButtonPressed: onButtonPressed,
          onMessagePressed: onMessagePressed,
          onClosePressed: onDismiss,
        ),
      ],
    );

    // BackButtonListener asserts when there is no Router ancestor, which a
    // plain MaterialApp does not provide. Only attach it where it works; the
    // scrim and close button are always available, so the message is never
    // undismissable.
    if (Router.maybeOf(context) == null) {
      return layer;
    }
    return BackButtonListener(
      onBackButtonPressed: () async {
        onDismiss();
        return true; // handled; do not pop the host's route
      },
      child: layer,
    );
  }
}
