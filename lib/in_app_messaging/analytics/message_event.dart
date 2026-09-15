import 'dart:math';

/// What happened to a message.
///
/// [wireName] is spelled out rather than derived from the enum identifier, so
/// renaming a Dart symbol can never silently change the wire format.
///
/// There is deliberately no `buttonClick`: the backend's vocabulary is
/// `impression | click | dismiss | submit`, and a button tap is a [click]
/// carrying a `buttonId`. Presence of the id is the discriminator. `submit`
/// belongs to email-capture messages, which this SDK does not render.
enum GameballMessageEventType {
  impression('impression'),
  click('click'),
  dismiss('dismiss');

  const GameballMessageEventType(this.wireName);

  final String wireName;
}

/// One analytics event, shaped as the JSON the backend receives.
///
/// A value object rather than several method signatures on the analytics
/// interface: the payload is the thing both sides have to agree on, so it is worth
/// one Dart type that mirrors it field for field.
class GameballMessageEvent {
  GameballMessageEvent({
    required this.type,
    required this.campaignId,
    required this.occurredAt,
    this.variationId,
    this.dispatchId,
    this.buttonId,
    this.url,
    String? eventUid,
  }) : eventUid = eventUid ?? uuidV4();

  /// Unique per event, generated on the device.
  ///
  /// Delivery is **at-least-once**: a batch can be accepted and then resent if the
  /// process dies after the response but before the outbox bookkeeping is written.
  /// The backend deduplicates on this, so a kill at the wrong moment cannot
  /// inflate impression counts. Generated once per event and **never regenerated
  /// on retry** — that is the whole point of it.
  final String eventUid;

  final GameballMessageEventType type;

  /// The campaign this happened to.
  final int campaignId;

  /// Which A/B arm was displayed, when the campaign had more than one.
  final int? variationId;

  /// The campaign's opaque dispatch id, echoed verbatim.
  ///
  /// Null when the campaign carried none; [campaignId] then carries the
  /// correlation, which is enough for counting but not for attributing a variation.
  final String? dispatchId;

  /// When it happened on the device, not when it was sent.
  ///
  /// Events are buffered, and a send can be delayed for hours by a dead network,
  /// so send time is not a usable substitute. Conversion windows and the
  /// per-calendar-day unique-impression rule are both anchored to this.
  final DateTime occurredAt;

  /// Which button was tapped. Set only on a [GameballMessageEventType.click] that
  /// came from a button rather than the message surface.
  final String? buttonId;

  /// The destination, on a click whose action opened a URL.
  final String? url;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'eventUid': eventUid,
      'type': type.wireName,
      'campaignId': campaignId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      if (variationId != null) 'variationId': variationId,
      if (dispatchId != null) 'dispatchId': dispatchId,
      if (buttonId != null) 'buttonId': buttonId,
      if (url != null) 'url': url,
    };
  }
}

/// A version-4 UUID, for event idempotency keys.
///
/// Hand-rolled rather than adding a dependency: the compatibility contract keeps
/// this package's dependency list unchanged, and a v4 UUID is sixteen random bytes
/// with two fixed nibbles.
String uuidV4() {
  final random = Random();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
