import 'package:flutter/material.dart';

import '../models/in_app_message.dart';

/// The modal layout, covering both of Braze's modal variants.
///
/// "Text (with Optional Image)" draws a text block with an optional image above
/// it. "Image Only" — no header and no body — draws the image alone, with no
/// empty padding where the text would have been.
///
/// Draws only what the message provides, and falls back to the host's theme for
/// every colour the campaign leaves unset. Knows nothing about overlays,
/// analytics or dismissal policy — it reports taps and lets the presenter
/// decide.
class GameballInAppMessageModal extends StatelessWidget {
  const GameballInAppMessageModal({
    super.key,
    required this.message,
    required this.onButtonPressed,
    required this.onClosePressed,
    required this.onMessagePressed,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onClosePressed;

  /// Invoked when the message surface itself is tapped. Only reachable when the
  /// campaign set a message-level action.
  final VoidCallback onMessagePressed;

  /// Whether there is any text to lay out. False for an image-only message.
  bool get _hasText => message.header != null || message.body != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = message.style;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            key: const Key('gb_iam_surface'),
            color: style.backgroundColor ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // The tap target wraps the content, not the Stack, so the close
                // button stays outside it. Buttons sit inside but win the hit
                // test themselves, so their taps never reach here.
                _wrapTappable(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (message.imageUrl != null) _image(message.imageUrl!),
                      // Omitted entirely for image-only, so there is no blank
                      // band under the artwork.
                      if (_hasText || message.buttons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (message.header != null)
                                Padding(
                                  padding: EdgeInsets.only(
                                      bottom: message.body != null ? 8 : 0),
                                  child: Text(
                                    message.header!,
                                    key: const Key('gb_iam_header'),
                                    textAlign:
                                        style.headerAlign ?? TextAlign.start,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: style.headerColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (message.body != null)
                                Text(
                                  message.body!,
                                  key: const Key('gb_iam_body'),
                                  textAlign: style.bodyAlign ?? TextAlign.start,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: style.bodyColor),
                                ),
                              if (message.buttons.isNotEmpty) _buttons(context),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (message.showCloseButton)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      key: const Key('gb_iam_close'),
                      icon: const Icon(Icons.close),
                      color: style.headerColor,
                      tooltip: 'Close',
                      onPressed: onClosePressed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Makes [child] tappable only when the campaign supplied a message action.
  ///
  /// Without an action the surface stays inert, so a message that was never
  /// meant to be interactive does not silently absorb taps.
  Widget _wrapTappable(Widget child) {
    if (message.clickAction == null) return child;
    return InkWell(
      key: const Key('gb_iam_surface_tap'),
      onTap: onMessagePressed,
      child: child,
    );
  }

  Widget _image(String url) {
    return Image.network(
      url,
      key: const Key('gb_iam_image'),
      height: 160,
      fit: BoxFit.cover,
      // A campaign image that fails to load must never block the message.
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buttons(BuildContext context) {
    return Padding(
      key: const Key('gb_iam_buttons'),
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final button in message.buttons)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _button(context, button),
            ),
        ],
      ),
    );
  }

  Widget _button(BuildContext context, GameballMessageButton button) {
    final style = button.style;
    return TextButton(
      onPressed: () => onButtonPressed(button),
      style: TextButton.styleFrom(
        backgroundColor: style.backgroundColor,
        foregroundColor: style.textColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: style.borderColor != null
              ? BorderSide(color: style.borderColor!)
              : BorderSide.none,
        ),
      ),
      child: Text(button.text),
    );
  }
}
