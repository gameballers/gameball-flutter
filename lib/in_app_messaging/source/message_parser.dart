import 'dart:convert';
import 'dart:ui' show Color, TextAlign;

import '../iam_log.dart';
import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';

/// Parses a message-source payload into campaigns.
///
/// Never throws. The rule is: drop what can never work, keep-but-skip what a
/// future SDK version might support, and log every decision.
List<InAppMessageCampaign> parseCampaignsJson(String rawJson) {
  Object? decoded;
  try {
    decoded = jsonDecode(rawJson);
  } catch (error) {
    iamLog('parse failed: payload is not valid JSON ($error)');
    return const <InAppMessageCampaign>[];
  }

  if (decoded is! Map<String, dynamic>) {
    iamLog('parse failed: payload root is not an object');
    return const <InAppMessageCampaign>[];
  }

  final campaignsJson = decoded['campaigns'];
  if (campaignsJson is! List) {
    iamLog('parse failed: "campaigns" is missing or not a list');
    return const <InAppMessageCampaign>[];
  }

  final campaigns = <InAppMessageCampaign>[];
  for (final entry in campaignsJson) {
    if (entry is! Map<String, dynamic>) {
      iamLog('campaign skipped: entry is not an object');
      continue;
    }
    final campaign = _parseCampaign(entry);
    if (campaign != null) {
      campaigns.add(campaign);
    }
  }
  return campaigns;
}

InAppMessageCampaign? _parseCampaign(Map<String, dynamic> json) {
  final id = _asString(json['id']);
  if (id == null || id.isEmpty) {
    iamLog('campaign dropped: missing "id"');
    return null;
  }

  final trigger = _parseTrigger(json['trigger'], id);
  if (trigger == null) {
    return null; // already logged
  }

  final messageJson = json['message'];
  if (messageJson is! Map<String, dynamic>) {
    iamLog('campaign "$id" dropped: "message" is missing or not an object');
    return null;
  }

  final message = _parseMessage(messageJson, id);
  if (message == null) {
    return null; // already logged
  }

  return InAppMessageCampaign(
    id: id,
    trigger: trigger,
    priority: _asInt(json['priority']) ?? 0,
    message: message,
  );
}

GameballMessageTrigger? _parseTrigger(Object? json, String campaignId) {
  if (json is! Map<String, dynamic>) {
    iamLog('campaign "$campaignId" dropped: "trigger" is missing or not an object');
    return null;
  }

  final type = _asString(json['type'])?.toLowerCase();
  switch (type) {
    case 'session_start':
      return const GameballSessionStartTrigger();
    case 'custom_event':
      final eventName = _asString(json['eventName']);
      if (eventName == null || eventName.isEmpty) {
        iamLog('campaign "$campaignId" dropped: custom_event trigger has no "eventName"');
        return null;
      }
      return GameballCustomEventTrigger(eventName);
    default:
      // Expected steady state, not an edge case: the backend supports more
      // trigger types than this SDK version. Name both so "why didn't my
      // campaign fire" is answerable from the log alone.
      iamLog('campaign "$campaignId" dropped: unsupported trigger type "$type" '
          '(this SDK supports session_start, custom_event)');
      return null;
  }
}

GameballInAppMessage? _parseMessage(Map<String, dynamic> json, String campaignId) {
  final id = _asString(json['id']);
  if (id == null || id.isEmpty) {
    iamLog('campaign "$campaignId" dropped: message has no "id"');
    return null;
  }

  // Braze's modal has two layouts: "Text (with Optional Image)" and
  // "Image Only". So text is not required — but something to render is.
  final header = _asString(json['header']);
  final body = _asString(json['body']);
  final imageUrl = _asString(json['imageUrl']);
  final hasHeader = header != null && header.isNotEmpty;
  final hasBody = body != null && body.isNotEmpty;
  final hasImage = imageUrl != null && imageUrl.isNotEmpty;
  if (!hasHeader && !hasBody && !hasImage) {
    iamLog('campaign "$campaignId" dropped: message "$id" has no "header", '
        '"body" or "imageUrl" — nothing to render');
    return null;
  }

  final typeName = _asString(json['type'])?.toLowerCase();
  final type = switch (typeName) {
    'modal' => GameballMessageType.modal,
    _ => GameballMessageType.unsupported,
  };
  if (type == GameballMessageType.unsupported) {
    iamLog('message "$id" has unsupported type "$typeName" — kept, but this SDK '
        'version will not display it');
  }

  final autoMs = _asInt(json['autoDismissAfterMs']);

  return GameballInAppMessage(
    id: id,
    type: type,
    body: hasBody ? body : null,
    header: hasHeader ? header : null,
    imageUrl: hasImage ? imageUrl : null,
    // Message-level action: what tapping the message itself does. Optional, and
    // absent means the message is not tappable — so this is parsed leniently
    // rather than defaulting to dismiss the way a button's action does.
    clickAction: _parseOptionalAction(json['action'], id),
    showCloseButton: _asBool(json['showCloseButton']) ?? true,
    autoDismissAfter:
        (autoMs != null && autoMs > 0) ? Duration(milliseconds: autoMs) : null,
    isTestSend: _asBool(json['isTestSend']) ?? false,
    buttons: _parseButtons(json['buttons'], id),
    extras: _parseExtras(json['extras']),
    style: _parseMessageStyle(json['style']),
  );
}

List<GameballMessageButton> _parseButtons(Object? json, String messageId) {
  if (json is! List) {
    return const <GameballMessageButton>[];
  }

  final buttons = <GameballMessageButton>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) {
      iamLog('message "$messageId": button skipped, entry is not an object');
      continue;
    }
    final text = _asString(entry['text']);
    if (text == null || text.isEmpty) {
      iamLog('message "$messageId": button dropped, missing "text"');
      continue;
    }
    buttons.add(GameballMessageButton(
      // Default to position so analytics still distinguishes buttons.
      id: _asInt(entry['id']) ?? buttons.length,
      text: text,
      action: _parseAction(entry['action'], messageId),
      style: _parseButtonStyle(entry['style']),
    ));
  }

  if (buttons.length > maxModalButtons) {
    iamLog('message "$messageId": ${buttons.length} buttons provided, keeping '
        'the first $maxModalButtons');
    return buttons.sublist(0, maxModalButtons);
  }
  return buttons;
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
    default:
      // A working close beats a dead button.
      iamLog('message "$messageId": unsupported action type "$type", using dismiss');
      return const GameballDismissAction();
  }
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
    default:
      iamLog('message "$messageId": unsupported message action type "$type", '
          'leaving the message untappable');
      return null;
  }
}

GameballButtonStyle _parseButtonStyle(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const GameballButtonStyle();
  }
  return GameballButtonStyle(
    backgroundColor: parseColor(json['backgroundColor']),
    textColor: parseColor(json['textColor']),
    borderColor: parseColor(json['borderColor']),
  );
}

GameballMessageStyle _parseMessageStyle(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const GameballMessageStyle();
  }
  return GameballMessageStyle(
    backgroundColor: parseColor(json['backgroundColor']),
    headerColor: parseColor(json['headerColor']),
    bodyColor: parseColor(json['bodyColor']),
    scrimColor: parseColor(json['scrimColor']),
    headerAlign: _parseAlign(json['headerAlign']),
    bodyAlign: _parseAlign(json['bodyAlign']),
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
