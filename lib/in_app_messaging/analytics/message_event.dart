import 'dart:math';

/// What happened to a message.
///
/// [wireName] is spelled out rather than derived from the enum identifier, so
/// renaming a Dart symbol can never silently change the wire format.
enum GameballMessageEventType {
  impression('impression'),
  click('click'),
  buttonClick('button_click'),
  dismiss('dismiss');

  const GameballMessageEventType(this.wireName);

  final String wireName;
}

/// One analytics event, shaped as the JSON the backend receives.
///
/// A value object rather than four method signatures on the analytics interface:
/// the payload is the thing both sides have to agree on, so it is worth one Dart
/// type that mirrors it field for field. Adding an event type then costs an enum
/// entry, not an interface change.
class GameballMessageEvent {
  GameballMessageEvent({
    required this.type,
    required this.campaignId,
    required this.messageId,
    required this.occurredAt,
    this.analyticsToken,
    this.buttonId,
    this.isTestSend = false,
    String? eventId,
  }) : eventId = eventId ?? uuidV4();

  /// Unique per event, generated on the device.
  ///
  /// Delivery is **at-least-once**: a batch can be accepted by the backend and
  /// then resent, if the process dies after the response but before the outbox
  /// bookkeeping is written. The backend must treat this as an idempotency key —
  /// without that, a kill at the wrong moment inflates impression counts.
  final String eventId;

  final GameballMessageEventType type;
  final String campaignId;
  final String messageId;

  /// When it happened on the device, not when it was sent.
  ///
  /// Events are buffered, and a send can be delayed for hours by a dead network,
  /// so the send time is not a usable substitute. Every conversion window and the
  /// per-calendar-day unique-impression rule are anchored to this value.
  final DateTime occurredAt;

  /// The opaque token the backend attached to this campaign at fetch time.
  ///
  /// Null when the campaign carried none — a stub campaign, or a backend that has
  /// not started sending them. [campaignId] and [messageId] then carry the
  /// correlation instead, which is enough for reporting but not for attributing a
  /// variant.
  final String? analyticsToken;

  /// Set only for [GameballMessageEventType.buttonClick].
  final int? buttonId;

  /// True when the campaign was a marketer's test send.
  final bool isTestSend;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'eventId': eventId,
      'event': type.wireName,
      'campaignId': campaignId,
      'messageId': messageId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      if (analyticsToken != null) 'analyticsToken': analyticsToken,
      if (buttonId != null) 'buttonId': buttonId,
      if (isTestSend) 'isTestSend': true,
    };
  }
}

/// A version-4 UUID, for event idempotency keys.
///
/// Hand-rolled rather than adding a dependency: the compatibility contract keeps
/// this package's dependency list unchanged, and a v4 UUID is sixteen random
/// bytes with two fixed nibbles.
String uuidV4() {
  final random = Random();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
