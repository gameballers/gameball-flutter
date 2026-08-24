import 'package:flutter/material.dart';

import '../models/in_app_message.dart';
import 'message_presenter.dart' show messageEntrance;

/// The fullscreen layout, covering both of its variants.
///
/// Edge to edge, with no card and no margin — that is what distinguishes it from
/// a modal, which is a centred card over a dimmed app. The two variants are
/// genuinely different compositions rather than one with a part hidden:
///
/// * [GameballMessageLayout.textWithImage] stacks image, copy and buttons down
///   the screen on the message background.
/// * [GameballMessageLayout.imageOnly] lets the image fill the screen and floats
///   the buttons **over** it, which is Braze's `GRAPHIC` style and the pattern
///   most consumer apps actually ship: full-bleed promo art with one call to
///   action and the copy baked into the artwork.
///
/// Getting that second one from an inferred layout is exactly why the layout
/// belongs on the wire — see [GameballMessageLayout].
class GameballInAppMessageFullscreen extends StatelessWidget {
  const GameballInAppMessageFullscreen({
    super.key,
    required this.message,
    required this.onButtonPressed,
    required this.onClosePressed,
    required this.onMessagePressed,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onClosePressed;

  /// Invoked when the surface itself is tapped. Only reachable when the campaign
  /// set a message-level action.
  final VoidCallback onMessagePressed;

  bool get _imageOnly => message.layout == GameballMessageLayout.imageOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = message.style;

    return _entrance(
      context,
      child: Material(
        key: const Key('gb_iam_fullscreen_surface'),
        // Opaque by design: a fullscreen message replaces the app rather than
        // floating above it, so there is no scrim and nothing shows through.
        color: style.backgroundColor ?? theme.colorScheme.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_imageOnly)
              _fullBleedImage()
            else
              _stacked(context, theme, style),
            // Outside the tappable surface, so closing never counts as engaging.
            if (message.showCloseButton)
              SafeArea(child: _closeButton(context, style)),
          ],
        ),
      ),
    );
  }

  /// Fades the surface into place on first build.
  ///
  /// Fade alone, where the modal also scales: a fullscreen surface that grows
  /// into position looks like a botched transition, and scaling would move the
  /// artwork's painted bounds — which is the thing this variant is measured on.
  ///
  /// Honours the platform's reduce-motion setting.
  Widget _entrance(BuildContext context, {required Widget child}) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: still ? Duration.zero : messageEntrance,
      curve: Curves.easeOut,
      builder: (context, t, animated) => Opacity(opacity: t, child: animated),
      child: child,
    );
  }

  /// Image fills the screen; buttons float over it.
  Widget _fullBleedImage() {
    return _wrapTappable(
      Stack(
        fit: StackFit.expand,
        children: [
          if (message.imageUrl != null)
            Image.network(
              message.imageUrl!,
              key: const Key('gb_iam_fullscreen_image'),
              // The one place cropping is right: the artwork is meant to bleed
              // to every edge, and letterboxing it would put bands of message
              // background where the designer expected none.
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          if (message.buttons.isNotEmpty)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: _buttons(stretch: true),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Image, then copy, then buttons — down the screen.
  Widget _stacked(
    BuildContext context,
    ThemeData theme,
    GameballMessageStyle style,
  ) {
    final hasImage = message.imageUrl != null;

    // The image takes whatever the copy does not need, exactly as before — the
    // full-bleed look this variant exists for. What changed is that the copy is
    // now bounded and scrollable instead of unbounded: long promotional text, or
    // any text at an accessibility scale, used to overflow off the bottom and
    // take the buttons with it.
    return SafeArea(
      child: _wrapTappable(
        LayoutBuilder(
          builder: (context, constraints) => Column(
            // Centres the block when there is nothing to fill with — a
            // copy-only message on a tall screen. A no-op when an image is
            // present, because Expanded leaves no slack.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage)
                Expanded(
                  child: Image.network(
                    message.imageUrl!,
                    key: const Key('gb_iam_fullscreen_image'),
                    // Contain, unlike the image-only variant above. There the
                    // artwork *is* the message and bleeding to every edge is
                    // the point; here it shares the screen with copy, so
                    // cropping buys nothing and costs whatever the designer
                    // baked into the top and bottom of the image — which for a
                    // promo is usually the offer itself. The modal already
                    // reasons this way, and the same campaign artwork should
                    // not be whole in one type and sliced in the other.
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ConstrainedBox(
                // Copy may claim at most 60% of the height when it shares the
                // screen with artwork, and all of it when it does not. Either
                // way it scrolls past that rather than overflowing, so the
                // buttons underneath stay on screen and reachable.
                constraints: BoxConstraints(
                  maxHeight: hasImage
                      ? constraints.maxHeight * 0.6
                      : constraints.maxHeight,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message.header != null)
                          Padding(
                            padding: EdgeInsets.only(
                                bottom: message.body != null ? 12 : 0),
                            child: Text(
                              message.header!,
                              key: const Key('gb_iam_fullscreen_header'),
                              textAlign: style.headerAlign ?? TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: style.headerColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (message.body != null)
                          Text(
                            message.body!,
                            key: const Key('gb_iam_fullscreen_body'),
                            textAlign: style.bodyAlign ?? TextAlign.center,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: style.bodyColor),
                          ),
                        if (message.buttons.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: _buttons(stretch: true),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Buttons stacked full-width rather than in a right-aligned row.
  ///
  /// A fullscreen message has the width for it, and a call to action that fills
  /// the screen's width is the pattern every promo of this shape uses. The modal's
  /// compact row would look lost here.
  Widget _buttons({required bool stretch}) {
    return Column(
      key: const Key('gb_iam_fullscreen_buttons'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final button in message.buttons)
          Padding(
            padding: EdgeInsets.only(
              top: button == message.buttons.first ? 0 : 12,
            ),
            child: SizedBox(
              width: stretch ? double.infinity : null,
              child: _button(button),
            ),
          ),
      ],
    );
  }

  Widget _button(GameballMessageButton button) {
    final style = button.style;
    return TextButton(
      onPressed: () => onButtonPressed(button),
      style: TextButton.styleFrom(
        backgroundColor: style.backgroundColor,
        foregroundColor: style.textColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: style.borderColor != null
              ? BorderSide(color: style.borderColor!)
              : BorderSide.none,
        ),
      ),
      child: Text(
        button.text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// The close affordance, kept legible over anything behind it.
  ///
  /// Always over artwork in the image-only variant, and usually over it in the
  /// other, so it defaults to a light glyph on a scrim disc unless the campaign
  /// named a colour. A dark glyph on a dark photograph is invisible.
  Widget _closeButton(BuildContext context, GameballMessageStyle style) {
    final overArtwork = message.imageUrl != null;

    // `topEnd`, not `topRight`: in Arabic the trailing corner is the left one.
    return Align(
      alignment: AlignmentDirectional.topEnd,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: overArtwork && style.closeButtonColor == null
                ? const Color(0x59000000)
                : null,
          ),
          child: IconButton(
            key: const Key('gb_iam_fullscreen_close'),
            icon: const Icon(Icons.close),
            iconSize: 24,
            color: style.closeButtonColor ??
                (overArtwork ? const Color(0xFFFFFFFF) : null),
            // Flutter's own localised string, so it is already correct in
            // every locale the host app ships — including Arabic. A literal
            // here would be the only untranslated word in the module.
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClosePressed,
          ),
        ),
      ),
    );
  }

  /// Makes [child] tappable only when the campaign supplied a message action.
  Widget _wrapTappable(Widget child) {
    if (message.clickAction == null) return child;
    return GestureDetector(
      key: const Key('gb_iam_fullscreen_tap'),
      // Opaque rather than InkWell: a ripple across the whole screen reads as a
      // glitch, and the artwork should not be tinted by a highlight.
      behavior: HitTestBehavior.opaque,
      onTap: onMessagePressed,
      child: child,
    );
  }
}
