import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/stub_message_source.dart';

void main() {
  const audience = CustomerAudience('customer-1');

  test('the built-in fixture parses into three usable campaigns', () async {
    final campaigns = await StubMessageSource().fetch(audience);

    expect(campaigns, hasLength(3));
    for (final c in campaigns) {
      expect(c.message.type, GameballMessageType.modal,
          reason: 'the fixture must only contain displayable messages');
    }
  });

  test('the fixture covers both supported trigger types', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final triggers = campaigns.map((c) => c.trigger);

    expect(triggers.whereType<GameballSessionStartTrigger>(), hasLength(1));
    expect(
      triggers.whereType<GameballCustomEventTrigger>().map((t) => t.eventName),
      containsAll(<String>[stubCartEventName, stubPromoEventName]),
    );
  });

  test('the fixture covers both Braze modal layouts', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final messages = campaigns.map((c) => c.message);

    // "Text (with Optional Image)"
    expect(messages.where((m) => m.body != null), isNotEmpty);
    // "Image Only" — no header, no body, tappable artwork
    final imageOnly = messages.singleWhere((m) => m.body == null);
    expect(imageOnly.header, isNull);
    expect(imageOnly.imageUrl, isNotNull);
    expect(imageOnly.clickAction, isA<GameballOpenUrlAction>(),
        reason: 'an image-only message needs an action or it does nothing');
  });

  test('the session-start campaign exercises header, image and two buttons', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final sessionStart = campaigns
        .firstWhere((c) => c.trigger is GameballSessionStartTrigger)
        .message;

    expect(sessionStart.header, isNotNull);
    expect(sessionStart.imageUrl, isNotNull);
    expect(sessionStart.buttons, hasLength(2));
    expect(sessionStart.buttons.map((b) => b.action).whereType<GameballOpenUrlAction>(),
        hasLength(1));
    expect(sessionStart.buttons.map((b) => b.action).whereType<GameballDismissAction>(),
        hasLength(1));
  });

  test('priorities are distinct so ordering is observable', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final priorities = campaigns.map((c) => c.priority).toSet();

    expect(priorities, hasLength(campaigns.length));
  });

  test('an injected payload replaces the fixture', () async {
    final source = StubMessageSource(json: '''
      {"campaigns":[{"id":"only","priority":1,"trigger":{"type":"session_start"},
        "message":{"id":"m","type":"modal","body":"b"}}]}
    ''');

    final campaigns = await source.fetch(audience);

    expect(campaigns.single.id, 'only');
  });

  test('an unparseable injected payload yields no campaigns', () async {
    final campaigns = await StubMessageSource(json: 'garbage').fetch(audience);

    expect(campaigns, isEmpty);
  });
}
