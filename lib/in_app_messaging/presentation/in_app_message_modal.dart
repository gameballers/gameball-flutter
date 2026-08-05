import 'package:flutter/material.dart';

import '../models/in_app_message.dart';

/// The modal layout: optional image, optional header, body, and up to two
/// buttons.
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
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onClosePressed;

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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message.imageUrl != null) _image(message.imageUrl!),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (message.header != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                message.header!,
                                key: const Key('gb_iam_header'),
                                textAlign: style.headerAlign ?? TextAlign.start,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: style.headerColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Text(
                            message.body,
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
