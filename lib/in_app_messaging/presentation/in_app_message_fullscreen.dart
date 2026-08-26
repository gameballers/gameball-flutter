import 'package:flutter/material.dart';

import '../models/in_app_message.dart';
import 'message_presenter.dart' show messageEntrance;
import 'message_view_metrics.dart';

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

  /// Whether to draw the full-bleed composition.
  ///
  /// Requires artwork as well as the declared layout. This composition renders
  /// the image and the buttons and nothing else, so a campaign that asks for
  /// image-only and supplies no image would otherwise show bare background with
  /// its copy silently dropped — and still log an impression. Falling back to
  /// the stacked composition is the one case where overriding the declared
  /// layout is right, because the alternative is a blank screen.
  bool get _imageOnly =>
      message.layout == GameballMessageLayout.imageOnly &&
      message.imageUrl != null;

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
                  padding: FullscreenMetrics.imageOnlyButtonsPadding,
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
                SizedBox(
                  // A fixed share, not the slack the copy leaves. Sized by
                  // subtraction the image inherited whatever ratio was left
                  // over and letterboxed whenever that did not match the
                  // artwork — 35 of background either side of the live portrait
                  // poster on a 390-wide screen. Braze pins its fullscreen
                  // image to half the content height for the same reason.
                  height: constraints.maxHeight *
                      FullscreenMetrics.imageHeightFraction,
                  child: Image.network(
                    message.imageUrl!,
                    key: const Key('gb_iam_fullscreen_image'),
                    // Cover, as in the image-only variant and as in both
                    // references — Braze crops to its fixed half-screen,
                    // CleverTap to the whole screen. A stacked fullscreen reads
                    // as a poster with copy beneath it rather than a framed
                    // picture, and bars break that reading.
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              // Expanded when there is artwork, so the copy takes the rest
              // exactly and the buttons land at the bottom; Flexible when there
              // is not, so the block can centre in a screen it does not fill.
              _flex(
                expand: hasImage,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: FullscreenMetrics.contentPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (message.header != null)
                          Padding(
                            padding: EdgeInsets.only(
                                bottom: message.body != null
                                    ? FullscreenMetrics.headerToBodySpacing
                                    : 0),
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
                      ],
                    ),
                  ),
                ),
              ),
              if (message.buttons.isNotEmpty)
                Padding(
                  padding: FullscreenMetrics.buttonsPadding,
                  child: _buttons(stretch: true),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// [Expanded] or [Flexible] around the copy, depending on whether artwork is
  /// taking its fixed share above it.
  Widget _flex({required bool expand, required Widget child}) =>
      expand ? Expanded(child: child) : Flexible(child: child);

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
              top: button == message.buttons.first
                  ? 0
                  : FullscreenMetrics.buttonSpacing,
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
        padding: FullscreenMetrics.buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(MessageMetrics.buttonCornerRadius),
          side: style.borderColor != null
              ? BorderSide(color: style.borderColor!)
              : BorderSide.none,
        ),
      ),
      child: Text(
        button.text,
        style: const TextStyle(
            fontSize: FullscreenMetrics.buttonFontSize,
            fontWeight: FontWeight.w600),
      ),
    );
  }

  /// The close affordance, coloured to stay legible on the surface.
  ///
  /// No disc behind it. [resolveCloseGlyphColor] derives the colour from the
  /// message background, which is what sits behind the glyph in the stacked
  /// composition. Over a full-bleed image the background is not what is behind
  /// it, so that is the case a campaign should name `closeButton` for.
  Widget _closeButton(BuildContext context, GameballMessageStyle style) {
    // `topEnd`, not `topRight`: in Arabic the trailing corner is the left one.
    return Align(
      alignment: AlignmentDirectional.topEnd,
      child: Padding(
        padding: FullscreenMetrics.closePadding,
        child: IconButton(
          key: const Key('gb_iam_fullscreen_close'),
          icon: const Icon(Icons.close),
          iconSize: MessageMetrics.closeGlyphSize,
          color: resolveCloseGlyphColor(
            campaignColor: style.closeButtonColor,
            backgroundColor: style.backgroundColor,
          ),
          // Flutter's own localised string, so it is already correct in
          // every locale the host app ships — including Arabic. A literal
          // here would be the only untranslated word in the module.
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClosePressed,
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
