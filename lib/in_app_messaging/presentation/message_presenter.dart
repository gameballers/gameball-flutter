import 'package:flutter/widgets.dart';

import '../models/in_app_message.dart';

/// Draws a message somewhere the user can see it.
///
/// Internal: not exported to hosts. Deliberately knows nothing about analytics
/// or frequency caps — it reports what happened and the service decides what it
/// means. That is what keeps a second implementation (slideup, banner) cheap.
abstract class GameballMessagePresenter {
  /// Whether a message is on screen right now.
  bool get isShowing;

  /// Puts [message] on screen.
  ///
  /// Returns false without invoking any callback if there is no surface to draw
  /// on, or if a message is already showing.
  ///
  /// [onShown] fires once, when the message becomes visible. [onButtonPressed]
  /// and [onMessagePressed] fire per tap and do **not** dismiss — the caller
  /// decides. [onMessagePressed] is only reachable when the campaign set a
  /// message-level action. [onDismissed] fires exactly once, after the message
  /// leaves the screen, however it left.
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onMessagePressed,
    required VoidCallback onDismissed,
  });

  /// Removes the current message, if any. Safe to call repeatedly.
  void dismiss();
}
