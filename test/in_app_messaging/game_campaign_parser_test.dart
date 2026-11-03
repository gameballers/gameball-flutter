import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';

String sync(String entries) => '{"cooldownSeconds":30,"messages":[$entries]}';

/// A game entry exactly as the contract's worked example shapes one, including
/// the fields it says are present but meaningless.
const String wheelEntry = '''
{
  "campaignType": 2, "campaignId": 0, "variationId": 0, "dispatchId": null,
  "name": "Spin the Wheel", "priority": 0, "messageType": 2,
  "trigger": { "type": "session_start", "repeatable": true },
  "content": null, "locale": null, "localeCode": null,
  "expiresAt": null, "isTest": false,
  "gameCampaignId": 9645, "gameCampaignType": "wheel"
}''';

void main() {
  test('a game entry parses with no content of its own', () {
    final campaigns = parseSyncResponse(sync(wheelEntry)).campaigns;

    expect(campaigns, hasLength(1));
    final widget = campaigns.single.message.widget!;
    expect(widget.gameCampaignId, 9645);
    expect(widget.gameCampaignType, 'wheel');
    expect(widget.openDetail, 'details_wheel_9645');
  });

  test('a game entry is identified by its game id, never by campaignId 0', () {
    final campaign = parseSyncResponse(sync(wheelEntry)).campaigns.single;
    expect(campaign.key.id, 9645);
  });

  test('a game is named by its game id wherever it is logged', () {
    final campaign = parseSyncResponse(sync(wheelEntry)).campaigns.single;

    expect(campaign.label, 'game:9645 (Spin the Wheel)');
    expect(campaign.message.id, 'game:9645',
        reason: 'derived from campaignId and variationId, every game was '
            '"0/0"');
  });

  test('a game the parser skips is named by its game id', () {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message ?? '');
    addTearDown(() => debugPrint = original);

    parseSyncResponse(sync(wheelEntry.replaceFirst(
      '"trigger": { "type": "session_start", "repeatable": true }',
      '"trigger": { "type": "screen", "name": "cart", "repeatable": true }',
    )));

    expect(lines.where((l) => l.contains('game:9645')), isNotEmpty);
    expect(lines.where((l) => l.contains('campaign 0')), isEmpty);
  });

  test('an unknown campaignType is skipped, not coerced', () {
    final entry = wheelEntry.replaceFirst('"campaignType": 2', '"campaignType": 7');
    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
  });

  test('an unknown gameCampaignType is skipped', () {
    final entry = wheelEntry.replaceFirst(
        '"gameCampaignType": "wheel"', '"gameCampaignType": "roulette"');
    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
  });

  test('a game entry with no gameCampaignId is skipped', () {
    final entry = wheelEntry.replaceFirst('"gameCampaignId": 9645,', '');
    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
  });

  test('a message with null content is still dropped', () {
    // The exemption is keyed off campaignType, not off the fields being absent,
    // so a malformed message keeps failing for the right reason.
    final entry = wheelEntry
        .replaceFirst('"campaignType": 2', '"campaignType": 1')
        .replaceFirst('"campaignId": 0', '"campaignId": 2215');
    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
  });

  test('an ordinary message still parses alongside the new fork', () {
    const message = '''
{
  "campaignType": 1, "campaignId": 2215, "variationId": 206,
  "dispatchId": "d-1", "name": "Welcome", "priority": 100, "messageType": 2,
  "trigger": { "type": "session_start", "repeatable": false },
  "content": { "colors": { "background": "#FFFFFF" } },
  "locale": { "header": "Welcome back!" },
  "localeCode": "en", "expiresAt": null, "isTest": false
}''';
    final campaigns = parseSyncResponse(sync(message)).campaigns;

    expect(campaigns, hasLength(1));
    expect(campaigns.single.message.isWidget, isFalse);
    expect(campaigns.single.message.header, 'Welcome back!');
  });

  test('an entry with no campaignType is read as a message', () {
    // Older payloads, and anything the backend sends before the field is
    // universal. Defaulting to the kind that has always existed is safe;
    // defaulting to a game would try to open a campaign that is not there.
    const legacy = '''
{
  "campaignId": 2215, "messageType": 2,
  "trigger": { "type": "session_start", "repeatable": false },
  "content": {}, "locale": { "header": "Hello" }, "localeCode": "en"
}''';
    final campaigns = parseSyncResponse(sync(legacy)).campaigns;
    expect(campaigns, hasLength(1));
    expect(campaigns.single.message.isWidget, isFalse);
  });

  test('a screen-triggered game is skipped until screens are supported', () {
    final entry = wheelEntry.replaceFirst(
      '"trigger": { "type": "session_start", "repeatable": true }',
      '"trigger": { "type": "screen", "name": "cart", "repeatable": true }',
    );
    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
  });

  test('a fullscreen game is kept and marked fullscreen', () {
    // The earlier reading that fullscreen clips was an artefact of measuring a
    // 1.12-aspect box. A portrait screen is about 0.46, comfortably inside the
    // ratio at which the widget starts clipping; landscape is the case that is
    // not, and the presenter's orientation gate holds a campaign back there.
    final entry = wheelEntry.replaceFirst('"messageType": 2', '"messageType": 3');
    final campaigns = parseSyncResponse(sync(entry)).campaigns;

    expect(campaigns, hasLength(1));
    expect(campaigns.single.message.type, GameballMessageType.fullscreen);
    expect(campaigns.single.message.isWidget, isTrue);
  });

  test('a fullscreen *message* is unaffected', () {
    // The guard is for games only. Fullscreen messages have shipped and work.
    const message = '''
{
  "campaignType": 1, "campaignId": 2215, "messageType": 3,
  "trigger": { "type": "session_start", "repeatable": false },
  "content": { "colors": { "background": "#FFFFFF" } },
  "locale": { "header": "Poster" }, "localeCode": "en"
}''';
    expect(parseSyncResponse(sync(message)).campaigns, hasLength(1));
  });

  test('a modal game is kept', () {
    expect(parseSyncResponse(sync(wheelEntry)).campaigns, hasLength(1));
  });

  test('a game that asks for a slideup is skipped, and says so', () {
    // The backend sends 2 or 3 for a game. A slideup has no surface that hosts
    // one, so drawing it there left an invisible overlay up for good, with
    // every later message waiting behind it.
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message ?? '');
    addTearDown(() => debugPrint = original);

    final entry = wheelEntry.replaceFirst('"messageType": 2', '"messageType": 1');

    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
    expect(lines.where((l) => l.contains('game:9645') && l.contains('slideup')),
        isNotEmpty);
  });

  test('a game with Any conditions is kept and fires on either one', () {
    final entry = wheelEntry.replaceFirst(
      '"trigger": { "type": "session_start", "repeatable": true }',
      '"trigger": { "type": "event", "name": "purchase", "repeatable": true, '
          '"metadataLogicalOperator": "OR", "metadataFilters": ['
          '{ "metadataId": 1, "name": "price", "operator": "Greater", "value": 100 },'
          '{ "metadataId": 2, "name": "productId", "operator": "Equals", "value": "sku-1" }'
          '] }',
    );
    final game = parseSyncResponse(sync(entry)).campaigns.single;

    expect(
      triggerMatches(
        game.trigger,
        GameballCustomEventOccurrence.purchase(
            productId: 'sku-1', price: 20, currency: 'EGP'),
      ),
      isTrue,
      reason: 'the product matches even though the price does not',
    );
    expect(
      triggerMatches(
        game.trigger,
        GameballCustomEventOccurrence.purchase(
            productId: 'sku-2', price: 20, currency: 'EGP'),
      ),
      isFalse,
    );
  });

  group('a game reads its repeat rule from its trigger, as a message does', () {
    InAppMessageCampaign withTrigger(String trigger) =>
        parseSyncResponse(sync(wheelEntry.replaceFirst(
          '"trigger": { "type": "session_start", "repeatable": true }',
          '"trigger": $trigger',
        ))).campaigns.single;

    test('repeatable with a minimum interval', () {
      final game = withTrigger('{ "type": "session_start", "repeatable": true, '
          '"minIntervalSeconds": 120 }');

      expect(game.repeatable, isTrue);
      expect(game.minInterval, const Duration(seconds: 120));
    });

    test('a null interval is none, not a game default', () {
      // What every game entry carries today.
      final game = withTrigger('{ "type": "session_start", "repeatable": true, '
          '"minIntervalSeconds": null }');

      expect(game.repeatable, isTrue);
      expect(game.minInterval, isNull);
    });

    test('not repeatable is once ever', () {
      final game =
          withTrigger('{ "type": "session_start", "repeatable": false }');

      expect(game.repeatable, isFalse);
    });
  });
}
