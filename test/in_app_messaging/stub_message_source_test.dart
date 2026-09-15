import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/stub_message_source.dart';

void main() {
  const audience = CustomerAudience('customer-1');

  Future<List<InAppMessageCampaign>> load() async =>
      (await StubMessageSource().fetch(audience)).campaigns;

  test('every campaign in the fixture is displayable', () async {
    final campaigns = await load();

    expect(campaigns, isNotEmpty);
    for (final c in campaigns) {
      expect(c.message.type, GameballMessageType.modal,
          reason: 'campaign ${c.label} must not be an unsupported layout');
    }
  });

  test('the sync carries the cooldown the backend chose', () async {
    final result = await StubMessageSource().fetch(audience);

    expect(result.cooldown, const Duration(seconds: 30),
        reason: 'the fixture states it explicitly, so a parser that ignored '
            'cooldownSeconds would still pass by luck on the default');
  });

  test('there is a campaign for every trigger type the SDK supports', () async {
    final triggers = (await load()).map((c) => c.trigger);

    expect(triggers.whereType<GameballSessionStartTrigger>(), hasLength(2),
        reason: 'two, so the cold start shows one and the warm return the next');
    expect(triggers.whereType<GameballCustomEventTrigger>(), hasLength(4));
  });

  test('the two session-start campaigns have distinct priorities', () async {
    final sessionStart = (await load())
        .where((c) => c.trigger is GameballSessionStartTrigger)
        .toList();

    final priorities = sessionStart.map((c) => c.priority).toSet();
    expect(priorities, hasLength(2),
        reason: 'equal priorities would make which one shows first arbitrary');
  });

  group('purchases, which are events rather than a trigger type of their own', () {
    Future<List<InAppMessageCampaign>> purchaseCampaigns() async =>
        (await load())
            .where((c) =>
                c.trigger is GameballCustomEventTrigger &&
                (c.trigger as GameballCustomEventTrigger).eventName ==
                    gameballPurchaseEventName)
            .toList();

    test('there are two: any purchase, and one filtered on price', () async {
      final campaigns = await purchaseCampaigns();

      expect(campaigns, hasLength(2));
      final filtered = campaigns.where((c) =>
          (c.trigger as GameballCustomEventTrigger).filters.isNotEmpty);
      expect(filtered.single.trigger, isA<GameballCustomEventTrigger>());
      expect(
        (filtered.single.trigger as GameballCustomEventTrigger)
            .filters
            .single
            .property,
        'price',
      );
    });

    test('the filtered one outranks the unfiltered one', () async {
      final campaigns = await purchaseCampaigns();
      final filtered = campaigns.firstWhere((c) =>
          (c.trigger as GameballCustomEventTrigger).filters.isNotEmpty);
      final any = campaigns.firstWhere(
          (c) => (c.trigger as GameballCustomEventTrigger).filters.isEmpty);

      expect(filtered.priority, greaterThan(any.priority),
          reason: 'both match a purchase over 100, and the specific offer is the '
              'more interesting of the two');
    });
  });

  test('the fixture covers both modal layouts', () async {
    final messages = (await load()).map((c) => c.message);

    expect(messages.where((m) => m.body != null), isNotEmpty);
    final imageOnly = messages.singleWhere((m) => m.body == null);
    expect(imageOnly.header, isNull);
    expect(imageOnly.imageUrl, isNotNull);
    expect(imageOnly.clickAction, isA<GameballNavigateAction>(),
        reason: 'an image-only message needs an action or it does nothing');
  });

  test('the cart campaign filters on event metadata', () async {
    final trigger = (await load())
        .map((c) => c.trigger)
        .whereType<GameballCustomEventTrigger>()
        .firstWhere((t) => t.eventName == stubCartEventName);

    expect(trigger.filters.single.property, 'productId',
        reason: 'the metadata name has to survive parsing, or filtered '
            'campaigns are silently inert');
  });

  test('buttons are paired with their translated labels by id', () async {
    final welcome =
        (await load()).firstWhere((c) => c.campaignId == 2041).message;

    expect(welcome.buttons.map((b) => b.id), ['b1', 'b2']);
    expect(welcome.buttons.map((b) => b.text), ['Later', 'Redeem']);
  });

  test('every campaign carries a dispatch id for telemetry', () async {
    for (final c in await load()) {
      expect(c.dispatchId, isNotNull,
          reason: 'campaign ${c.label} could not be attributed to a variation');
    }
  });

  test('an injected payload replaces the fixture', () async {
    final source = StubMessageSource(json: '''
      {"messages": [
        {"campaignId": 7, "priority": 1, "messageType": 2,
         "trigger": {"type": "session_start"},
         "content": {}, "locale": {"message": "b"}}
      ]}
    ''');

    expect((await source.fetch(audience)).campaigns.single.campaignId, 7);
  });

  test('an unparseable injected payload yields no campaigns', () async {
    final result = await StubMessageSource(json: 'garbage').fetch(audience);

    expect(result.campaigns, isEmpty);
  });
}
