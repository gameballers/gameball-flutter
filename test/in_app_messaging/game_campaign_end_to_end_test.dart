import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/campaign_key.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';
import 'package:gameball_sdk/in_app_messaging/source/stub_message_source.dart';

void main() {
  test('a message and a game from one response both survive the parse', () {
    // One array carrying both kinds is the shape the contract's worked example
    // uses, and the case the kind fork exists to handle.
    final campaigns = parseSyncResponse(stubGameSyncJson).campaigns;

    expect(campaigns.map((c) => c.key), <CampaignKey>[
      const CampaignKey.message(2215),
      const CampaignKey.game(9645),
    ]);
    expect(campaigns.first.message.isWidget, isFalse);
    expect(campaigns.last.message.isWidget, isTrue);
  });

  test('the game sorts after the message on an equal trigger', () {
    // Ties keep the existing rule: priority, then array position. A game carries
    // priority 0 and is appended last, so a message with any real priority wins
    // and the game is deferred rather than dropped.
    final campaigns = parseSyncResponse(stubGameSyncJson).campaigns;

    expect(campaigns.first.priority, greaterThan(campaigns.last.priority));
  });

  test('the game opens the wheel it names', () {
    final game = parseSyncResponse(stubGameSyncJson).campaigns.last;

    expect(game.message.widget!.openDetail, 'details_wheel_9645');
  });

  test('the response carries the cooldown and quiet hours for both kinds', () {
    // The reason the two kinds share one array: these apply to everything in it.
    final result = parseSyncResponse(stubGameSyncJson);

    expect(result.cooldown, const Duration(seconds: 30));
    expect(result.quietHours, isNotNull);
  });
}
