import '../models/in_app_message.dart';

/// Matches `{token_name}` — a single brace pair around a bare identifier.
///
/// Deliberately strict. `{ spaced }`, `{2}` and a lone `{` are not tokens, and
/// treating them as such would let ordinary copy be mangled by a value map.
final RegExp _token = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Whether [message] carries anything worth fetching variables for.
///
/// Checked before the network call, so a message with no tokens — which today is
/// every message the backend serves, since it substitutes at sync — costs
/// nothing. This is the check that keeps the whole feature inert rather than
/// wrong while the contract question in O13 is open.
bool messageHasTokens(GameballInAppMessage message) {
  return _hasToken(message.header) ||
      _hasToken(message.body) ||
      message.buttons.any((b) => _hasToken(b.text));
}

bool _hasToken(String? text) =>
    text != null && text.contains('{') && _token.hasMatch(text);

/// Replaces every `{token}` in [text] that [values] knows.
///
/// A token with no matching key is **left exactly as written**. A newer server
/// may know tokens this SDK's map does not, and blanking them would silently
/// delete copy a marketer wrote.
///
/// One pass only: a substituted value is data, not a template, so a value that
/// happens to contain braces is never expanded again.
String substituteTokens(String text, Map<String, String> values) {
  if (values.isEmpty || !text.contains('{')) return text;
  return text.replaceAllMapped(_token, (match) {
    final name = match.group(1)!;
    return values[name] ?? match.group(0)!;
  });
}

/// [message] with its text personalised.
///
/// Applies to the header, the body and every button label. `html` and the
/// EmailCapture strings are skipped because those message types are not
/// rendered; when they are, this is the function they use.
GameballInAppMessage substituteInto(
  GameballInAppMessage message,
  Map<String, String> values,
) {
  if (values.isEmpty) return message;

  return message.withText(
    header: message.header == null
        ? null
        : substituteTokens(message.header!, values),
    body: message.body == null ? null : substituteTokens(message.body!, values),
    buttons: message.buttons
        .map((b) => b.withText(substituteTokens(b.text, values)))
        .toList(growable: false),
  );
}
