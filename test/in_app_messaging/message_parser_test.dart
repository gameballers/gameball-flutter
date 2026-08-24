import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/models/property_filter.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';

/// Wraps one or more campaigns in the plain payload the backend sends.
GameballSyncResult parse(String campaignsJson, {String payloadExtras = ''}) {
  return parseSyncResponse('{$payloadExtras"messages":[$campaignsJson]}');
}

/// The single campaign a payload produced, or null when it was dropped.
InAppMessageCampaign? one(String campaignJson) {
  final campaigns = parse(campaignJson).campaigns;
  return campaigns.isEmpty ? null : campaigns.single;
}

/// A campaign with only what the parser insists on, so each test adds just the
/// field it is about.
String minimal({
  int campaignId = 2041,
  String trigger = '{"type":"session_start"}',
  String content = '{}',
  String locale = '{"message":"body"}',
  String extras = '',
}) {
  return '''
  { "campaignId": $campaignId, "messageType": 2, $extras
    "trigger": $trigger, "content": $content, "locale": $locale }
  ''';
}

void main() {
  group('the payload root', () {
    test('reads messages from the root', () {
      expect(parse(minimal()).campaigns.single.campaignId, 2041);
    });

    test('takes cooldownSeconds from the root', () {
      final result = parse(minimal(), payloadExtras: '"cooldownSeconds": 90,');

      expect(result.cooldown, const Duration(seconds: 90));
    });

    test('falls back to the client default when cooldownSeconds is absent', () {
      expect(parse(minimal()).cooldown, const Duration(seconds: 30));
    });

    test('a bots-style wrapper is no longer unwrapped', () {
      // V4 sends a plain payload and reports failure with the status code. The
      // v1 and v4 paths are disjoint, so a wrapper can only reach here from a
      // misconfigured base URL — and reading it would hide that.
      final result = parseSyncResponse(
          '{"success":true,"response":{"cooldownSeconds":45,'
          '"messages":[${minimal()}]}}');

      expect(result.campaigns, isEmpty);
      expect(result.cooldown, const Duration(seconds: 30),
          reason: 'the client default, because "messages" is not at the root');
    });

    test('a payload that is not an object yields nothing', () {
      expect(parseSyncResponse('[]').campaigns, isEmpty);
    });

    test('invalid JSON yields nothing rather than throwing', () {
      expect(parseSyncResponse('not json').campaigns, isEmpty);
    });
  });

  group('happy path', () {
    test('parses a fully populated campaign', () {
      final campaign = one('''
        {
          "campaignId": 2041, "variationId": 4, "dispatchId": "d-abc",
          "name": "Welcome back", "priority": 100, "messageType": 2,
          "contentMode": "prerendered",
          "expiresAt": "2026-09-30T21:59:59Z", "isTest": false,
          "trigger": { "type": "session_start", "repeatable": true,
                       "minIntervalSeconds": 120 },
          "content": {
            "colors": { "background": "#FFFFFF", "header": "#111111",
                        "text": "#444444", "frame": "#99000000",
                        "closeButton": "#FEFEFE" },
            "textAlignment": { "header": "center", "body": "left" },
            "closeBehaviour": "both",
            "imageUrl": "https://cdn/hero.png",
            "autoDismissSeconds": 6,
            "extras": { "campaignSource": "q3" },
            "action": { "type": "navigate", "route": "/rewards" },
            "buttons": [
              { "id": "b1", "action": { "type": "dismiss" },
                "colors": { "background": "#EEEEEE", "text": "#111111",
                            "border": "#DDDDDD" } }
            ]
          },
          "locale": {
            "header": "Welcome back!", "message": "1,250 points waiting.",
            "buttons": [ { "id": "b1", "text": "Later" } ]
          }
        }
      ''')!;

      expect(campaign.campaignId, 2041);
      expect(campaign.variationId, 4);
      expect(campaign.dispatchId, 'd-abc');
      expect(campaign.name, 'Welcome back');
      expect(campaign.priority, 100);
      expect(campaign.repeatable, isTrue);
      expect(campaign.minInterval, const Duration(seconds: 120));
      expect(campaign.expiresAt, DateTime.utc(2026, 9, 30, 21, 59, 59));
      expect(campaign.isTest, isFalse);

      final message = campaign.message;
      expect(message.type, GameballMessageType.modal);
      expect(message.header, 'Welcome back!');
      expect(message.body, '1,250 points waiting.');
      expect(message.imageUrl, 'https://cdn/hero.png');
      expect(message.autoDismissAfter, const Duration(seconds: 6));
      expect(message.showCloseButton, isTrue);
      expect(message.dismissOnScrimTap, isTrue);
      expect(message.extras, {'campaignSource': 'q3'});
      expect(message.clickAction, isA<GameballNavigateAction>());
      expect(message.style.backgroundColor, const Color(0xFFFFFFFF));
      expect(message.style.headerColor, const Color(0xFF111111));
      expect(message.style.bodyColor, const Color(0xFF444444));
      expect(message.style.scrimColor, const Color(0x99000000));
      expect(message.style.closeButtonColor, const Color(0xFFFEFEFE));
      expect(message.style.headerAlign, TextAlign.center);
      expect(message.style.bodyAlign, TextAlign.left);
      expect(message.buttons.single.id, 'b1');
      expect(message.buttons.single.text, 'Later');
      expect(message.buttons.single.style.backgroundColor,
          const Color(0xFFEEEEEE));
    });

    test('a minimal campaign needs only an id, type, trigger and some text', () {
      final campaign = one(minimal())!;

      expect(campaign.message.body, 'body');
      expect(campaign.priority, 0);
      expect(campaign.repeatable, isFalse);
      expect(campaign.expiresAt, isNull);
      expect(campaign.dispatchId, isNull);
    });
  });

  group('the content and locale split', () {
    test('pairs buttons by id across the two blocks', () {
      final buttons = one(minimal(
        content: '''
          { "buttons": [ { "id": "b1", "action": {"type":"dismiss"} },
                         { "id": "b2", "action": {"type":"dismiss"} } ] }
        ''',
        locale: '''
          { "message": "body",
            "buttons": [ { "id": "b2", "text": "Second" },
                         { "id": "b1", "text": "First" } ] }
        ''',
      ))!.message.buttons;

      expect(buttons.map((b) => b.id), ['b1', 'b2'],
          reason: 'content order decides layout order, not locale order');
      expect(buttons.map((b) => b.text), ['First', 'Second']);
    });

    test('drops a styled button with no translated label', () {
      final buttons = one(minimal(
        content: '''
          { "buttons": [ { "id": "b1", "action": {"type":"dismiss"} },
                         { "id": "b2", "action": {"type":"dismiss"} } ] }
        ''',
        locale: '{"message":"body","buttons":[{"id":"b1","text":"Only"}]}',
      ))!.message.buttons;

      expect(buttons.map((b) => b.id), ['b1'],
          reason: 'a button with no text has nothing to render');
    });

    test('drops a button with no id, which could never be reported', () {
      final buttons = one(minimal(
        content: '{"buttons":[{"action":{"type":"dismiss"}}]}',
        locale: '{"message":"body","buttons":[{"id":"b1","text":"x"}]}',
      ))!.message.buttons;

      expect(buttons, isEmpty);
    });

    test('keeps the first two buttons when more are provided', () {
      final buttons = one(minimal(
        content: '''
          { "buttons": [ {"id":"b1","action":{"type":"dismiss"}},
                         {"id":"b2","action":{"type":"dismiss"}},
                         {"id":"b3","action":{"type":"dismiss"}} ] }
        ''',
        locale: '''
          { "message": "body", "buttons": [ {"id":"b1","text":"1"},
            {"id":"b2","text":"2"}, {"id":"b3","text":"3"} ] }
        ''',
      ))!.message.buttons;

      expect(buttons.map((b) => b.id), ['b1', 'b2']);
    });

    test('reads the message body from locale.message', () {
      expect(one(minimal(locale: '{"message":"from message"}'))!.message.body,
          'from message');
    });
  });

  group('messageType', () {
    test('2 is a modal', () {
      expect(one(minimal())!.message.type, GameballMessageType.modal);
    });

    test('1 is a slideup', () {
      final campaign = parse('''
        { "campaignId": 1, "messageType": 1,
          "trigger": {"type":"session_start"},
          "content": {}, "locale": {"message":"body"} }
      ''').campaigns.single;

      expect(campaign.message.type, GameballMessageType.slideup);
    });

    test('3 is a fullscreen', () {
      final campaign = parse('''
        { "campaignId": 1, "messageType": 3,
          "trigger": {"type":"session_start"},
          "content": {}, "locale": {"message":"body"} }
      ''').campaigns.single;

      expect(campaign.message.type, GameballMessageType.fullscreen);
    });

    for (final (number, name) in [
        (4, 'htmlFullscreen'), (5, 'emailCapture'), (99, 'unknown')]) {
      test('$number ($name) is kept as unsupported, not dropped', () {
        final campaign = parse('''
          { "campaignId": 1, "messageType": $number,
            "trigger": {"type":"session_start"},
            "content": {}, "locale": {"message":"body"} }
        ''').campaigns.single;

        expect(campaign.message.type, GameballMessageType.unsupported,
            reason: 'kept so the evaluator can skip it and let a usable '
                'lower-priority campaign win');
      });
    }
  });

  group('contentMode', () {
    test('prerendered is accepted', () {
      expect(one(minimal(extras: '"contentMode": "prerendered",')), isNotNull);
    });

    test('an absent mode is accepted', () {
      expect(one(minimal()), isNotNull);
    });

    test('an unknown mode drops the campaign', () {
      expect(one(minimal(extras: '"contentMode": "server_rendered",')), isNull,
          reason: 'a future mode would make every content field mean something '
              'else, so rendering it as if it were prerendered would be wrong');
    });
  });

  group('closeBehaviour', () {
    test('both offers the close button and the scrim', () {
      final m = one(minimal(content: '{"closeBehaviour":"both"}'))!.message;

      expect(m.showCloseButton, isTrue);
      expect(m.dismissOnScrimTap, isTrue);
    });

    test('button offers only the close button', () {
      final m = one(minimal(content: '{"closeBehaviour":"button"}'))!.message;

      expect(m.showCloseButton, isTrue);
      expect(m.dismissOnScrimTap, isFalse);
    });

    test('swipe offers only the scrim', () {
      final m = one(minimal(content: '{"closeBehaviour":"swipe"}'))!.message;

      expect(m.showCloseButton, isFalse);
      expect(m.dismissOnScrimTap, isTrue);
    });

    test('an absent or unknown value offers both', () {
      expect(one(minimal())!.message.showCloseButton, isTrue);
      final unknown =
          one(minimal(content: '{"closeBehaviour":"telepathy"}'))!.message;
      expect(unknown.showCloseButton, isTrue);
      expect(unknown.dismissOnScrimTap, isTrue,
          reason: 'a message offering no way out traps the user in the app');
    });
  });

  group('triggers', () {
    test('parses session_start', () {
      expect(one(minimal())!.trigger, isA<GameballSessionStartTrigger>());
    });

    test('parses an event trigger by name, ignoring the numeric id', () {
      final trigger = one(minimal(
        trigger: '{"type":"event","eventId":812,"name":"add_to_cart"}',
      ))!.trigger as GameballCustomEventTrigger;

      expect(trigger.eventName, 'add_to_cart');
    });

    test('accepts custom_event as an alias for event', () {
      final trigger = one(minimal(
        trigger: '{"type":"custom_event","name":"x"}',
      ))!.trigger as GameballCustomEventTrigger;

      expect(trigger.eventName, 'x');
    });

    test('drops an event trigger with only a numeric id', () {
      expect(
        one(minimal(trigger: '{"type":"event","eventId":812}')),
        isNull,
        reason: 'the id is meaningless on the device — there is nothing to match '
            'a locally logged event name against',
      );
    });

    test('drops an unknown trigger type', () {
      expect(one(minimal(trigger: '{"type":"push_click"}')), isNull);
    });

    test('drops a campaign with no trigger', () {
      expect(one('{"campaignId":1,"messageType":2,"locale":{"message":"b"}}'),
          isNull);
    });

    test('reads repeatable and minIntervalSeconds', () {
      final campaign = one(minimal(
        trigger: '{"type":"session_start","repeatable":true,'
            '"minIntervalSeconds":45}',
      ))!;

      expect(campaign.repeatable, isTrue);
      expect(campaign.minInterval, const Duration(seconds: 45));
    });

    test('treats a zero interval as none', () {
      final campaign = one(minimal(
        trigger: '{"type":"session_start","repeatable":true,'
            '"minIntervalSeconds":0}',
      ))!;

      expect(campaign.minInterval, isNull,
          reason: 'zero means every occurrence may display');
    });
  });

  group('metadata filters', () {
    GameballCustomEventTrigger? eventTrigger(String filters) {
      final campaign = one(minimal(
        trigger: '{"type":"event","name":"e","metadataFilters":$filters}',
      ));
      return campaign?.trigger as GameballCustomEventTrigger?;
    }

    test('reads the property name from metadataKey', () {
      final t = eventTrigger(
          '[{"metadataId":1,"name":"price","operator":"greaterThan",'
          '"value":100}]')!;

      expect(t.filters.single.property, 'price');
      expect(t.filters.single.operator, GameballFilterOperator.greaterThan);
      expect(t.filters.single.value, 100);
    });

    test('reads it from metadataName too, since the spelling was agreed verbally',
        () {
      final t = eventTrigger(
          '[{"metadataId":1,"name":"price","operator":"is",'
          '"value":"x"}]')!;

      expect(t.filters.single.property, 'price');
    });

    test('drops the whole campaign when a filter has no name', () {
      expect(
        eventTrigger('[{"metadataId":4051,"operator":"is","value":"x"}]'),
        isNull,
        reason: 'dropping only the filter would widen the campaign — showing a '
            '"spent over \$100" message to everyone — which is worse than not '
            'showing it at all',
      );
    });

    test('maps the backend operator names', () {
      expect(
        eventTrigger('[{"name":"a","operator":"Is","value":1}]')!
            .filters
            .single
            .operator,
        GameballFilterOperator.equals,
      );
      expect(
        eventTrigger('[{"name":"a","operator":"IsNot","value":1}]')!
            .filters
            .single
            .operator,
        GameballFilterOperator.notEquals,
      );
    });

    test('accepts our own operator aliases', () {
      for (final alias in ['equals', 'eq', '==']) {
        expect(
          eventTrigger('[{"name":"a","operator":"$alias","value":1}]')!
              .filters
              .single
              .operator,
          GameballFilterOperator.equals,
          reason: 'alias "$alias" should parse',
        );
      }
    });

    test('drops a filter with an unusable operator, widening the campaign', () {
      final t = eventTrigger(
          '[{"name":"a","operator":"sounds_like","value":1}]')!;

      expect(t.filters, isEmpty,
          reason: 'a typo in one operator should not hide the campaign entirely');
    });

    test('drops a filter with no value', () {
      expect(eventTrigger('[{"name":"a","operator":"is"}]')!.filters,
          isEmpty);
    });

    test('drops the campaign when the logical operator is not AND', () {
      final campaign = one(minimal(
        trigger: '{"type":"event","name":"e",'
            '"metadataLogicalOperator":"Or",'
            '"metadataFilters":[{"name":"a","operator":"is","value":1}]}',
      ));

      expect(campaign, isNull,
          reason: 'evaluating OR as AND would silently narrow the audience');
    });

    test('accepts an explicit And', () {
      expect(
        one(minimal(
          trigger: '{"type":"event","name":"e",'
              '"metadataLogicalOperator":"And",'
              '"metadataFilters":[{"name":"a","operator":"is","value":1}]}',
        )),
        isNotNull,
      );
    });
  });

  group('expiry', () {
    test('parses expiresAt as UTC', () {
      final campaign =
          one(minimal(extras: '"expiresAt": "2026-09-30T21:59:59Z",'))!;

      expect(campaign.expiresAt, DateTime.utc(2026, 9, 30, 21, 59, 59));
      expect(campaign.expiresAt!.isUtc, isTrue);
    });

    test('normalises a zoned timestamp to UTC', () {
      final campaign =
          one(minimal(extras: '"expiresAt": "2026-09-30T23:59:59+02:00",'))!;

      expect(campaign.expiresAt, DateTime.utc(2026, 9, 30, 21, 59, 59));
    });

    test('a null or unparseable expiry means no expiry', () {
      expect(one(minimal(extras: '"expiresAt": null,'))!.expiresAt, isNull);
      expect(one(minimal(extras: '"expiresAt": "soon",'))!.expiresAt, isNull);
    });

    test('hasExpiredAt is inclusive of the expiry instant', () {
      final campaign =
          one(minimal(extras: '"expiresAt": "2026-09-30T21:59:59Z",'))!;

      expect(campaign.hasExpiredAt(DateTime.utc(2026, 9, 30, 21, 59, 58)),
          isFalse);
      expect(campaign.hasExpiredAt(DateTime.utc(2026, 9, 30, 21, 59, 59)),
          isTrue);
    });
  });

  group('leniency', () {
    test('matches enum-ish values case-insensitively', () {
      final m = one(minimal(
        trigger: '{"type":"SESSION_START"}',
        content: '{"closeBehaviour":"BOTH","textAlignment":{"header":"CENTER"}}',
      ))!.message;

      expect(m.style.headerAlign, TextAlign.center);
    });

    test('accepts a colour as a packed ARGB int', () {
      final m = one(minimal(content: '{"colors":{"background":4294967295}}'))!
          .message;

      expect(m.style.backgroundColor, const Color(0xFFFFFFFF));
    });

    test('ignores a malformed colour', () {
      final m =
          one(minimal(content: '{"colors":{"background":"not-a-colour"}}'))!
              .message;

      expect(m.style.backgroundColor, isNull);
    });

    test('coerces non-string extras rather than dropping them', () {
      final m = one(minimal(
        content: '{"extras":{"count":3,"flag":true,"name":"x"}}',
      ))!.message;

      expect(m.extras, {'count': '3', 'flag': 'true', 'name': 'x'});
    });

    test('treats a non-positive autoDismissSeconds as no auto-dismiss', () {
      expect(one(minimal(content: '{"autoDismissSeconds":0}'))!
          .message
          .autoDismissAfter, isNull);
      expect(one(minimal(content: '{"autoDismissSeconds":-3}'))!
          .message
          .autoDismissAfter, isNull);
    });

    test('rounds a fractional autoDismissSeconds', () {
      expect(
        one(minimal(content: '{"autoDismissSeconds":1.5}'))!
            .message
            .autoDismissAfter,
        const Duration(milliseconds: 1500),
      );
    });

    test('degrades an unknown button action to dismiss', () {
      final button = one(minimal(
        content: '{"buttons":[{"id":"b1","action":{"type":"teleport"}}]}',
        locale: '{"message":"b","buttons":[{"id":"b1","text":"Go"}]}',
      ))!.message.buttons.single;

      expect(button.action, isA<GameballDismissAction>(),
          reason: 'a working close beats a dead button');
    });

    test('degrades open_url with no url to dismiss', () {
      final button = one(minimal(
        content: '{"buttons":[{"id":"b1","action":{"type":"open_url"}}]}',
        locale: '{"message":"b","buttons":[{"id":"b1","text":"Go"}]}',
      ))!.message.buttons.single;

      expect(button.action, isA<GameballDismissAction>());
    });
  });

  group('modal layouts', () {
    test('image-only: an imageUrl alone is enough, with no text', () {
      final m = one(minimal(
        content: '{"imageUrl":"https://cdn/promo.png"}',
        locale: '{}',
      ))!.message;

      expect(m.header, isNull);
      expect(m.body, isNull);
      expect(m.imageUrl, 'https://cdn/promo.png');
    });

    test('a header with no body is enough to render', () {
      expect(one(minimal(locale: '{"header":"Only a header"}'))!.message.header,
          'Only a header');
    });

    test('no message action means the surface is not tappable', () {
      expect(one(minimal())!.message.clickAction, isNull);
    });

    test('a message-level dismiss action is honoured', () {
      expect(one(minimal(content: '{"action":{"type":"dismiss"}}'))!
          .message
          .clickAction, isA<GameballDismissAction>());
    });

    test('an unusable message action leaves the surface untappable', () {
      expect(
        one(minimal(content: '{"action":{"type":"navigate"}}'))!
            .message
            .clickAction,
        isNull,
        reason: 'silently turning the whole message into a close button would be '
            'worse than doing nothing',
      );
    });

    test('the message action is independent of button actions', () {
      final m = one(minimal(
        content: '''
          { "action": {"type":"navigate","route":"/a"},
            "buttons": [{"id":"b1","action":{"type":"open_url",
                         "url":"https://b"}}] }
        ''',
        locale: '{"message":"b","buttons":[{"id":"b1","text":"Go"}]}',
      ))!.message;

      expect((m.clickAction! as GameballNavigateAction).route, '/a');
      expect((m.buttons.single.action as GameballOpenUrlAction).url,
          'https://b');
    });
  });

  group('drop what can never work', () {
    test('drops a campaign with no campaignId', () {
      expect(
        one('{"messageType":2,"trigger":{"type":"session_start"},'
            '"locale":{"message":"b"}}'),
        isNull,
      );
    });

    test('drops a campaign whose campaignId is not a number', () {
      expect(
        one('{"campaignId":"abc","messageType":2,'
            '"trigger":{"type":"session_start"},"locale":{"message":"b"}}'),
        isNull,
      );
    });

    test('drops a message with nothing to render', () {
      expect(one(minimal(locale: '{}')), isNull);
    });

    test('drops a message whose only text fields are empty strings', () {
      expect(one(minimal(locale: '{"header":"","message":""}')), isNull);
    });

    test('keeps valid campaigns alongside dropped ones', () {
      final campaigns = parse(
        '${minimal(campaignId: 1)},'
        '{"campaignId":2,"messageType":2,"trigger":{"type":"nope"},'
        '"locale":{"message":"b"}},'
        '${minimal(campaignId: 3)}',
      ).campaigns;

      expect(campaigns.map((c) => c.campaignId), [1, 3]);
    });
  });

  group('never throws', () {
    test('returns empty for invalid JSON', () {
      expect(parseSyncResponse('{oh no').campaigns, isEmpty);
    });

    test('returns empty when the root is not an object', () {
      expect(parseSyncResponse('[1,2,3]').campaigns, isEmpty);
    });

    test('returns empty when messages is missing', () {
      expect(parseSyncResponse('{"response":{}}').campaigns, isEmpty);
    });

    test('returns empty when messages is not a list', () {
      expect(
          parseSyncResponse('{"response":{"messages":"x"}}').campaigns, isEmpty);
    });

    test('skips non-object entries in messages', () {
      expect(parseSyncResponse('{"response":{"messages":[1,"x",null]}}')
          .campaigns, isEmpty);
    });
  });

  group('parseColor', () {
    test('parses 6-digit hex as fully opaque', () {
      expect(parseColor('#112233'), const Color(0xFF112233));
    });

    test('parses 8-digit hex with alpha', () {
      expect(parseColor('#80112233'), const Color(0x80112233));
    });

    test('parses hex without a leading hash', () {
      expect(parseColor('112233'), const Color(0xFF112233));
    });

    test('parses a packed ARGB int', () {
      expect(parseColor(4278190080), const Color(0xFF000000));
    });

    test('returns null for junk', () {
      expect(parseColor('nope'), isNull);
      expect(parseColor(null), isNull);
      expect(parseColor('#12345'), isNull);
    });
  });

  group('triggerMatches', () {
    test('matches session start to session start', () {
      expect(
        triggerMatches(const GameballSessionStartTrigger(),
            const GameballSessionStartOccurrence()),
        isTrue,
      );
    });

    test('matches events with the same name', () {
      expect(
        triggerMatches(const GameballCustomEventTrigger('a'),
            const GameballCustomEventOccurrence('a')),
        isTrue,
      );
    });

    test('does not match events with different names', () {
      expect(
        triggerMatches(const GameballCustomEventTrigger('a'),
            const GameballCustomEventOccurrence('b')),
        isFalse,
      );
    });

    test('does not match across trigger types', () {
      expect(
        triggerMatches(const GameballSessionStartTrigger(),
            const GameballCustomEventOccurrence('a')),
        isFalse,
      );
    });

    test('a filter narrows an otherwise matching name', () {
      const trigger = GameballCustomEventTrigger('cart', filters: [
        GameballPropertyFilter(
          property: 'value',
          operator: GameballFilterOperator.greaterThan,
          value: 100,
        ),
      ]);

      expect(
        triggerMatches(trigger,
            const GameballCustomEventOccurrence('cart',
                properties: {'value': 200})),
        isTrue,
      );
      expect(
        triggerMatches(trigger,
            const GameballCustomEventOccurrence('cart',
                properties: {'value': 50})),
        isFalse,
      );
    });

    test('a filter on a property the occurrence lacks never matches', () {
      const trigger = GameballCustomEventTrigger('cart', filters: [
        GameballPropertyFilter(
          property: 'missing',
          operator: GameballFilterOperator.equals,
          value: 1,
        ),
      ]);

      expect(
        triggerMatches(trigger, const GameballCustomEventOccurrence('cart')),
        isFalse,
      );
    });
  });

  group('purchases are events', () {
    test('a purchase occurrence matches an event trigger named purchase', () {
      final occurrence = GameballCustomEventOccurrence.purchase(
        productId: 'sku-1',
        price: 42.0,
        currency: 'USD',
      );

      expect(
        triggerMatches(
            const GameballCustomEventTrigger(gameballPurchaseEventName),
            occurrence),
        isTrue,
        reason: 'the backend has no purchase trigger type, so a purchase must '
            'satisfy an event trigger or purchase campaigns never fire',
      );
    });

    test('built-ins are filterable like any other property', () {
      final occurrence = GameballCustomEventOccurrence.purchase(
        productId: 'sku-1',
        price: 150.0,
        currency: 'USD',
        quantity: 2,
      );

      expect(occurrence.filterableProperties, {
        'productId': 'sku-1',
        'price': 150.0,
        'currency': 'USD',
        'quantity': 2,
      });

      const overHundred =
          GameballCustomEventTrigger(gameballPurchaseEventName, filters: [
        GameballPropertyFilter(
          property: 'price',
          operator: GameballFilterOperator.greaterThan,
          value: 100,
        ),
      ]);
      expect(triggerMatches(overHundred, occurrence), isTrue);
    });

    test('a caller property of the same name wins over a built-in', () {
      final occurrence = GameballCustomEventOccurrence.purchase(
        productId: 'sku-1',
        price: 10.0,
        currency: 'USD',
        properties: const {'price': 999},
      );

      expect(occurrence.filterableProperties['price'], 999,
          reason: 'the caller\'s data is the more specific of the two');
    });
  });

  group('slideup', () {
    String slideup({String content = '{}', String locale = '{"message":"hi"}'}) =>
        '{"campaignId":1,"messageType":1,"trigger":{"type":"session_start"},'
        '"content":$content,"locale":$locale}';

    test('reads slideFrom', () {
      expect(one(slideup(content: '{"slideFrom":"top"}'))!.message.slidePosition,
          GameballSlidePosition.top);
      expect(
          one(slideup(content: '{"slideFrom":"bottom"}'))!.message.slidePosition,
          GameballSlidePosition.bottom);
    });

    test('defaults to the bottom when slideFrom is absent or unknown', () {
      expect(one(slideup())!.message.slidePosition,
          GameballSlidePosition.bottom);
      expect(
          one(slideup(content: '{"slideFrom":"sideways"}'))!
              .message
              .slidePosition,
          GameballSlidePosition.bottom,
          reason: 'a top banner covers the status bar, so bottom is the safer '
              'fallback');
    });

    test('reads iconUrl, which is not the same slot as imageUrl', () {
      final message =
          one(slideup(content: '{"iconUrl":"https://cdn/i.png"}'))!.message;

      expect(message.iconUrl, 'https://cdn/i.png');
      expect(message.imageUrl, isNull);
    });

    test('drops buttons, loudly', () {
      final message = one(slideup(
        content: '{"buttons":[{"id":"b1","action":{"type":"dismiss"}}]}',
        locale: '{"message":"hi","buttons":[{"id":"b1","text":"Go"}]}',
      ))!.message;

      expect(message.buttons, isEmpty,
          reason: 'Braze has none either, and there is no room beside three '
              'lines of text — the whole surface is the tap target instead');
    });

    test('needs text: an icon alone is not a message', () {
      expect(
        one(slideup(content: '{"iconUrl":"https://cdn/i.png"}', locale: '{}')),
        isNull,
        reason: 'a 40-point square with no words says nothing. A modal can carry '
            'everything in artwork; a banner cannot',
      );
    });

    test('an image-only slideup is dropped even with an imageUrl', () {
      expect(
        one(slideup(content: '{"imageUrl":"https://cdn/big.png"}', locale: '{}')),
        isNull,
      );
    });

    test('accepts header as a fallback when message is absent', () {
      expect(one(slideup(locale: '{"header":"From the header"}'))!.message.header,
          'From the header');
    });

    test('keeps a message-level action, which is its only interaction', () {
      final action = one(slideup(
        content: '{"action":{"type":"navigate","route":"/offers"}}',
      ))!.message.clickAction;

      expect(action, isA<GameballNavigateAction>());
    });
  });

  group('layout, which the backend now names explicitly', () {
    String full({
      int messageType = 3,
      String content = '{}',
      String locale = '{"message":"hi"}',
    }) =>
        '{"campaignId":1,"messageType":$messageType,'
        '"trigger":{"type":"session_start"},'
        '"content":$content,"locale":$locale}';

    const image = '"imageUrl":"https://cdn/a.png"';

    test('a modal with no layout field renders the default', () {
      expect(one(full(messageType: 2, content: '{$image}'))!.message.layout,
          GameballMessageLayout.textWithImage);
    });

    test('a modal honours image_only', () {
      expect(
        one(full(messageType: 2, content: '{"layout":"image_only",$image}'))!
            .message
            .layout,
        GameballMessageLayout.imageOnly,
      );
    });

    test('a modal honours text_with_image', () {
      expect(
        one(full(
                messageType: 2,
                content: '{"layout":"text_with_image",$image}'))!
            .message
            .layout,
        GameballMessageLayout.textWithImage,
      );
    });

    test('a fullscreen honours image_and_text, its own default spelling', () {
      expect(
        one(full(content: '{"layout":"image_and_text",$image}'))!
            .message
            .layout,
        GameballMessageLayout.textWithImage,
        reason: 'modal and fullscreen spell the same arrangement differently',
      );
    });

    test('a fullscreen honours image_only', () {
      expect(
        one(full(content: '{"layout":"image_only",$image}'))!.message.layout,
        GameballMessageLayout.imageOnly,
      );
    });

    test('an unknown layout renders the default and keeps the message', () {
      final campaign =
          one(full(messageType: 2, content: '{"layout":"hologram",$image}'));

      expect(campaign, isNotNull,
          reason: 'layout is a rendering hint, not a contract — an unknown '
              'value must never cost the customer the message');
      expect(campaign!.message.layout, GameballMessageLayout.textWithImage);
    });

    test('absent copy no longer implies image-only', () {
      // This is O12, and the reason the inference had to go. A campaign whose
      // personalised copy resolved to empty was indistinguishable from one the
      // marketer deliberately made image-only, and alpha was already serving
      // "Welcome !" from an unresolved placeholder. The backend names the
      // layout now, so silence means the default.
      expect(
        one(full(messageType: 2, content: '{$image}', locale: '{}'))!
            .message
            .layout,
        GameballMessageLayout.textWithImage,
      );
    });

    test('imageStyle is no longer read', () {
      // A guess at what the backend might call the field, made before it had
      // named one. It chose `layout`, so this hedge is dead weight.
      expect(
        one(full(messageType: 2, content: '{"imageStyle":"GRAPHIC",$image}'))!
            .message
            .layout,
        GameballMessageLayout.textWithImage,
      );
    });

    test("Braze's own spellings are no longer read", () {
      expect(
        one(full(messageType: 2, content: '{"layout":"graphic",$image}'))!
            .message
            .layout,
        GameballMessageLayout.textWithImage,
        reason: 'this SDK follows the Gameball contract, not Braze wire format',
      );
    });
  });

  group('artwork, which fullscreen delivers as media', () {
    String withContent(String content, {int messageType = 3}) =>
        '{"campaignId":1,"messageType":$messageType,'
        '"trigger":{"type":"session_start"},'
        '"content":$content,"locale":{"header":"H","message":"B"}}';

    test('a fullscreen takes its artwork from media when imageUrl is null', () {
      final message = one(withContent(
          '{"imageUrl":null,"media":{"type":"image","url":"https://x/m.png"}}'))!
          .message;
      expect(message.imageUrl, 'https://x/m.png');
    });

    test('a fullscreen prefers media over imageUrl', () {
      final message = one(withContent(
          '{"imageUrl":"https://x/i.png",'
          '"media":{"type":"image","url":"https://x/m.png"}}'))!.message;
      expect(message.imageUrl, 'https://x/m.png',
          reason: 'the contract puts fullscreen artwork in media');
    });

    test('a modal prefers imageUrl over media', () {
      final message = one(withContent(
          '{"imageUrl":"https://x/i.png",'
          '"media":{"type":"image","url":"https://x/m.png"}}',
          messageType: 2))!.message;
      expect(message.imageUrl, 'https://x/i.png');
    });

    test('a modal still falls back to media', () {
      final message = one(withContent(
          '{"media":{"type":"image","url":"https://x/m.png"}}',
          messageType: 2))!.message;
      expect(message.imageUrl, 'https://x/m.png');
    });

    test('video media is ignored rather than drawn as a broken image', () {
      final message = one(withContent(
          '{"imageUrl":null,"media":{"type":"video","url":"https://x/v.mp4"}}'))!
          .message;
      expect(message.imageUrl, isNull);
    });

    test('a blank url is treated as absent', () {
      final message = one(withContent('{"imageUrl":"   ","media":null}',
          messageType: 2))!.message;
      expect(message.imageUrl, isNull,
          reason: 'an empty url would make the artwork prefetcher pass the '
              'whole campaign over, silently');
    });

    test('a blank icon url is treated as absent', () {
      final message = one(
          '{"campaignId":1,"messageType":1,'
          '"trigger":{"type":"session_start"},'
          '"content":{"iconUrl":"  "},"locale":{"message":"hi"}}')!.message;
      expect(message.iconUrl, isNull);
    });
  });

  group('the V4 payload has no envelope', () {
    test('a plain payload parses', () {
      const raw = '{"cooldownSeconds":45,"messages":[]}';
      expect(parseSyncResponse(raw).cooldown, const Duration(seconds: 45));
    });

    test('a bots-style wrapper is no longer unwrapped', () {
      // The v1 and v4 paths are disjoint, so a wrapper can only arrive from a
      // misconfigured base URL. Reading it would hide that.
      const raw =
          '{"success":true,"response":{"cooldownSeconds":45,"messages":[]}}';
      final result = parseSyncResponse(raw);

      expect(result.campaigns, isEmpty);
      expect(result.cooldown, const Duration(seconds: 30),
          reason: 'the client default, because "messages" is not at the root');
    });
  });

  group('orientation', () {
    String full({String content = '{}'}) =>
        '{"campaignId":1,"messageType":3,"trigger":{"type":"session_start"},'
        '"content":$content,"locale":{"message":"hi"}}';

    test('reads portrait and landscape', () {
      expect(one(full(content: '{"orientation":"portrait"}'))!.message.orientation,
          GameballMessageOrientation.portrait);
      expect(
          one(full(content: '{"orientation":"landscape"}'))!.message.orientation,
          GameballMessageOrientation.landscape);
    });

    test('defaults to any when absent or unknown', () {
      expect(one(full())!.message.orientation, GameballMessageOrientation.any);
      expect(one(full(content: '{"orientation":"sideways"}'))!.message.orientation,
          GameballMessageOrientation.any,
          reason: 'suppressing a message over an unrecognised value would be '
              'worse than showing it');
    });
  });

  group('quiet hours', () {
    test('are read from the response root', () {
      final result = parseSyncResponse('''
{
  "cooldownSeconds": 60,
  "quietHours": {"enabled": true, "start": "22:00", "end": "08:00"},
  "messages": []
}
''');

      expect(result.quietHours, isNotNull);
      expect(result.quietHours!.startMinute, 22 * 60);
      expect(result.quietHours!.endMinute, 8 * 60);
    });

    test('a response without them has none', () {
      final result = parseSyncResponse('{"cooldownSeconds": 60, "messages": []}');

      expect(result.quietHours, isNull);
    });

    test('a null block has none', () {
      final result = parseSyncResponse(
          '{"quietHours": null, "cooldownSeconds": 60, "messages": []}');

      expect(result.quietHours, isNull);
    });
  });

  group('a slideup always has a way out', () {
    String slideupPayload({String extra = ''}) => '''
{
  "cooldownSeconds": 60,
  "messages": [
    {
      "campaignId": 2041, "messageType": 1,
      "trigger": {"type": "session_start"},
      "content": {$extra},
      "locale": {"message": "New slideup A"}
    }
  ]
}
''';

    test('one with no close behaviour and no duration gets the default', () {
      // Campaigns 2041, 2042 and 2046 on the live account are exactly this.
      // A slideup never draws a close glyph and has no scrim, so without a
      // duration the only exit is a swipe gesture nobody is told about — and it
      // sits on the host's app bar until then. Braze cannot express this state:
      // its `message_close` defaults to `auto_dismiss`.
      final message = parseSyncResponse(slideupPayload()).campaigns.single.message;

      expect(message.autoDismissAfter, defaultSlideupAutoDismiss);
    });

    test('an explicit duration is never overridden', () {
      final message = parseSyncResponse(
        slideupPayload(extra: '"autoDismissSeconds": 8'),
      ).campaigns.single.message;

      expect(message.autoDismissAfter, const Duration(seconds: 8));
    });

    test('an explicit zero is honoured as "no auto-dismiss"', () {
      // Zero is a deliberate "stay until dismissed", so the default must not
      // quietly reinstate a timer the author turned off.
      final message = parseSyncResponse(
        slideupPayload(extra: '"autoDismissSeconds": 0'),
      ).campaigns.single.message;

      expect(message.autoDismissAfter, isNull);
    });

    test('a modal is left alone — it has a close glyph and a scrim', () {
      final message = parseSyncResponse('''
{
  "messages": [
    {
      "campaignId": 2052, "messageType": 2,
      "trigger": {"type": "session_start"},
      "content": {},
      "locale": {"message": "body"}
    }
  ]
}
''').campaigns.single.message;

      expect(message.autoDismissAfter, isNull);
    });
  });
}
