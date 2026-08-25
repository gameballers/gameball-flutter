import 'package:flutter/material.dart';

import '../models/in_app_message.dart';
import 'message_view_metrics.dart';
import 'message_presenter.dart' show messageEntrance;

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
      child: _entrance(
        context,
        child: Padding(
          padding: ModalMetrics.margin,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ModalMetrics.maxWidth),
            child: Material(
              key: const Key('gb_iam_surface'),
              color: style.backgroundColor ?? theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(ModalMetrics.cornerRadius),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Scrollable rather than clipped. A long promo on a small phone,
                  // or any copy at an accessibility text scale, is taller than the
                  // card — and a clipped card loses its buttons, which is the one
                  // part of the message that has to stay reachable.
                  //
                  // SingleChildScrollView sizes to its child up to the incoming
                  // constraint, so a short message stays short; it only scrolls
                  // once the content genuinely does not fit.
                  //
                  // The tap target wraps the content, not the Stack, so the close
                  // button stays outside it. Buttons sit inside but win the hit
                  // test themselves, so their taps never reach here.
                  SingleChildScrollView(
                    child: _wrapTappable(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (message.imageUrl != null)
                            _image(context, message.imageUrl!),
                          // Omitted entirely for image-only, so there is no blank
                          // band under the artwork.
                          if (_hasText || message.buttons.isNotEmpty)
                            Padding(
                              padding:
                                  ModalMetrics.contentPadding,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (message.header != null)
                                    Padding(
                                      padding: EdgeInsets.only(
                                          bottom: message.body != null
                                              ? ModalMetrics.headerToBodySpacing
                                              : 0),
                                      child: Text(
                                        message.header!,
                                        key: const Key('gb_iam_header'),
                                        textAlign: style.headerAlign ??
                                            TextAlign.start,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                          color: style.headerColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  if (message.body != null)
                                    Text(
                                      message.body!,
                                      key: const Key('gb_iam_body'),
                                      textAlign:
                                          style.bodyAlign ?? TextAlign.start,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: style.bodyColor),
                                    ),
                                  if (message.buttons.isNotEmpty)
                                    _buttons(context),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (message.showCloseButton) _closeButton(context, style),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fades and lifts the card into place on first build.
  ///
  /// `TweenAnimationBuilder` animates from `begin` to `end` when it is first
  /// mounted, which is exactly an entrance — and it needs no controller to own,
  /// so this widget stays stateless.
  ///
  /// Honours the platform's reduce-motion setting: a customer who has asked the
  /// OS for less movement gets the message immediately, not a shorter animation.
  Widget _entrance(BuildContext context, {required Widget child}) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: still ? Duration.zero : messageEntrance,
      curve: Curves.easeOutCubic,
      builder: (context, t, animated) => Opacity(
        opacity: t,
        // Scale, not slide: a card that arrives from an edge implies a direction
        // the message does not have. 4% is enough to read as arriving.
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: animated),
      ),
      child: child,
    );
  }

  /// The close affordance, kept legible over anything behind it.
  ///
  /// When the image starts at the top of the modal — an image-led or image-only
  /// message — the glyph sits over artwork whose colours are unknown. A dark
  /// glyph on a dark photograph is effectively invisible, so in that case it gets
  /// a scrim disc behind it and a light glyph. Over the plain message surface no
  /// disc is needed and the campaign's colour is used directly.
  Widget _closeButton(BuildContext context, GameballMessageStyle style) {
    final overArtwork = message.imageUrl != null;
    final glyphColour = style.closeButtonColor ??
        (overArtwork ? MessageMetrics.closeGlyphOverArtwork : null);

    // `end` rather than `right`: in Arabic the trailing corner is the left one,
    // and a close glyph pinned to the wrong corner reads as someone else's UI.
    return Positioned.directional(
      textDirection: Directionality.of(context),
      top: ModalMetrics.closeInset,
      end: ModalMetrics.closeInset,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: overArtwork && style.closeButtonColor == null
              ? MessageMetrics.closeDiscOverArtwork
              : null,
        ),
        child: IconButton(
          key: const Key('gb_iam_close'),
          icon: const Icon(Icons.close),
          iconSize: 20,
          color: glyphColour,
          // Flutter's own localised string, so it is already correct in every
          // locale the host app ships — including Arabic. A literal here would
          // be the only untranslated word in the module.
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClosePressed,
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

  /// Renders the campaign image without ever cropping it.
  ///
  /// The image sizes to its own aspect ratio within the modal's width, capped so
  /// it cannot overflow the screen. Two caps, because the image plays a different
  /// role in each layout: a banner above copy stays modest, while an image-only
  /// message *is* the content and gets most of the screen.
  ///
  /// Deliberately not `BoxFit.cover` with a fixed height. Braze crops header
  /// images to a fixed band, but cropping discards the design a marketer
  /// uploaded — for an image-only message it would reduce a portrait poster to an
  /// unreadable horizontal slice.
  Widget _image(BuildContext context, String url) {
    // Proportional rather than a fixed band. A fixed 220 letterboxed a square
    // image — lossless, but the white bars either side read as a bug. At 40% of
    // the screen a square or landscape banner fills the modal width exactly,
    // and only an unusually tall one letterboxes, where the alternative
    // (cropping) would be worse.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = screenHeight *
        (_hasText
            ? ModalMetrics.imageHeightFraction
            : ModalMetrics.imageOnlyHeightFraction);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.network(
        url,
        key: const Key('gb_iam_image'),
        fit: BoxFit.contain,
        // A campaign image that fails to load must never block the message.
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    return Padding(
      key: const Key('gb_iam_buttons'),
      padding: ModalMetrics.buttonsPadding,
      // Wrap, not Row. Two German or Arabic labels are wider than two English
      // ones and overflowed the card by 360 logical pixels; a second line is
      // always better than a clipped button. `spacing` also removes the
      // hand-rolled left padding, which put the gap on the wrong side in Arabic.
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: ModalMetrics.buttonSpacing,
        runSpacing: ModalMetrics.buttonSpacing,
        children: [
          for (final button in message.buttons) _button(context, button),
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
        padding: ModalMetrics.buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(MessageMetrics.buttonCornerRadius),
          side: style.borderColor != null
              ? BorderSide(color: style.borderColor!)
              : BorderSide.none,
        ),
      ),
      child: Text(button.text),
    );
  }
}
