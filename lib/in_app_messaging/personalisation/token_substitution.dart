import '../models/in_app_message.dart';

/// Matches `{token_name}` — a single brace pair around a bare identifier.
///
/// Deliberately strict. `{ spaced }`, `{2}` and a lone `{` are not tokens, and
/// treating them as such would let ordinary copy be mangled by a value map.
final RegExp _token = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Whether [message] carries anything worth fetching variables for.
///
/// Checked before the network call, so a message with no tokens costs nothing.
///
/// This used to be the check that kept the whole feature inert, because sync
/// substituted and no message arrived carrying a token. Sync no longer does, so
/// the guard now does the opposite job: it marks the messages that *cannot* be
/// displayed until [VariableSource] has answered.
bool messageHasTokens(GameballInAppMessage message) {
  return _hasToken(message.header) ||
      _hasToken(message.body) ||
      message.buttons.any((b) => _hasToken(b.text));
}

bool _hasToken(String? text) =>
    text != null && text.contains('{') && _token.hasMatch(text);

/// Every distinct `{token}` name appearing in [message]'s text.
///
/// Used to decide which values are worth keeping on the device. A campaign that
/// never mentions `{player_email}` gives the SDK no reason to store one, and the
/// less personal data sits at rest the better.
Set<String> tokensIn(GameballInAppMessage message) {
  final found = <String>{};
  for (final text in <String?>[
    message.header,
    message.body,
    ...message.buttons.map((b) => b.text),
  ]) {
    if (text == null || !text.contains('{')) continue;
    for (final match in _token.allMatches(text)) {
      found.add(match.group(1)!);
    }
  }
  return found;
}

/// Replaces every `{token}` in [text] that [values] knows.
///
/// A token with no matching key is **left exactly as written**, so a caller can
/// still tell resolved from unresolved. Nothing reaches a screen in that state:
/// [clearUnresolvedTokens] is the last step before display and empties whatever
/// is left.
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

/// [message] with every remaining `{token}` replaced by nothing.
///
/// The last step before a message is drawn, and it runs on **every** display
/// path — including the ones where [substituteInto] never got the chance, such
/// as a fetch that timed out. Nothing else guarantees that.
///
/// Blanking rather than suppressing is deliberate. Sync no longer substitutes,
/// so an unresolved token means the values call did not answer or did not know
/// the name — and both of those are backend problems, to be found and fixed
/// there. Withholding the campaign would hide the symptom and cost the customer
/// the message; rendering the brace would show them the SDK's internals. An
/// empty span does neither.
///
/// Substituting a sensible default instead is the better answer and is not this
/// function's to make: it needs per-token defaults the backend does not yet
/// send.
GameballInAppMessage clearUnresolvedTokens(GameballInAppMessage message) {
  if (!messageHasTokens(message)) return message;

  return message.withText(
    header: message.header == null ? null : _blankTokens(message.header!),
    body: message.body == null ? null : _blankTokens(message.body!),
    buttons: message.buttons
        .map((b) => b.withText(_blankTokens(b.text)))
        .toList(growable: false),
  );
}

String _blankTokens(String text) =>
    text.contains('{') ? text.replaceAll(_token, '') : text;
