import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';

/// Parses a response captured from the live V4 endpoint, rather than one we
/// wrote to match our own reading of the contract.
///
/// Captured 2026-08-17 from
/// `POST api.alpha.gameball.app/api/v4.0/integrations/inapp-messages/sync`.
/// Every other parser test asserts against a fixture *we* authored, which proves
/// only that the parser agrees with our interpretation. This one proves it agrees
/// with the backend — and it is what caught `content.media` going unread.
///
/// **Assertions are derived from the payload, not hard-coded against it.** Alpha
/// is a live environment whose campaigns are edited by whoever is testing that
/// day; between writing this suite and running it, one campaign disappeared and
/// another appeared. A test pinned to campaign 2053 would have started failing
/// for a reason that says nothing about the parser. Reading the expectation out
/// of the raw JSON keeps the claim — "nothing the backend sent was lost" —
/// true whatever the dashboard holds.
void main() {
  final raw = File('test/fixtures/v4-sync-response.json').readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final rawMessages = (decoded['messages'] as List).cast<Map<String, dynamic>>();

  List<InAppMessageCampaign> parsed() => parseSyncResponse(raw).campaigns;

  InAppMessageCampaign byId(int id) =>
      parsed().firstWhere((c) => c.campaignId == id);

  test('no campaign the backend sent is dropped', () {
    expect(parsed(), hasLength(rawMessages.length),
        reason: 'a dropped campaign is a campaign the customer never sees, and '
            'the parser logs rather than throws — so silence is the failure mode');
  });

  test('the payload exercises all three rendered types', () {
    final types = parsed().map((c) => c.message.type).toSet();
    expect(
      types,
      containsAll(<GameballMessageType>[
        GameballMessageType.modal,
        GameballMessageType.slideup,
        GameballMessageType.fullscreen,
      ]),
      reason: 'until V4, alpha served only slideups, so two of the three '
          'renderers had never met real data',
    );
  });

  test('the cooldown comes from the response, not the client default', () {
    expect(parseSyncResponse(raw).cooldown,
        Duration(seconds: decoded['cooldownSeconds'] as int));
  });

  group('triggers', () {
    test('every event trigger keeps the name the backend sent', () {
      final events = rawMessages.where(
          (m) => (m['trigger'] as Map<String, dynamic>)['type'] == 'event');
      expect(events, isNotEmpty, reason: 'the fixture must exercise this path');

      for (final message in events) {
        final expected =
            (message['trigger'] as Map<String, dynamic>)['name'] as String;
        expect(
          byId(message['campaignId'] as int).trigger,
          isA<GameballCustomEventTrigger>()
              .having((t) => t.eventName, 'eventName', expected),
          reason: 'matching is by name; eventId is internal to the backend',
        );
      }
    });

    test('every session_start trigger parses as one', () {
      final starts = rawMessages.where((m) =>
          (m['trigger'] as Map<String, dynamic>)['type'] == 'session_start');
      expect(starts, isNotEmpty);

      for (final message in starts) {
        expect(byId(message['campaignId'] as int).trigger,
            isA<GameballSessionStartTrigger>());
      }
    });

    test('a repeatable campaign keeps its minimum interval', () {
      final repeatable = rawMessages.firstWhere(
        (m) => (m['trigger'] as Map<String, dynamic>)['minIntervalSeconds'] != null,
        orElse: () => <String, dynamic>{},
      );
      if (repeatable.isEmpty) {
        markTestSkipped('no repeatable campaign in the current payload');
        return;
      }

      final seconds = (repeatable['trigger'] as Map<String, dynamic>)
          ['minIntervalSeconds'] as int;
      final campaign = byId(repeatable['campaignId'] as int);

      expect(campaign.repeatable, isTrue);
      expect(campaign.minInterval, Duration(seconds: seconds));
    });
  });

  test('buttons keep their id and pair with the translated label', () {
    final withButtons = rawMessages.firstWhere(
      (m) => ((m['content'] as Map<String, dynamic>)['buttons'] as List?)
              ?.isNotEmpty ??
          false,
      orElse: () => <String, dynamic>{},
    );
    if (withButtons.isEmpty) {
      markTestSkipped('no campaign with buttons in the current payload');
      return;
    }

    final rawButton = ((withButtons['content'] as Map<String, dynamic>)['buttons']
        as List)[0] as Map<String, dynamic>;
    final rawLabel = ((withButtons['locale'] as Map<String, dynamic>)['buttons']
        as List)[0] as Map<String, dynamic>;

    final parsedButton =
        byId(withButtons['campaignId'] as int).message.buttons.single;

    expect(parsedButton.id, rawButton['id']);
    expect(parsedButton.text, rawLabel['text'],
        reason: 'styling and label arrive in separate halves, paired by id');
  });

  test('the live fullscreen campaign gets its artwork from media', () {
    final fullscreen = rawMessages.firstWhere(
      (m) => m['messageType'] == 3,
      orElse: () => <String, dynamic>{},
    );
    if (fullscreen.isEmpty) {
      markTestSkipped('no fullscreen campaign in the current payload');
      return;
    }

    final content = fullscreen['content'] as Map<String, dynamic>;
    final media = content['media'] as Map<String, dynamic>?;
    if (media == null || media['type'] != 'image') {
      markTestSkipped('the fullscreen campaign no longer carries image media');
      return;
    }

    // This campaign's imageUrl is null and its artwork lives only in
    // content.media. Before that field was read, the one fullscreen campaign on
    // alpha had no artwork at all — and with the prefetcher in place it would
    // have been passed over entirely rather than rendering blank.
    expect(content['imageUrl'], isNull);
    expect(byId(fullscreen['campaignId'] as int).message.imageUrl, media['url']);
  });

  test('the raw payload is carried through for the cache to store', () {
    expect(parseSyncResponse(raw).rawJson, raw);
  });
}
