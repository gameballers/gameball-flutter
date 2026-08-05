import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/stub_message_source.dart';

void main() {
  const audience = CustomerAudience('customer-1');

  Future<List<InAppMessageCampaign>> load() =>
      StubMessageSource().fetch(audience);

  test('every campaign in the fixture is displayable', () async {
    final campaigns = await load();

    expect(campaigns, isNotEmpty);
    for (final c in campaigns) {
      expect(c.message.type, GameballMessageType.modal,
          reason: 'campaign "${c.id}" must not be an unsupported layout');
    }
  });

  test('there is a campaign for every trigger type the SDK supports', () async {
    final triggers = (await load()).map((c) => c.trigger);

    expect(triggers.whereType<GameballSessionStartTrigger>(), hasLength(2),
        reason: 'two, so the cold start shows one and the warm return the next');
    expect(triggers.whereType<GameballCustomEventTrigger>(), isNotEmpty);
    expect(triggers.whereType<GameballAnyPurchaseTrigger>(), hasLength(1));
    expect(triggers.whereType<GameballSpecificPurchaseTrigger>(), hasLength(1));
  });

  test('the two session-start campaigns have distinct priorities', () async {
    final sessionStart = (await load())
        .where((c) => c.trigger is GameballSessionStartTrigger)
        .toList();

    final priorities = sessionStart.map((c) => c.priority).toSet();
    expect(priorities, hasLength(2),
        reason: 'equal priorities would make which one shows first arbitrary');
  });

  test('the specific-purchase campaign filters on price', () async {
    final trigger = (await load())
        .map((c) => c.trigger)
        .whereType<GameballSpecificPurchaseTrigger>()
        .single;

    expect(trigger.filters.single.property, 'price');
  });

  test('the specific-purchase campaign outranks the any-purchase one', () async {
    final campaigns = await load();
    final specific = campaigns
        .firstWhere((c) => c.trigger is GameballSpecificPurchaseTrigger);
    final any =
        campaigns.firstWhere((c) => c.trigger is GameballAnyPurchaseTrigger);

    expect(specific.priority, greaterThan(any.priority),
        reason: 'both match a purchase over 100, and the specific offer is the '
            'more interesting of the two');
  });

  test('the fixture covers both Braze modal layouts', () async {
    final messages = (await load()).map((c) => c.message);

    expect(messages.where((m) => m.body != null), isNotEmpty);
    final imageOnly = messages.singleWhere((m) => m.body == null);
    expect(imageOnly.header, isNull);
    expect(imageOnly.imageUrl, isNotNull);
    expect(imageOnly.clickAction, isA<GameballOpenUrlAction>(),
        reason: 'an image-only message needs an action or it does nothing');
  });

  test('the custom event trigger uses the documented event name', () async {
    final trigger = (await load())
        .map((c) => c.trigger)
        .whereType<GameballCustomEventTrigger>()
        .firstWhere((t) => t.eventName == stubCartEventName);

    expect(trigger.eventName, stubCartEventName);
  });

  test('an injected payload replaces the fixture', () async {
    final source = StubMessageSource(json: '''
      {"campaigns":[{"id":"only","priority":1,"trigger":{"type":"session_start"},
        "message":{"id":"m","type":"modal","body":"b"}}]}
    ''');

    expect((await source.fetch(audience)).single.id, 'only');
  });

  test('an unparseable injected payload yields no campaigns', () async {
    expect(await StubMessageSource(json: 'garbage').fetch(audience), isEmpty);
  });
}
