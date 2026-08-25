/// Every layout constant the three message views use, in one place.
///
/// Values, not a themeable API. Nothing here is configurable by a host or a
/// campaign — a campaign controls colours, text and behaviour, never geometry —
/// so these are `const` and the views read them directly.
///
/// **Why they are gathered rather than inline.** The iOS, Android and React
/// Native ports each render these three layouts themselves, and the four have
/// drifted: the same campaign is a different shape on each. Reconciling them is
/// scheduled after the ports are built and tested, and that pass is a diff
/// between four files only if each platform keeps its numbers in one. The iOS
/// SDK already does, in `MessageViewAttributes.swift`; this is its counterpart,
/// deliberately grouped the same way so the two can be read side by side.
///
/// Two of the differences are **mechanisms rather than numbers** and will need a
/// decision rather than an edit: iOS gives a modal's artwork a fixed height where
/// this bounds it as a fraction of the screen ([ModalMetrics.imageHeightFraction]),
/// and iOS caps a slideup's container where this clamps its text
/// ([SlideupMetrics.maxTextLines]). Both are flagged where they are declared.
///
/// A value here that is load-bearing rather than cosmetic says so on its own
/// doc comment — those are contract, and a port that changes them changes
/// behaviour, not appearance.
library;

import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show EdgeInsets, EdgeInsetsDirectional;

/// Constants shared by more than one message type.
abstract final class MessageMetrics {
  /// The dimmed layer behind a modal, when the campaign names no scrim colour.
  static const Color defaultScrim = Color(0x99000000);

  /// Glyph colour for a close button drawn over artwork, when the campaign
  /// names none.
  ///
  /// Load-bearing: a close button over an unknown photograph needs a colour that
  /// cannot vanish into it. See the disc below.
  static const Color closeGlyphOverArtwork = Color(0xFFFFFFFF);

  /// The disc drawn behind a close glyph that sits over artwork.
  ///
  /// Only applied when the campaign named no close-button colour — if it named
  /// one, it is used directly and no disc is drawn.
  static const Color closeDiscOverArtwork = Color(0x59000000);

  /// Corner radius of a message button, on every type.
  static const double buttonCornerRadius = 8;
}

/// Modal: a centred card over a dimmed app.
abstract final class ModalMetrics {
  /// Gap between the card and the screen edge.
  static const EdgeInsets margin = EdgeInsets.all(24);

  /// The card never grows past this, however wide the screen.
  static const double maxWidth = 420;

  static const double cornerRadius = 16;

  /// Around the text block and buttons. Bottom is tighter because the button
  /// row carries its own top padding.
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(20, 20, 20, 16);

  /// Between the header and the body, applied only when both are present.
  static const double headerToBodySpacing = 8;

  /// Above the button row.
  static const EdgeInsets buttonsPadding = EdgeInsets.only(top: 20);

  /// Between buttons, and between wrapped rows of them.
  static const double buttonSpacing = 8;

  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  /// Inset of the close glyph from the card's top trailing corner.
  static const double closeInset = 4;

  /// How much of the screen's height the artwork may occupy.
  ///
  /// **A mechanism, not a number** — iOS gives the modal image a fixed height
  /// instead, so on a tall phone the two differ by roughly a factor of two for
  /// the same campaign. Whichever survives reconciliation, changing this to a
  /// fixed height is a rewrite of `_image`, not an edit here.
  ///
  /// Proportional rather than fixed because a fixed band letterboxes a square
  /// image — lossless, but the bars read as a bug. At these fractions a square
  /// or landscape banner fills the card's width exactly, and only an unusually
  /// tall one letterboxes, where the alternative (cropping) would be worse.
  static const double imageHeightFraction = 0.4;

  /// The same, for an image-only modal where the artwork is the whole message.
  static const double imageOnlyHeightFraction = 0.65;
}

/// Slideup: a non-blocking banner at one edge.
abstract final class SlideupMetrics {
  /// Gap between the banner and the screen edge, inside the safe area.
  static const EdgeInsets margin = EdgeInsets.all(12);

  /// The banner never grows past this, however wide the screen.
  static const double maxWidth = 480;

  static const double cornerRadius = 12;

  static const double elevation = 6;

  static const EdgeInsets contentPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  /// Lines of copy before the text ellipsises.
  ///
  /// **Load-bearing, and a mechanism rather than a number.** A banner that grew
  /// with its copy would eventually cover the screen it exists not to block.
  /// iOS bounds the container's height instead, which is not the same rule —
  /// see the class comment on [MessageMetrics].
  static const int maxTextLines = 3;

  /// The leading icon, a fixed square.
  ///
  /// Load-bearing: sizing it to its own aspect ratio would change the banner's
  /// height with every campaign.
  static const double iconSize = 40;

  static const double iconCornerRadius = 8;

  /// Between the icon and the copy. Directional so Arabic mirrors it.
  static const EdgeInsetsDirectional iconSpacing =
      EdgeInsetsDirectional.only(end: 12);

  /// Between the copy and the trailing chevron, when the banner is tappable.
  static const EdgeInsetsDirectional chevronSpacing =
      EdgeInsetsDirectional.only(start: 8);

  static const double chevronSize = 20;
}

/// Fullscreen: edge to edge, covering the app.
abstract final class FullscreenMetrics {
  /// Around the copy and the buttons in the stacked composition.
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(24, 24, 24, 24);

  /// Around the buttons floated over a full-bleed image.
  static const EdgeInsets imageOnlyButtonsPadding =
      EdgeInsets.fromLTRB(24, 0, 24, 32);

  /// Between the header and the body, applied only when both are present.
  static const double headerToBodySpacing = 12;

  /// Above the button stack.
  static const EdgeInsets buttonsPadding = EdgeInsets.only(top: 28);

  /// Between stacked buttons.
  static const double buttonSpacing = 12;

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(vertical: 16);

  static const double buttonFontSize = 16;

  /// Inset of the close glyph, inside the safe area.
  static const EdgeInsets closePadding = EdgeInsets.all(8);

  /// How much of the height the copy may claim when it shares the screen with
  /// artwork. It scrolls past this rather than overflowing.
  ///
  /// Load-bearing: clipping removes the buttons first, which is the one part of
  /// the message that has to stay reachable.
  static const double copyHeightFractionWithImage = 0.6;
}
