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
/// The close glyph is the one appearance rule here that is computed rather than
/// declared — [resolveCloseGlyphColor] at the bottom of this file. It is kept
/// alongside the constants because a port that reimplements it differently
/// produces a control the customer cannot see, which is the failure this whole
/// group exists to prevent.
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

  /// Close glyph for a light message surface, when the campaign names none.
  ///
  /// Load-bearing, and only half of a pair — see [resolveCloseGlyphColor].
  /// Neither value is safe on its own: this one measures 1.6:1 against the
  /// live slideup background, which is why the choice is derived rather than
  /// defaulted.
  static const Color closeGlyphOnLight = Color(0xFF111827);

  /// Close glyph for a dark message surface, when the campaign names none.
  static const Color closeGlyphOnDark = Color(0xFFFFFFFF);

  /// Relative luminance at which [closeGlyphOnLight] and [closeGlyphOnDark]
  /// change places.
  ///
  /// 0.179 is where black and white give identical contrast against the same
  /// background — 4.58:1 each — so picking either side of it is picking the
  /// better of the two, always. Not a taste value: moving it makes one glyph
  /// win a background the other reads better on.
  static const double closeGlyphLuminanceThreshold = 0.179;

  /// Size of the close glyph, on every type that draws one.
  ///
  /// One number rather than two. It was 20 on a modal and 24 on fullscreen, and
  /// nothing about a modal argues for a smaller control — 24 in a 48 hit target
  /// is the same proportion CleverTap uses. Kept separate from the hit target,
  /// which stays 48 everywhere and is the accessibility floor on both platforms.
  static const double closeGlyphSize = 24;

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

  /// Around the text block. No bottom inset: the button block below carries its
  /// own, and the two are separate children now that only the copy scrolls.
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(20, 20, 20, 0);

  /// Between the header and the body, applied only when both are present.
  static const double headerToBodySpacing = 8;

  /// Around the button block, which sits outside the scrolling copy.
  static const EdgeInsets buttonsPadding = EdgeInsets.fromLTRB(20, 20, 20, 16);

  /// Between buttons, and between wrapped rows of them.
  static const double buttonSpacing = 8;

  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  /// Around the buttons floated over a full-bleed image, in the image-only
  /// layout. Narrower than the fullscreen equivalent because a card is
  /// narrower, and it reuses the card's own 20 so the two compositions line up.
  static const EdgeInsets imageOnlyButtonsPadding =
      EdgeInsets.fromLTRB(20, 0, 20, 20);

  /// Inset of the close glyph from the card's top trailing corner.
  static const double closeInset = 4;

  /// The tallest artwork that still fills the card's width without bars.
  ///
  /// Expressed as an **aspect ratio, not a fraction of the screen** — that is
  /// the whole point. The previous rule capped the image at 40% of screen
  /// height while the card's width came from screen width, so the ratio at
  /// which bars appeared slid with the device: 1.013 on a tall phone, 1.226 on
  /// a short one. The same square image was clean on one and letterboxed on the
  /// other, which nobody chose and no marketer could preview.
  ///
  /// Against a ratio the crossover is the same number everywhere. At 0.55
  /// nothing a campaign realistically ships letterboxes — the live 3:5 poster
  /// included — which is Braze's outcome, reached without their cost: they
  /// impose no cap at all, so a portrait poster grows the card until the copy
  /// is crushed into a 23-point sliver.
  static const double minImageRatio = 0.55;

  /// Height always kept for the copy and buttons, whatever the artwork wants.
  ///
  /// Roughly one line of copy plus a button block. Braze has no equivalent and
  /// relies on a required aspect constraint winning, which on a small screen
  /// means a broken constraint rather than a considered outcome. This bars the
  /// image slightly on a genuinely cramped device instead — the one place bars
  /// remain, and the better failure.
  static const double copyReserve = 120;

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
  /// Around the scrolling copy in the stacked composition. No bottom inset:
  /// the button block below carries its own.
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(24, 24, 24, 0);

  /// How much of the available height the artwork takes in the stacked
  /// composition.
  ///
  /// A fixed share, not "whatever the copy leaves". Braze pins its fullscreen
  /// image to exactly half the content height with a required constraint, and
  /// the reason is the same one that drove the modal: an image sized by
  /// subtraction lands on whatever ratio is left over and letterboxes when that
  /// does not match the artwork. Half of the *safe* area rather than half the
  /// screen, because we keep the stack inside it where Braze hides the status
  /// bar instead.
  static const double imageHeightFraction = 0.5;

  /// Around the buttons floated over a full-bleed image.
  static const EdgeInsets imageOnlyButtonsPadding =
      EdgeInsets.fromLTRB(24, 0, 24, 32);

  /// Between the header and the body, applied only when both are present.
  static const double headerToBodySpacing = 12;

  /// Around the button block, which sits outside the scrolling copy.
  static const EdgeInsets buttonsPadding = EdgeInsets.fromLTRB(24, 28, 24, 24);

  /// Between stacked buttons.
  static const double buttonSpacing = 12;

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(vertical: 16);

  static const double buttonFontSize = 16;

  /// Inset of the close glyph, inside the safe area.
  static const EdgeInsets closePadding = EdgeInsets.all(8);

  /// The copy takes what the artwork does not, and scrolls inside it.
  ///
  /// There is no separate cap any more: with the image on a fixed share, the
  /// remainder *is* the copy's bound. Load-bearing all the same — the buttons
  /// sit outside the scroll view, so copy can never push them off.
}

/// The colour to paint a close glyph, or null to let the host's theme decide.
///
/// Three cases, in order:
///
/// 1. The campaign named a colour — use it verbatim, readable or not. It asked
///    for exactly this, and quietly substituting something else is how a brand
///    colour becomes a colour nobody chose.
/// 2. The campaign named a message background — derive the half of the pair
///    that contrasts with it. Worst case, at the threshold itself, is 3.8:1,
///    which clears the 3:1 that WCAG 2.1 asks of a non-text control.
/// 3. Neither — return null and let the platform's own on-surface colour apply.
///    Material already guarantees that contrasts with the surface it sits on,
///    so computing our own would be second-guessing a solved problem.
///
/// Deliberately **not** a function of whether the message has artwork. That was
/// the previous rule and it was wrong twice over: a contained portrait image
/// letterboxes, so the glyph often sits on card background while the message
/// does have an image; and it made naming a close colour switch off the
/// contrast treatment, so the one field a marketer is most likely to touch was
/// the one that could hide the control.
///
/// Over full-bleed artwork the background is not what is behind the glyph, so
/// the derived answer there is a reasonable guess rather than a guarantee —
/// which is the case a campaign should name a colour for, and the case Braze
/// leaves to the marketer too.
Color? resolveCloseGlyphColor({Color? campaignColor, Color? backgroundColor}) {
  if (campaignColor != null) return campaignColor;
  if (backgroundColor == null) return null;
  return backgroundColor.computeLuminance() >
          MessageMetrics.closeGlyphLuminanceThreshold
      ? MessageMetrics.closeGlyphOnLight
      : MessageMetrics.closeGlyphOnDark;
}
