import 'package:flutter_test/flutter_test.dart';
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

  test('a fullscreen game is skipped until the surface is designed', () {
    // Measured: the widget sizes its wheel off viewport width, and a full-width
    // box clips its own copy. Skipped rather than drawn badly.
    final entry = wheelEntry.replaceFirst('"messageType": 2', '"messageType": 3');
    expect(parseSyncResponse(sync(entry)).campaigns, isEmpty);
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
}
