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

  /// Whether to draw the full-bleed composition: the card *is* the artwork,
  /// with the buttons laid over it.
  ///
  /// Requires artwork as well as the declared layout. A campaign that asks for
  /// image-only and supplies no image would otherwise render an empty card that
  /// still logs an impression — so it falls back to the stacked composition,
  /// which is the one case where overriding the declared layout is right.
  bool get _imageOnly =>
      message.layout == GameballMessageLayout.imageOnly &&
      message.imageUrl != null;

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
                  if (_imageOnly)
                    _fullBleed(context)
                  else
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
                  // Only the copy scrolls. The image and the buttons sit
                  // outside it, which is how Braze keeps a call to action on
                  // screen under a tall poster: the artwork takes the height it
                  // needs and the copy absorbs the difference. When everything
                  // was in one scroll view, a tall image pushed the buttons
                  // below the fold and the customer had to scroll to find the
                  // only control that does anything.
                  //
                  // LayoutBuilder because the image's cap depends on how much
                  // card there is, which nothing above this knows.
                  LayoutBuilder(
                    builder: (context, constraints) => _wrapTappable(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (message.imageUrl != null)
                            _image(
                              context,
                              message.imageUrl!,
                              maxHeight: _stackedImageCap(constraints),
                            ),
                          if (_hasText)
                            // Flexible, so the copy yields to the artwork rather
                            // than the other way round, and scrolls once it has
                            // nothing left to yield.
                            Flexible(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: ModalMetrics.contentPadding,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (message.header != null)
                                        Padding(
                                          padding: EdgeInsets.only(
                                              bottom: message.body != null
                                                  ? ModalMetrics
                                                      .headerToBodySpacing
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (message.buttons.isNotEmpty) _buttons(context),
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

  /// The tallest the artwork may be in the stacked composition.
  ///
  /// Two bounds, whichever is smaller. The first is a shape bound — artwork at
  /// or above [ModalMetrics.minImageRatio] fills the card's width exactly, and
  /// because it is a ratio rather than a fraction of the screen it behaves the
  /// same on every device. The second keeps [ModalMetrics.copyReserve] of card
  /// for the copy and buttons, so a portrait poster on a cramped screen loses a
  /// little of its width rather than the message losing its call to action.
  double _stackedImageCap(BoxConstraints constraints) {
    final byShape = constraints.maxWidth / ModalMetrics.minImageRatio;
    if (!constraints.hasBoundedHeight) return byShape;

    final needsRoomBelow = _hasText || message.buttons.isNotEmpty;
    if (!needsRoomBelow) return byShape;

    final byRoom = constraints.maxHeight - ModalMetrics.copyReserve;
    return byRoom < byShape ? byRoom : byShape;
  }

  /// The card is the artwork, with the buttons laid over it.
  ///
  /// Braze draws its image-only modal this way on both platforms, and so does
  /// our own fullscreen image-only variant — the artwork carries the message and
  /// the call to action sits on top of it. What this replaces put the image in a
  /// banner with the buttons beneath, which meant the card's content padding and
  /// the button row's own padding stacked into a blank strip under artwork that
  /// was supposed to be the whole point.
  ///
  /// The [Stack] takes its size from the image, so the card ends up with the
  /// artwork's own aspect ratio rather than a shape of its own — which is why
  /// there is normally nothing to crop.
  Widget _fullBleed(BuildContext context) {
    final artwork = Stack(
      children: [
        _image(
          context,
          message.imageUrl!,
          maxHeight: MediaQuery.sizeOf(context).height *
              ModalMetrics.imageOnlyHeightFraction,
          // Cover, unlike every other image in this widget. It only bites once
          // the height cap clamps an unusually tall poster, and at that point
          // letterboxing would leave bands of card either side of artwork that
          // is meant to reach the edges.
          fit: BoxFit.cover,
        ),
        if (message.buttons.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: ModalMetrics.imageOnlyButtonsPadding,
              child: _overlayButtons(context),
            ),
          ),
      ],
    );

    if (message.clickAction == null) return artwork;
    // Opaque rather than InkWell: a ripple across the whole card reads as a
    // glitch, and the artwork should not be tinted by a highlight. The buttons
    // sit above this and win the hit test themselves.
    return GestureDetector(
      key: const Key('gb_iam_surface_tap'),
      behavior: HitTestBehavior.opaque,
      onTap: onMessagePressed,
      child: artwork,
    );
  }

  /// Buttons for the full-bleed layout: stacked and stretched, not a trailing
  /// row.
  ///
  /// A compact right-aligned row is a dialog convention and looks lost over a
  /// poster. This matches the fullscreen image-only variant, so the two
  /// compositions a campaign might choose between behave the same way.
  Widget _overlayButtons(BuildContext context) {
    return Column(
      key: const Key('gb_iam_buttons'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final button in message.buttons)
          Padding(
            padding: EdgeInsets.only(
              top: button == message.buttons.first
                  ? 0
                  : ModalMetrics.buttonSpacing,
            ),
            child: _button(context, button),
          ),
      ],
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

  /// The close affordance, coloured to stay legible on the card.
  ///
  /// No disc behind it. The contrast comes from the glyph colour itself, which
  /// [resolveCloseGlyphColor] derives from the message background — so a light
  /// card gets a dark glyph and a dark card a light one. See that function for
  /// why the previous rule, which keyed off whether the message had artwork,
  /// was wrong for a modal in particular.
  Widget _closeButton(BuildContext context, GameballMessageStyle style) {
    // `end` rather than `right`: in Arabic the trailing corner is the left one,
    // and a close glyph pinned to the wrong corner reads as someone else's UI.
    return Positioned.directional(
      textDirection: Directionality.of(context),
      top: ModalMetrics.closeInset,
      end: ModalMetrics.closeInset,
      child: IconButton(
        key: const Key('gb_iam_close'),
        icon: const Icon(Icons.close),
        iconSize: MessageMetrics.closeGlyphSize,
        color: resolveCloseGlyphColor(
          campaignColor: style.closeButtonColor,
          backgroundColor: style.backgroundColor,
        ),
        // Flutter's own localised string, so it is already correct in every
        // locale the host app ships — including Arabic. A literal here would
        // be the only untranslated word in the module.
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: onClosePressed,
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
  Widget _image(
    BuildContext context,
    String url, {
    required double maxHeight,
    BoxFit fit = BoxFit.contain,
  }) {
    // Proportional rather than a fixed band. A fixed 220 letterboxed a square
    // image — lossless, but the white bars either side read as a bug. At 40% of
    // the screen a square or landscape banner fills the modal width exactly,
    // and only an unusually tall one letterboxes, where the alternative
    // (cropping) would be worse.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.network(
        url,
        key: const Key('gb_iam_image'),
        width: double.infinity,
        fit: fit,
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
