import 'dart:ui' show Color, TextAlign;

/// Maximum buttons a modal renders. Extra buttons in the payload are dropped.
const int maxModalButtons = 2;

/// Supported in-app message layouts.
///
/// An unrecognised wire value parses to [unsupported] rather than defaulting to
/// a real layout. Braze's closed enum with a silent `slideup` fallback shipped
/// wrong message types twice — prefer an explicit unknown over a default that
/// lies.
enum GameballMessageType {
  /// A centred card over a dimmed background. Blocks the app until dismissed.
  modal,

  /// A banner at the top or bottom of the screen.
  ///
  /// Non-blocking: the app stays usable underneath, so it is the only type that
  /// does not demand a decision. It also carries no buttons — the whole surface
  /// is the tap target.
  slideup,

  /// Edge-to-edge, covering the app entirely.
  fullscreen,

  unsupported,
}

/// Which edge a slideup enters from and rests against.
enum GameballSlidePosition { top, bottom }

/// How a modal or fullscreen message arranges its image and copy.
///
/// **Currently inferred** from which content fields the campaign populated,
/// because nothing in the payload names it. Braze does not infer — it sends
/// `image_style`, `TOP` or `GRAPHIC` — and its Flutter SDK drops that field, which
/// is the lossiness this module exists not to inherit. Held on the model rather
/// than worked out in each widget so that when the backend sends the layout, one
/// line in the parser replaces the guess and nothing else changes.
enum GameballMessageLayout {
  /// Image above the copy, buttons beneath it. Braze's `TOP`.
  textWithImage,

  /// The image is the message: it fills the surface and buttons sit over it.
  /// Braze's `GRAPHIC`.
  imageOnly,
}

/// Which device orientations a fullscreen message may display in.
enum GameballMessageOrientation { portrait, landscape, any }

/// What a button does when tapped.
sealed class GameballClickAction {
  const GameballClickAction();
}

/// Closes the message and does nothing else.
final class GameballDismissAction extends GameballClickAction {
  const GameballDismissAction();
}

/// Opens [url], then closes the message.
final class GameballOpenUrlAction extends GameballClickAction {
  const GameballOpenUrlAction(this.url, {this.external = false});

  final String url;

  /// Whether to force an external browser rather than the platform default.
  final bool external;
}

/// Navigates to a named route in the host app, then closes the message.
///
/// Braze cannot express this: it has no handle on the host's router, so a
/// "deep link" there is a URI handed to the OS, which routes back into the app,
/// where native code must catch it and forward it to Dart over a channel the
/// integrator writes themselves. Because this SDK renders in Flutter and already
/// holds the host's navigator key, it can simply push the route — no URI scheme
/// to invent, no native code, no round trip.
final class GameballNavigateAction extends GameballClickAction {
  const GameballNavigateAction(this.route, {this.arguments});

  /// A route name the host registered, e.g. `/cart`.
  final String route;

  /// Passed through as the route's `arguments`.
  final Map<String, Object>? arguments;
}

/// Per-button colours. A null field means "use the host's theme".
class GameballButtonStyle {
  const GameballButtonStyle({this.backgroundColor, this.textColor, this.borderColor});

  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;
}

class GameballMessageButton {
  const GameballMessageButton({
    required this.id,
    required this.text,
    required this.action,
    this.style = const GameballButtonStyle(),
  });

  /// Stable identifier used for click analytics, and to pair a button's styling
  /// with its translated label.
  ///
  /// A string, because that is what the backend assigns (`"b1"`, `"cta"`) and
  /// because it survives translation: the same id appears in the untranslated
  /// styling and in every locale's labels. Braze instead requires a marketer to
  /// set positional `"0"` / `"1"` identifiers by hand, and reports nothing when
  /// they forget.
  final String id;
  final String text;
  final GameballClickAction action;
  final GameballButtonStyle style;

  /// The same button with different label text.
  ///
  /// Exists for personalisation, which rewrites labels just before display. The
  /// id is carried through deliberately: it is what click analytics report, and
  /// a substituted button that lost it would be unattributable.
  GameballMessageButton withText(String newText) => GameballMessageButton(
        id: id,
        text: newText,
        action: action,
        style: style,
      );
}

/// Message-level colours and alignment. A null field means "use the host's theme".
class GameballMessageStyle {
  const GameballMessageStyle({
    this.backgroundColor,
    this.headerColor,
    this.bodyColor,
    this.scrimColor,
    this.closeButtonColor,
    this.headerAlign,
    this.bodyAlign,
  });

  final Color? backgroundColor;
  final Color? headerColor;
  final Color? bodyColor;
  final Color? scrimColor;

  /// Colour of the close glyph. Braze's `close_btn_color`.
  ///
  /// Needed as its own field rather than borrowing the header colour: the close
  /// button can sit over artwork, where a colour chosen for text on the message
  /// background may be invisible.
  final Color? closeButtonColor;

  final TextAlign? headerAlign;
  final TextAlign? bodyAlign;
}

/// A single in-app message, ready to render.
///
/// Covers both of Braze's modal layouts. "Text (with Optional Image)" sets
/// [body]; "Image Only" sets [imageUrl] and leaves [header] and [body] null. At
/// least one of the three must be present — a message with nothing to render is
/// dropped at parse.
class GameballInAppMessage {
  const GameballInAppMessage({
    required this.id,
    required this.type,
    this.body,
    this.header,
    this.imageUrl,
    this.clickAction,
    this.showCloseButton = true,
    this.dismissOnScrimTap = true,
    this.autoDismissAfter,
    this.layout = GameballMessageLayout.textWithImage,
    this.orientation = GameballMessageOrientation.any,
    this.slidePosition = GameballSlidePosition.bottom,
    this.iconUrl,
    this.buttons = const <GameballMessageButton>[],
    this.extras = const <String, String>{},
    this.style = const GameballMessageStyle(),
  });

  final String id;
  final GameballMessageType type;

  /// Null for an image-only message.
  final String? body;

  final String? header;
  final String? imageUrl;

  /// What tapping the message itself does, as opposed to tapping a button.
  ///
  /// Null means the message is not tappable. Required in practice for an
  /// image-only layout, where the artwork is the only thing to act on.
  final GameballClickAction? clickAction;

  /// Whether to draw a close glyph. From the backend's `closeBehaviour`.
  final bool showCloseButton;

  /// Whether tapping the scrim outside the message dismisses it.
  ///
  /// Separate from [showCloseButton] because the backend's `closeBehaviour`
  /// distinguishes them (`button`, `swipe`, `both`), and because a campaign that
  /// offers neither would be undismissable — which the parser refuses to produce.
  final bool dismissOnScrimTap;

  /// Null means the message stays until the user dismisses it.
  final Duration? autoDismissAfter;

  /// How the image and copy are arranged. Applies to modal and fullscreen.
  ///
  /// See [GameballMessageLayout]: this is inferred today and should become a
  /// value the backend sends.
  final GameballMessageLayout layout;

  /// Which orientations a [GameballMessageType.fullscreen] may display in.
  ///
  /// A poster designed for portrait is not merely narrow in landscape — the copy
  /// baked into it becomes unreadable — so a campaign can insist. Ignored by the
  /// other types, which are small enough to work either way.
  final GameballMessageOrientation orientation;

  /// Which edge a [GameballMessageType.slideup] rests against. Ignored by other
  /// types.
  ///
  /// Defaults to the bottom, which is both Braze's default and the safer choice:
  /// a banner at the top competes with the status bar and whatever app-bar action
  /// sits underneath it.
  final GameballSlidePosition slidePosition;

  /// A small leading image, used by [GameballMessageType.slideup].
  ///
  /// Distinct from [imageUrl]: an icon is a fixed-size square beside the text,
  /// where [imageUrl] is artwork the layout sizes itself around. A slideup has
  /// room for the former and not the latter.
  final String? iconUrl;

  /// Up to [maxModalButtons] buttons. Always empty for a slideup, which has none.
  final List<GameballMessageButton> buttons;

  /// Arbitrary key-values from the campaign, for driving app behaviour without
  /// a client release.
  final Map<String, String> extras;

  final GameballMessageStyle style;

  /// The same message with different text.
  ///
  /// Deliberately narrow rather than a general `copyWith`: personalisation is the
  /// only thing that rewrites a parsed message, and it has no business changing
  /// the layout, the action, the artwork or the styling. A full copyWith would
  /// invite exactly that.
  GameballInAppMessage withText({
    String? header,
    String? body,
    List<GameballMessageButton>? buttons,
  }) =>
      GameballInAppMessage(
        id: id,
        type: type,
        body: body ?? this.body,
        header: header ?? this.header,
        imageUrl: imageUrl,
        clickAction: clickAction,
        showCloseButton: showCloseButton,
        dismissOnScrimTap: dismissOnScrimTap,
        autoDismissAfter: autoDismissAfter,
        layout: layout,
        orientation: orientation,
        slidePosition: slidePosition,
        iconUrl: iconUrl,
        buttons: buttons ?? this.buttons,
        extras: extras,
        style: style,
      );
}
