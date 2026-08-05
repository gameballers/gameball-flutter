import 'dart:ui' show Color, TextAlign;

/// Maximum buttons a modal renders. Extra buttons in the payload are dropped.
const int maxModalButtons = 2;

/// Supported in-app message layouts.
///
/// An unrecognised wire value parses to [unsupported] rather than defaulting to
/// a real layout. Braze's closed enum with a silent `slideup` fallback shipped
/// wrong message types twice — prefer an explicit unknown over a default that
/// lies.
enum GameballMessageType { modal, unsupported }

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

  /// Stable identifier used for click analytics.
  final int id;
  final String text;
  final GameballClickAction action;
  final GameballButtonStyle style;
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
    this.autoDismissAfter,
    this.isTestSend = false,
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

  final bool showCloseButton;

  /// Null means the message stays until the user dismisses it.
  final Duration? autoDismissAfter;

  /// True when this was delivered as a marketer's test send.
  final bool isTestSend;

  final List<GameballMessageButton> buttons;

  /// Arbitrary key-values from the campaign, for driving app behaviour without
  /// a client release.
  final Map<String, String> extras;

  final GameballMessageStyle style;
}
