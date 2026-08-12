import 'dart:convert';
import 'dart:ui' show Color, TextAlign;

import '../iam_log.dart';
import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';
import '../models/property_filter.dart';
import 'message_source.dart';

/// Message types the backend can send, as its numeric enum.
///
/// Only [modal] is rendered. The rest are listed so an unsupported campaign is
/// logged by name rather than by number — "why didn't my slideup show" should be
/// answerable from the log alone.
const Map<int, String> _messageTypeNames = <int, String>{
  1: 'slideup',
  2: 'modal',
  3: 'fullscreen',
  4: 'htmlFullscreen',
  5: 'emailCapture',
};

const int _slideupMessageType = 1;
const int _modalMessageType = 2;

/// Parses a `bots/inapp/sync` response.
///
/// Never throws. The rule is: drop what can never work, keep-but-skip what a
/// future SDK version might support, and log every decision.
GameballSyncResult parseSyncResponse(String rawJson) {
  Object? decoded;
  try {
    decoded = jsonDecode(rawJson);
  } catch (error) {
    iamLog('sync parse failed: payload is not valid JSON ($error)');
    return const GameballSyncResult.empty();
  }

  if (decoded is! Map<String, dynamic>) {
    iamLog('sync parse failed: payload root is not an object');
    return const GameballSyncResult.empty();
  }

  // The bots envelope reports failure *inside a 200*, so the status code alone
  // never tells you whether a sync worked.
  final success = _asBool(decoded['success']);
  if (success == false) {
    iamLog('sync rejected by the backend: '
        '${_asString(decoded['errorMsg']) ?? 'no message'} '
        '(errorCode ${decoded['errorCode']})');
    return const GameballSyncResult.empty();
  }

  // Tolerated unwrapped for the fixture source and for any future endpoint that
  // returns the payload directly.
  final payload = decoded['response'] is Map<String, dynamic>
      ? decoded['response'] as Map<String, dynamic>
      : decoded;

  final messagesJson = payload['messages'];
  if (messagesJson is! List) {
    iamLog('sync parse failed: "messages" is missing or not a list');
    return const GameballSyncResult.empty();
  }

  final cooldownSeconds = _asInt(payload['cooldownSeconds']);
  final campaigns = <InAppMessageCampaign>[];
  for (final entry in messagesJson) {
    if (entry is! Map<String, dynamic>) {
      iamLog('campaign skipped: entry is not an object');
      continue;
    }
    final campaign = _parseCampaign(entry);
    if (campaign != null) {
      campaigns.add(campaign);
    }
  }

  return GameballSyncResult(
    campaigns: campaigns,
    cooldown: cooldownSeconds == null || cooldownSeconds < 0
        ? defaultDisplayCooldown
        : Duration(seconds: cooldownSeconds),
    rawJson: rawJson,
  );
}

InAppMessageCampaign? _parseCampaign(Map<String, dynamic> json) {
  final campaignId = _asInt(json['campaignId']);
  if (campaignId == null) {
    iamLog('campaign dropped: missing or non-numeric "campaignId"');
    return null;
  }
  final name = _asString(json['name']);
  final label = name == null ? '$campaignId' : '$campaignId ($name)';

  // Anything but the one mode we know how to render. Checked before the message,
  // because a future mode would make every field below mean something else.
  final contentMode = _asString(json['contentMode']);
  if (contentMode != null && contentMode.toLowerCase() != 'prerendered') {
    iamLog('campaign $label skipped: unsupported contentMode "$contentMode" '
        '(this SDK renders "prerendered" only)');
    return null;
  }

  final trigger = _parseTrigger(json['trigger'], label);
  if (trigger == null) {
    return null; // already logged
  }

  final message = _parseMessage(json, label, campaignId);
  if (message == null) {
    return null; // already logged
  }

  final triggerJson =
      json['trigger'] is Map<String, dynamic> ? json['trigger'] as Map<String, dynamic> : const <String, dynamic>{};
  final minIntervalSeconds = _asInt(triggerJson['minIntervalSeconds']);

  return InAppMessageCampaign(
    campaignId: campaignId,
    variationId: _asInt(json['variationId']),
    // Never validated beyond "is it a non-empty string": the id is opaque by
    // contract, so any check here would be this SDK asserting something about a
    // format it has no business knowing.
    dispatchId: _asString(json['dispatchId']),
    name: name,
    trigger: trigger,
    priority: _asInt(json['priority']) ?? 0,
    message: message,
    expiresAt: _parseUtcTimestamp(json['expiresAt'], label),
    isTest: _asBool(json['isTest']) ?? false,
    repeatable: _asBool(triggerJson['repeatable']) ?? false,
    minInterval: (minIntervalSeconds != null && minIntervalSeconds > 0)
        ? Duration(seconds: minIntervalSeconds)
        : null,
  );
}

GameballMessageTrigger? _parseTrigger(Object? json, String label) {
  if (json is! Map<String, dynamic>) {
    iamLog('campaign $label dropped: "trigger" is missing or not an object');
    return null;
  }

  final type = _asString(json['type'])?.toLowerCase();
  switch (type) {
    case 'session_start':
      return const GameballSessionStartTrigger();
    // `custom_event` accepted alongside the backend's `event` so the fixture
    // source and any older payload keep parsing.
    case 'event':
    case 'custom_event':
      final eventName = _asString(json['eventName']);
      if (eventName == null || eventName.isEmpty) {
        // The backend keys triggers on a numeric eventId and sends the name
        // alongside it. Without the name there is nothing to match a locally
        // logged event against — the id is meaningless on the device.
        iamLog('campaign $label dropped: event trigger has no "eventName" '
            '(eventId ${json['eventId']} cannot be resolved on the device)');
        return null;
      }
      final filters = _parseFilters(json['metadataFilters'] ?? json['filters'], label);
      if (filters == null) {
        return null; // a named filter was unusable; already logged
      }

      final logical = _asString(json['metadataLogicalOperator'])?.toLowerCase();
      if (logical != null && logical != 'and') {
        iamLog('campaign $label dropped: metadataLogicalOperator "$logical" is '
            'not supported (this SDK evaluates filters with AND)');
        return null;
      }

      return GameballCustomEventTrigger(eventName, filters: filters);
    default:
      // Expected steady state, not an edge case: the backend supports more
      // trigger types than this SDK version. Name both so "why didn't my
      // campaign fire" is answerable from the log alone.
      iamLog('campaign $label dropped: unsupported trigger type "$type" '
          '(this SDK supports session_start and event)');
      return null;
  }
}

/// Parses trigger property filters, or null when the campaign must be skipped.
///
/// A filter whose **property name is missing** skips the whole campaign: the
/// backend identifies metadata by a numeric id and sends the name alongside, and
/// a filter we cannot name is a filter we cannot evaluate. Dropping just that
/// filter would silently *widen* the campaign — showing a "spent over $100"
/// message to everyone — which is worse than not showing it.
///
/// A filter with an unusable **operator or value** is dropped individually, which
/// widens rather than narrows, because that is a content mistake in one field
/// rather than a contract mismatch.
List<GameballPropertyFilter>? _parseFilters(Object? json, String label) {
  if (json == null) return const <GameballPropertyFilter>[];
  if (json is! List) {
    iamLog('campaign $label: filters are not a list, ignoring');
    return const <GameballPropertyFilter>[];
  }

  final filters = <GameballPropertyFilter>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) {
      iamLog('campaign $label: filter skipped, entry is not an object');
      continue;
    }
    // Three spellings: the backend's agreed metadata name, whichever of the two
    // it ships as, and the fixture source's own. Costs one `??` and means the
    // parser does not care which lands.
    final property = _asString(entry['metadataKey']) ??
        _asString(entry['metadataName']) ??
        _asString(entry['property']);
    if (property == null || property.isEmpty) {
      iamLog('campaign $label dropped: filter has no metadata name '
          '(metadataId ${entry['metadataId']} cannot be resolved on the device)');
      return null;
    }
    final operator = _parseOperator(entry['operator']);
    if (operator == null) {
      iamLog('campaign $label: filter on "$property" dropped, '
          'unsupported operator "${entry['operator']}"');
      continue;
    }
    final value = entry['value'];
    if (value == null) {
      iamLog('campaign $label: filter on "$property" dropped, no "value"');
      continue;
    }
    filters.add(GameballPropertyFilter(
      property: property,
      operator: operator,
      value: value as Object,
    ));
  }
  return filters;
}

GameballFilterOperator? _parseOperator(Object? value) {
  return switch (_asString(value)?.toLowerCase()) {
    // `is` / `isnot` are the backend's spellings; the rest are ours and Braze's.
    'is' || 'equals' || 'eq' || '==' => GameballFilterOperator.equals,
    'isnot' || 'is_not' || 'not_equals' || 'ne' || '!=' =>
      GameballFilterOperator.notEquals,
    'greaterthan' || 'greater_than' || 'gt' || '>' =>
      GameballFilterOperator.greaterThan,
    'greaterthanorequal' || 'greater_than_or_equal' || 'gte' || '>=' =>
      GameballFilterOperator.greaterThanOrEqual,
    'lessthan' || 'less_than' || 'lt' || '<' => GameballFilterOperator.lessThan,
    'lessthanorequal' || 'less_than_or_equal' || 'lte' || '<=' =>
      GameballFilterOperator.lessThanOrEqual,
    'contains' => GameballFilterOperator.contains,
    _ => null,
  };
}

/// Builds the renderable message from a campaign's `content` and `locale`.
///
/// The backend separates untranslated styling from translated text, with buttons
/// appearing in both halves. Ours is one flat object, so this is where the two are
/// joined — buttons paired by id, and only those present on both sides kept.
GameballInAppMessage? _parseMessage(
  Map<String, dynamic> json,
  String label,
  int campaignId,
) {
  final content = json['content'] is Map<String, dynamic>
      ? json['content'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final locale = json['locale'] is Map<String, dynamic>
      ? json['locale'] as Map<String, dynamic>
      : const <String, dynamic>{};

  // No message id exists in this contract, so one is derived. It appears only in
  // local diagnostics; telemetry correlates on campaignId and dispatchId.
  final variationId = _asInt(json['variationId']);
  final id = variationId == null ? '$campaignId' : '$campaignId/$variationId';

  final typeNumber = _asInt(json['messageType']);
  final type = switch (typeNumber) {
    _slideupMessageType => GameballMessageType.slideup,
    _modalMessageType => GameballMessageType.modal,
    _ => GameballMessageType.unsupported,
  };
  if (type == GameballMessageType.unsupported) {
    final named = _messageTypeNames[typeNumber] ?? 'unknown';
    iamLog('campaign $label has messageType $typeNumber ($named) — kept, but '
        'this SDK version renders slideup and modal only');
  }

  // Two modal layouts exist: text with an optional image, and image only. So
  // text is not required — but something to render is.
  final header = _asString(locale['header']);
  final body = _asString(locale['message']) ?? _asString(locale['body']);
  final imageUrl = _asString(content['imageUrl']);
  final iconUrl = _asString(content['iconUrl']);
  final hasHeader = header != null && header.isNotEmpty;
  final hasBody = body != null && body.isNotEmpty;
  final hasImage = imageUrl != null && imageUrl.isNotEmpty;

  if (type == GameballMessageType.slideup) {
    // A slideup is one line of copy. An icon alone is not a message — unlike a
    // modal, where artwork can carry everything — because a 40-point square with
    // no words says nothing.
    if (!hasHeader && !hasBody) {
      iamLog('campaign $label dropped: a slideup needs text, and this one has '
          'none');
      return null;
    }
  } else if (!hasHeader && !hasBody && !hasImage) {
    iamLog('campaign $label dropped: no header, message or imageUrl — nothing '
        'to render');
    return null;
  }

  // Braze's slideup has none, and there is no room for them beside three lines of
  // text. Dropped loudly rather than silently, since a campaign that configured
  // them expected them to appear.
  var buttons = _parseButtons(content['buttons'], locale['buttons'], label);
  if (type == GameballMessageType.slideup && buttons.isNotEmpty) {
    iamLog('campaign $label: ${buttons.length} button(s) ignored — a slideup has '
        'no buttons; its whole surface is the tap target');
    buttons = const <GameballMessageButton>[];
  }

  final autoSeconds = _asNum(content['autoDismissSeconds']);
  final close = _parseCloseBehaviour(content['closeBehaviour'], label);

  return GameballInAppMessage(
    id: id,
    type: type,
    body: hasBody ? body : null,
    header: hasHeader ? header : null,
    imageUrl: hasImage ? imageUrl : null,
    // Message-level action: what tapping the message itself does. Optional, and
    // absent means the message is not tappable — so this is parsed leniently
    // rather than defaulting to dismiss the way a button's action does.
    clickAction: _parseOptionalAction(content['action'], label),
    showCloseButton: close.showCloseButton,
    dismissOnScrimTap: close.dismissOnScrimTap,
    autoDismissAfter: (autoSeconds != null && autoSeconds > 0)
        ? Duration(milliseconds: (autoSeconds * 1000).round())
        : null,
    slidePosition: _parseSlidePosition(content['slideFrom'], label),
    iconUrl: (iconUrl != null && iconUrl.isNotEmpty) ? iconUrl : null,
    buttons: buttons,
    extras: _parseExtras(content['extras']),
    style: _parseMessageStyle(content['colors'], content['textAlignment']),
  );
}

/// Which edge a slideup rests against.
///
/// Defaults to the bottom rather than the top: it is Braze's default, and a top
/// banner covers the status bar and whatever app-bar control sits under it.
GameballSlidePosition _parseSlidePosition(Object? value, String label) {
  switch (_asString(value)?.toLowerCase()) {
    case 'top':
      return GameballSlidePosition.top;
    case 'bottom':
    case null:
      return GameballSlidePosition.bottom;
    default:
      iamLog('campaign $label: unknown slideFrom "$value", using bottom');
      return GameballSlidePosition.bottom;
  }
}

/// How the message may be closed.
///
/// Defaults to offering both, and refuses to produce a message offering neither —
/// an undismissable modal traps the user in the app.
({bool showCloseButton, bool dismissOnScrimTap}) _parseCloseBehaviour(
  Object? value,
  String label,
) {
  switch (_asString(value)?.toLowerCase()) {
    case 'button':
      return (showCloseButton: true, dismissOnScrimTap: false);
    case 'swipe':
      return (showCloseButton: false, dismissOnScrimTap: true);
    case 'both':
    case null:
      return (showCloseButton: true, dismissOnScrimTap: true);
    default:
      iamLog('campaign $label: unknown closeBehaviour "$value", offering both');
      return (showCloseButton: true, dismissOnScrimTap: true);
  }
}

/// Joins styled buttons with their translated labels, pairing on id.
///
/// A button styled but not translated has no text to render; a button translated
/// but not styled has no action to perform. Either way it is dropped, which is the
/// backend's own rule: render only buttons present on both sides.
List<GameballMessageButton> _parseButtons(
  Object? contentJson,
  Object? localeJson,
  String label,
) {
  if (contentJson is! List) {
    return const <GameballMessageButton>[];
  }

  final labels = <String, String>{};
  if (localeJson is List) {
    for (final entry in localeJson) {
      if (entry is! Map<String, dynamic>) continue;
      final id = _asString(entry['id']);
      final text = _asString(entry['text']);
      if (id != null && id.isNotEmpty && text != null && text.isNotEmpty) {
        labels[id] = text;
      }
    }
  }

  final buttons = <GameballMessageButton>[];
  for (final entry in contentJson) {
    if (entry is! Map<String, dynamic>) {
      iamLog('campaign $label: button skipped, entry is not an object');
      continue;
    }
    final id = _asString(entry['id']);
    if (id == null || id.isEmpty) {
      iamLog('campaign $label: button dropped, missing "id" — there is no way '
          'to pair it with a label or report a click for it');
      continue;
    }
    // The fixture source carries text inline; the backend puts it in `locale`.
    final text = labels[id] ?? _asString(entry['text']);
    if (text == null || text.isEmpty) {
      iamLog('campaign $label: button "$id" dropped, no label for it in the '
          'locale block');
      continue;
    }
    buttons.add(GameballMessageButton(
      id: id,
      text: text,
      action: _parseAction(entry['action'], label),
      style: _parseButtonStyle(entry['colors'] ?? entry['style']),
    ));
  }

  if (buttons.length > maxModalButtons) {
    iamLog('campaign $label: ${buttons.length} buttons provided, keeping the '
        'first $maxModalButtons');
    return buttons.sublist(0, maxModalButtons);
  }
  return buttons;
}

/// Parses an ISO-8601 instant, normalised to UTC.
DateTime? _parseUtcTimestamp(Object? value, String label) {
  final raw = _asString(value);
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    iamLog('campaign $label: ignoring unparseable timestamp "$raw"');
    return null;
  }
  return parsed.toUtc();
}

GameballClickAction _parseAction(Object? json, String messageId) {
  if (json is! Map<String, dynamic>) {
    return const GameballDismissAction();
  }

  final type = _asString(json['type'])?.toLowerCase();
  switch (type) {
    case 'dismiss':
      return const GameballDismissAction();
    case 'open_url':
      final url = _asString(json['url']);
      if (url == null || url.isEmpty) {
        iamLog('message "$messageId": open_url action has no "url", using dismiss');
        return const GameballDismissAction();
      }
      return GameballOpenUrlAction(url, external: _asBool(json['external']) ?? false);
    case 'navigate':
      final navigate = _parseNavigate(json, messageId);
      if (navigate == null) return const GameballDismissAction();
      return navigate;
    default:
      // A working close beats a dead button.
      iamLog('message "$messageId": unsupported action type "$type", using dismiss');
      return const GameballDismissAction();
  }
}

/// Parses a `navigate` action, or null when it is unusable.
GameballNavigateAction? _parseNavigate(
  Map<String, dynamic> json,
  String messageId,
) {
  final route = _asString(json['route']);
  if (route == null || route.isEmpty) {
    iamLog('message "$messageId": navigate action has no "route"');
    return null;
  }

  final argsJson = json['arguments'];
  Map<String, Object>? arguments;
  if (argsJson is Map) {
    arguments = <String, Object>{};
    argsJson.forEach((key, value) {
      if (key is String && value != null) arguments![key] = value as Object;
    });
  }

  return GameballNavigateAction(route, arguments: arguments);
}

/// Parses the message-level action, where absent means "not tappable".
///
/// Deliberately stricter than [_parseAction]: a button must do *something* when
/// tapped, so an unusable action degrades to dismiss. A message surface that was
/// never meant to be tappable should simply not be — silently turning the whole
/// message into a close button would be worse than doing nothing.
GameballClickAction? _parseOptionalAction(Object? json, String messageId) {
  if (json == null) {
    return null;
  }
  if (json is! Map<String, dynamic>) {
    iamLog('message "$messageId": "action" is not an object, ignoring');
    return null;
  }

  final type = _asString(json['type'])?.toLowerCase();
  switch (type) {
    case 'dismiss':
      return const GameballDismissAction();
    case 'open_url':
      final url = _asString(json['url']);
      if (url == null || url.isEmpty) {
        iamLog('message "$messageId": message action open_url has no "url", '
            'leaving the message untappable');
        return null;
      }
      return GameballOpenUrlAction(url, external: _asBool(json['external']) ?? false);
    case 'navigate':
      // Null when unusable, which leaves the surface inert rather than making it
      // a close button — same reasoning as the other message-level cases.
      return _parseNavigate(json, messageId);
    default:
      iamLog('message "$messageId": unsupported message action type "$type", '
          'leaving the message untappable');
      return null;
  }
}

/// Per-button colours.
///
/// The backend's key names are read first, with ours accepted as aliases so the
/// fixture source and any hand-written payload keep working.
GameballButtonStyle _parseButtonStyle(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const GameballButtonStyle();
  }
  return GameballButtonStyle(
    backgroundColor: parseColor(json['background'] ?? json['backgroundColor']),
    textColor: parseColor(json['text'] ?? json['textColor']),
    borderColor: parseColor(json['border'] ?? json['borderColor']),
  );
}

/// Message-level colours and alignment, from the backend's two separate blocks.
///
/// `content.colors` carries `{background, text, header, closeButton, border,
/// frame}` and `content.textAlignment` carries `{header, body}`. `frame` has no
/// equivalent in a modal — it is the surround a fullscreen message draws — so it
/// is read as the scrim, which is the nearest thing a modal has.
GameballMessageStyle _parseMessageStyle(Object? colorsJson, Object? alignJson) {
  final colors = colorsJson is Map<String, dynamic>
      ? colorsJson
      : const <String, dynamic>{};
  final align =
      alignJson is Map<String, dynamic> ? alignJson : const <String, dynamic>{};

  return GameballMessageStyle(
    backgroundColor: parseColor(colors['background'] ?? colors['backgroundColor']),
    headerColor: parseColor(colors['header'] ?? colors['headerColor']),
    bodyColor: parseColor(colors['text'] ?? colors['bodyColor']),
    scrimColor: parseColor(colors['frame'] ?? colors['scrimColor']),
    closeButtonColor:
        parseColor(colors['closeButton'] ?? colors['closeButtonColor']),
    headerAlign: _parseAlign(align['header'] ?? align['headerAlign']),
    bodyAlign: _parseAlign(align['body'] ?? align['bodyAlign']),
  );
}

Map<String, String> _parseExtras(Object? json) {
  if (json is! Map) {
    return const <String, String>{};
  }
  final extras = <String, String>{};
  json.forEach((key, value) {
    if (key is String && value != null) {
      // Coerced rather than dropped. Braze silently discards non-string extras,
      // which loses campaign data with no diagnostic.
      extras[key] = value is String ? value : value.toString();
    }
  });
  return extras;
}

/// Parses a colour from a hex string (`#RRGGBB` or `#AARRGGBB`, hash optional)
/// or from a packed ARGB integer.
///
/// The integer form exists so a Braze-shaped payload still renders correctly —
/// Braze encodes colours as packed ARGB ints, and the backend may follow suit.
Color? parseColor(Object? value) {
  if (value is int) {
    return Color(value);
  }
  if (value is! String) {
    return null;
  }

  var hex = value.trim();
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  if (hex.length != 8) {
    iamLog('ignoring malformed colour "$value"');
    return null;
  }

  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    iamLog('ignoring malformed colour "$value"');
    return null;
  }
  return Color(parsed);
}

TextAlign? _parseAlign(Object? value) {
  return switch (_asString(value)?.toLowerCase()) {
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    'center' => TextAlign.center,
    'start' => TextAlign.start,
    'end' => TextAlign.end,
    _ => null,
  };
}

String? _asString(Object? value) => value is String ? value : null;

bool? _asBool(Object? value) => value is bool ? value : null;

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Kept separate from [_asInt] for durations, where a fractional second in the
/// payload should round rather than truncate to zero.
num? _asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}
