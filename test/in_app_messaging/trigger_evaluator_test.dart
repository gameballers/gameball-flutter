import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/trigger_evaluator.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';

final DateTime t0 = DateTime.utc(2026, 8, 5, 12);

InAppMessageCampaign campaign(
  String id, {
  GameballMessageTrigger trigger = const GameballSessionStartTrigger(),
  int priority = 0,
  GameballMessageType type = GameballMessageType.modal,
}) {
  return InAppMessageCampaign(
    id: id,
    trigger: trigger,
    priority: priority,
    message: GameballInAppMessage(id: 'msg_$id', type: type, body: 'body'),
  );
}

const CapState emptyCaps =
    CapState(shownCampaignIds: <String>{}, lastDisplayAt: null);

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

      expect(result?.id, 'a');
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
        )?.id,
        'cart',
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

      expect(result?.id, 'high');
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

      expect(result?.id, 'c0');
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

      expect(result?.id, 'first_top');
    });
  });

  group('selectCampaign — caps', () {
    test('skips a campaign that has already been shown', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: const CapState(shownCampaignIds: {'a'}, lastDisplayAt: null),
        now: t0,
      );

      expect(result, isNull);
    });

    test('falls through to a lower-priority campaign when the top is spent', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('high', priority: 99), campaign('low', priority: 1)],
        capState: const CapState(shownCampaignIds: {'high'}, lastDisplayAt: null),
        now: t0,
      );

      expect(result?.id, 'low');
    });

    test('returns null just inside the floor', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: CapState(
          shownCampaignIds: const <String>{},
          lastDisplayAt: t0.subtract(const Duration(milliseconds: 29900)),
        ),
        now: t0,
      );

      expect(result, isNull);
    });

    test('returns a campaign just outside the floor', () {
      final result = selectCampaign(
        occurrence: const GameballSessionStartOccurrence(),
        campaigns: [campaign('a')],
        capState: CapState(
          shownCampaignIds: const <String>{},
          lastDisplayAt: t0.subtract(const Duration(milliseconds: 30100)),
        ),
        now: t0,
      );

      expect(result?.id, 'a');
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

      expect(result?.id, 'usable');
    });
  });

  group('isWithinFloor', () {
    test('is false when nothing has been displayed', () {
      expect(isWithinFloor(capState: emptyCaps, now: t0), isFalse);
    });

    test('is true immediately after a display', () {
      expect(
        isWithinFloor(
          capState: CapState(shownCampaignIds: const <String>{}, lastDisplayAt: t0),
          now: t0,
        ),
        isTrue,
      );
    });

    test('is false once the floor has elapsed exactly', () {
      expect(
        isWithinFloor(
          capState: CapState(
            shownCampaignIds: const <String>{},
            lastDisplayAt: t0.subtract(minimumIntervalBetweenDisplays),
          ),
          now: t0,
        ),
        isFalse,
      );
    });
  });
}
