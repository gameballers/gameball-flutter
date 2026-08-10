import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/trigger_evaluator.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';

final DateTime t0 = DateTime.utc(2026, 8, 5, 12);

/// Campaigns are keyed by the backend's numeric id now, but these tests read far
/// better with names. [idFor] hands out a stable id per label so an assertion can
/// still say `idFor('high')` rather than a number that means nothing.
final Map<String, int> _idsByLabel = <String, int>{};
int idFor(String label) =>
    _idsByLabel.putIfAbsent(label, () => 2000 + _idsByLabel.length);

InAppMessageCampaign campaign(
  String label, {
  GameballMessageTrigger trigger = const GameballSessionStartTrigger(),
  int priority = 0,
  GameballMessageType type = GameballMessageType.modal,
  DateTime? expiresAt,
  bool repeatable = false,
  Duration? minInterval,
}) {
  return InAppMessageCampaign(
    campaignId: idFor(label),
    trigger: trigger,
    priority: priority,
    expiresAt: expiresAt,
    repeatable: repeatable,
    minInterval: minInterval,
    message: GameballInAppMessage(
      id: '${idFor(label)}',
      type: type,
      body: 'body',
    ),
  );
}

const CapState emptyCaps = CapState();

/// A history in which each named campaign was last displayed at [at].
///
/// [withCooldown] is a flag rather than a nullable timestamp on purpose: taking
/// `DateTime?` and defaulting it with `??` silently turns an explicit null into
/// "now", which activates the global cooldown and suppresses every campaign — a
/// mistake made once already while writing these.
CapState shown(List<String> labels, {DateTime? at, bool withCooldown = false}) {
  final when = at ?? t0;
  return CapState(
    lastDisplayByCampaign: {for (final l in labels) idFor(l): when},
    lastDisplayAt: withCooldown ? when : null,
  );
}

void main() {
  group('selectCampaign — matching', () {
    test('returns null when there are no campaigns', () {
      expect(
        selectCampaign(
          occurrence: const GameballSessionStartOccurrence(),
          campaigns: const <InAppMessageCampaign>[],
          capState: emptyCaps,
          now: t0,
        ),
        isNull,
      );
    });

    test('selects a campaign whose trigger matches', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.campaignId,
        idFor('a'));
    });

    test('ignores campaigns triggered by a different type', () {
      final result = selectCampaign(
        occurrence: const GameballCustomEventOccurrence('add_to_cart'),
        campaigns: [campaign('a')],
        capState: emptyCaps,
        now: t0,
      );

      expect(result, isNull);
    });

    test('matches a custom event only on an exact name', () {
      final campaigns = [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ];

      expect(
        selectCampaign(
          occurrence: const GameballCustomEventOccurrence('add_to_cart'),
          campaigns: campaigns,
          capState: emptyCaps,
          now: t0,
        )?.campaignId,
        idFor('cart'),
      );
      expect(
        selectCampaign(
          occurrence: const GameballCustomEventOccurrence('checkout'),
          campaigns: campaigns,
          capState: emptyCaps,
          now: t0,
        ),
        isNull,
      );
    });
  });

  group('selectCampaign — priority', () {
    test('higher priority wins', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('low', priority: 1), campaign('high', priority: 99)],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.campaignId,
        idFor('high'));
    });

    test('ties break on response order, not sort order', () {
      // Dart's List.sort is NOT stable, so this must hold for a list long
      // enough to trip the unstable path.
      final campaigns = [
        for (var i = 0; i < 40; i++) campaign('c$i', priority: 5),
      ];

      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: campaigns,
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.campaignId,
        idFor('c0'));
    });

    test('the winner is the first of the top priority in response order', () {
      final campaigns = [
        campaign('mid', priority: 5),
        campaign('first_top', priority: 10),
        campaign('second_top', priority: 10),
      ];

      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: campaigns,
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.campaignId,
        idFor('first_top'));
    });
  });

  group('selectCampaign — caps', () {
    test('skips a campaign that has already been shown', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: shown(['a']),
        now: t0,
      );

      expect(result, isNull);
    });

    test('falls through to a lower-priority campaign when the top is spent', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('high', priority: 99), campaign('low', priority: 1)],
        capState: shown(['high']),
        now: t0,
      );

      expect(result?.campaignId,
        idFor('low'));
    });

    test('returns null just inside the floor', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: CapState(lastDisplayAt: t0.subtract(const Duration(milliseconds: 29900)),
        ),
        now: t0,
      );

      expect(result, isNull);
    });

    test('returns a campaign just outside the floor', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: CapState(lastDisplayAt: t0.subtract(const Duration(milliseconds: 30100)),
        ),
        now: t0,
      );

      expect(result?.campaignId,
        idFor('a'));
    });
  });

  group('selectCampaign — unsupported types', () {
    test('never selects an unsupported message type', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a', type: GameballMessageType.unsupported)],
        capState: emptyCaps,
        now: t0,
      );

      expect(result, isNull);
    });

    test('a supported lower-priority campaign wins over an unsupported top one', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [
          campaign('top', priority: 99, type: GameballMessageType.unsupported),
          campaign('usable', priority: 1),
        ],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.campaignId,
        idFor('usable'));
    });
  });

  group('isWithinFloor', () {
    test('is false when nothing has been displayed', () {
      expect(isWithinFloor(capState: emptyCaps, now: t0), isFalse);
    });

    test('is true immediately after a display', () {
      expect(
        isWithinFloor(
          capState: CapState(lastDisplayAt: t0),
          now: t0,
        ),
        isTrue,
      );
    });

    test('is false once the floor has elapsed exactly', () {
      expect(
        isWithinFloor(
          capState: CapState(lastDisplayAt: t0.subtract(defaultDisplayCooldown),
          ),
          now: t0,
        ),
        isFalse,
      );
    });
  });

  group('repeat rules', () {
    test('a non-repeatable campaign shown once is never eligible again', () {
      final c = campaign('once');

      expect(
        isRepeatEligible(campaign: c, capState: emptyCaps, now: t0),
        isTrue,
      );
      expect(
        isRepeatEligible(
          campaign: c,
          capState: shown(['once']),
          now: t0.add(const Duration(days: 365)),
        ),
        isFalse,
        reason: 'once ever means once ever, however long has passed',
      );
    });

    test('a repeatable campaign with no interval is eligible again at once', () {
      final c = campaign('again', repeatable: true);

      expect(
        isRepeatEligible(campaign: c, capState: shown(['again']), now: t0),
        isTrue,
        reason: 'minIntervalSeconds 0 means every matching occurrence',
      );
    });

    test('a repeatable campaign waits out its own interval', () {
      final c = campaign('hourly',
          repeatable: true, minInterval: const Duration(hours: 1));
      final history = shown(['hourly']);

      expect(
        isRepeatEligible(
            campaign: c,
            capState: history,
            now: t0.add(const Duration(minutes: 59))),
        isFalse,
      );
      expect(
        isRepeatEligible(
            campaign: c, capState: history, now: t0.add(const Duration(hours: 1))),
        isTrue,
        reason: 'the boundary is inclusive',
      );
    });

    test('the interval is that campaign own, not the global cooldown', () {
      final quick = campaign('quick',
          repeatable: true, minInterval: const Duration(seconds: 5));
      // Another campaign displayed much more recently.
      final history = CapState(
        lastDisplayByCampaign: {idFor('quick'): t0},
        lastDisplayAt: t0.add(const Duration(minutes: 10)),
      );

      expect(
        isRepeatEligible(
            campaign: quick,
            capState: history,
            now: t0.add(const Duration(minutes: 10))),
        isTrue,
        reason: 'its own interval elapsed; the global cooldown is a separate '
            'check in selectCampaign',
      );
    });

    test('selectCampaign honours a repeatable interval', () {
      final c = campaign('hourly',
          repeatable: true, minInterval: const Duration(hours: 1));

      expect(
        selectCampaign(
          occurrence: const GameballSessionStartOccurrence(),
          campaigns: [c],
          capState: shown(['hourly']),
          now: t0.add(const Duration(minutes: 30)),
        ),
        isNull,
      );
      expect(
        selectCampaign(
          occurrence: const GameballSessionStartOccurrence(),
          campaigns: [c],
          capState: shown(['hourly']),
          now: t0.add(const Duration(hours: 2)),
        )?.campaignId,
        idFor('hourly'),
      );
    });
  });

  group('expiry', () {
    test('an expired campaign is not selected', () {
      final c = campaign('gone', expiresAt: t0);

      expect(
        selectCampaign(
          occurrence: const GameballSessionStartOccurrence(),
          campaigns: [c],
          capState: emptyCaps,
          now: t0,
        ),
        isNull,
        reason: 'enforced on the device because campaigns outlive their sync — '
            'one fetched at 23:58 would otherwise fire all night',
      );
    });

    test('a lower-priority campaign wins when the top one has expired', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [
          campaign('expired', priority: 99, expiresAt: t0),
          campaign('live', priority: 1),
        ],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.campaignId, idFor('live'));
    });
  });
}
