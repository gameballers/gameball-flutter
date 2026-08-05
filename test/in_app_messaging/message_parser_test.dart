import 'dart:ui' show Color, TextAlign;

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/models/property_filter.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';

/// Builds a payload with one campaign, letting each test override just the
/// fields it cares about.
String payload({String campaigns = _oneModalCampaign}) => '{"campaigns":[$campaigns]}';

const _oneModalCampaign = '''
{
  "id": "cmp_a",
  "priority": 10,
  "trigger": { "type": "session_start" },
  "message": { "id": "msg_a", "type": "modal", "body": "hello" }
}
''';

void main() {
  group('parseCampaignsJson — happy path', () {
    test('parses a minimal modal campaign', () {
      final campaigns = parseCampaignsJson(payload());

      expect(campaigns, hasLength(1));
      final c = campaigns.single;
      expect(c.id, 'cmp_a');
      expect(c.priority, 10);
      expect(c.trigger, isA<GameballSessionStartTrigger>());
      expect(c.message.id, 'msg_a');
      expect(c.message.type, GameballMessageType.modal);
      expect(c.message.body, 'hello');
      expect(c.message.showCloseButton, isTrue);
      expect(c.message.autoDismissAfter, isNull);
      expect(c.message.isTestSend, isFalse);
      expect(c.message.buttons, isEmpty);
    });

    test('parses a fully populated campaign', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        {
          "id": "cmp_full",
          "priority": 100,
          "trigger": { "type": "custom_event", "eventName": "add_to_cart" },
          "message": {
            "id": "msg_full",
            "type": "modal",
            "header": "Welcome",
            "body": "You have points",
            "imageUrl": "https://cdn.example.com/a.png",
            "showCloseButton": false,
            "autoDismissAfterMs": 4000,
            "isTestSend": true,
            "buttons": [
              { "id": 7, "text": "Go", "action": { "type": "open_url", "url": "app://x", "external": true },
                "style": { "backgroundColor": "#6C4DF6", "textColor": "#FFFFFF", "borderColor": "#000000" } }
            ],
            "style": { "backgroundColor": "#FFFFFF", "headerColor": "#111111",
                       "bodyColor": "#444444", "scrimColor": "#99000000",
                       "headerAlign": "center", "bodyAlign": "start" },
            "extras": { "source": "q3" }
          }
        }
      '''));

      final m = campaigns.single.message;
      expect(campaigns.single.trigger,
          isA<GameballCustomEventTrigger>().having((t) => t.eventName, 'eventName', 'add_to_cart'));
      expect(m.header, 'Welcome');
      expect(m.imageUrl, 'https://cdn.example.com/a.png');
      expect(m.showCloseButton, isFalse);
      expect(m.autoDismissAfter, const Duration(milliseconds: 4000));
      expect(m.isTestSend, isTrue);
      expect(m.extras, {'source': 'q3'});
      expect(m.style.backgroundColor, const Color(0xFFFFFFFF));
      expect(m.style.scrimColor, const Color(0x99000000));
      expect(m.style.headerAlign, TextAlign.center);
      expect(m.style.bodyAlign, TextAlign.start);

      final b = m.buttons.single;
      expect(b.id, 7);
      expect(b.text, 'Go');
      expect(b.style.backgroundColor, const Color(0xFF6C4DF6));
      final action = b.action;
      expect(action, isA<GameballOpenUrlAction>());
      action as GameballOpenUrlAction;
      expect(action.url, 'app://x');
      expect(action.external, isTrue);
    });
  });

  group('parseCampaignsJson — leniency', () {
    test('matches enum-ish values case-insensitively', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "SESSION_START" },
          "message": { "id": "m", "type": "MODAL", "body": "b",
                       "buttons": [ { "text": "x", "action": { "type": "DISMISS" } } ] } }
      '''));

      expect(campaigns.single.message.type, GameballMessageType.modal);
      expect(campaigns.single.trigger, isA<GameballSessionStartTrigger>());
      expect(campaigns.single.message.buttons.single.action, isA<GameballDismissAction>());
    });

    test('accepts a colour as a packed ARGB int', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "style": { "backgroundColor": 4294967295 } } }
      '''));

      expect(campaigns.single.message.style.backgroundColor, const Color(0xFFFFFFFF));
    });

    test('coerces non-string extras rather than dropping them', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "extras": { "n": 42, "b": true, "s": "x" } } }
      '''));

      expect(campaigns.single.message.extras, {'n': '42', 'b': 'true', 's': 'x'});
    });

    test('keeps the first two buttons when more are provided', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "one", "action": { "type": "dismiss" } },
            { "text": "two", "action": { "type": "dismiss" } },
            { "text": "three", "action": { "type": "dismiss" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.map((b) => b.text), ['one', 'two']);
    });

    test('defaults a button id to its position when absent', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "one", "action": { "type": "dismiss" } },
            { "text": "two", "action": { "type": "dismiss" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.map((b) => b.id), [0, 1]);
    });

    test('degrades an unknown action type to dismiss', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "x", "action": { "type": "send_telepathy" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.single.action, isA<GameballDismissAction>());
    });

    test('degrades open_url with no url to dismiss', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "x", "action": { "type": "open_url" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.single.action, isA<GameballDismissAction>());
    });

    test('ignores a malformed colour and leaves the field null', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "style": { "backgroundColor": "not-a-colour" } } }
      '''));

      expect(campaigns.single.message.style.backgroundColor, isNull);
    });

    test('treats a non-positive autoDismissAfterMs as no auto-dismiss', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "autoDismissAfterMs": 0 } }
      '''));

      expect(campaigns.single.message.autoDismissAfter, isNull);
    });
  });

  group('parseCampaignsJson — Braze modal layouts', () {
    test('image-only: an imageUrl alone is enough, with no text at all', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal",
                       "imageUrl": "https://cdn.example.com/promo.png",
                       "action": { "type": "open_url", "url": "app://sale" } } }
      '''));

      final m = campaigns.single.message;
      expect(m.imageUrl, 'https://cdn.example.com/promo.png');
      expect(m.body, isNull);
      expect(m.header, isNull);
      expect(m.clickAction, isA<GameballOpenUrlAction>());
    });

    test('a header with no body is enough to render', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "header": "Gold unlocked" } }
      '''));

      expect(campaigns.single.message.header, 'Gold unlocked');
      expect(campaigns.single.message.body, isNull);
    });

    test('text layout: no message action means the surface is not tappable', () {
      final campaigns = parseCampaignsJson(payload());

      expect(campaigns.single.message.clickAction, isNull);
    });

    test('a message-level dismiss action is honoured', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "action": { "type": "dismiss" } } }
      '''));

      expect(campaigns.single.message.clickAction, isA<GameballDismissAction>());
    });

    test('an unusable message action leaves the surface untappable', () {
      // Unlike a button, where an unusable action degrades to dismiss: silently
      // turning the whole message into a close button would be worse.
      for (final action in <String>[
        '{ "type": "open_url" }',
        '{ "type": "send_telepathy" }',
        '"not-an-object"',
      ]) {
        final campaigns = parseCampaignsJson(payload(campaigns: '''
          { "id": "c", "trigger": { "type": "session_start" },
            "message": { "id": "m", "type": "modal", "body": "b",
                         "action": $action } }
        '''));

        expect(campaigns.single.message.clickAction, isNull,
            reason: 'action $action must not make the message tappable');
      }
    });

    test('the message action is independent of button actions', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "action": { "type": "open_url", "url": "app://body" },
                       "buttons": [ { "text": "Go",
                         "action": { "type": "open_url", "url": "app://button" } } ] } }
      '''));

      final m = campaigns.single.message;
      expect((m.clickAction! as GameballOpenUrlAction).url, 'app://body');
      expect((m.buttons.single.action as GameballOpenUrlAction).url, 'app://button');
    });
  });

  group('parseCampaignsJson — purchase triggers and filters', () {
    test('parses any_purchase', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "any_purchase" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      '''));

      expect(campaigns.single.trigger, isA<GameballAnyPurchaseTrigger>());
    });

    test('parses specific_purchase with a productId', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "specific_purchase", "productId": "sku-001" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      '''));

      final trigger = campaigns.single.trigger as GameballSpecificPurchaseTrigger;
      expect(trigger.productId, 'sku-001');
      expect(trigger.filters, isEmpty);
    });

    test('parses specific_purchase with only filters', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "specific_purchase", "filters": [
            { "property": "price", "operator": "greater_than", "value": 100 } ] },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      '''));

      final trigger = campaigns.single.trigger as GameballSpecificPurchaseTrigger;
      expect(trigger.productId, isNull);
      expect(trigger.filters.single.property, 'price');
      expect(trigger.filters.single.operator, GameballFilterOperator.greaterThan);
      expect(trigger.filters.single.value, 100);
    });

    test('drops specific_purchase with neither productId nor filters', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "specific_purchase" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty,
          reason: 'it would be indistinguishable from any_purchase');
    });

    test('parses filters on a custom event too', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "custom_event", "eventName": "add_to_cart",
            "filters": [ { "property": "price", "operator": ">", "value": 100 } ] },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      '''));

      final trigger = campaigns.single.trigger as GameballCustomEventTrigger;
      expect(trigger.filters.single.operator, GameballFilterOperator.greaterThan);
    });

    test('accepts operator aliases', () {
      const aliases = <String, GameballFilterOperator>{
        'equals': GameballFilterOperator.equals,
        'eq': GameballFilterOperator.equals,
        '==': GameballFilterOperator.equals,
        'not_equals': GameballFilterOperator.notEquals,
        'gt': GameballFilterOperator.greaterThan,
        'gte': GameballFilterOperator.greaterThanOrEqual,
        '<': GameballFilterOperator.lessThan,
        'lte': GameballFilterOperator.lessThanOrEqual,
        'CONTAINS': GameballFilterOperator.contains,
      };

      aliases.forEach((alias, expected) {
        final campaigns = parseCampaignsJson(payload(campaigns: '''
          { "id": "c", "trigger": { "type": "custom_event", "eventName": "e",
              "filters": [ { "property": "p", "operator": "$alias", "value": 1 } ] },
            "message": { "id": "m", "type": "modal", "body": "b" } }
        '''));

        final trigger = campaigns.single.trigger as GameballCustomEventTrigger;
        expect(trigger.filters.single.operator, expected,
            reason: 'alias "$alias"');
      });
    });

    test('an unusable filter is dropped, widening rather than narrowing', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "custom_event", "eventName": "e",
            "filters": [
              { "property": "p", "operator": "sorta_equals", "value": 1 },
              { "operator": "eq", "value": 1 },
              { "property": "q", "operator": "eq" },
              { "property": "ok", "operator": "eq", "value": 5 } ] },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      '''));

      final trigger = campaigns.single.trigger as GameballCustomEventTrigger;
      expect(trigger.filters, hasLength(1),
          reason: 'dropping the whole campaign would hide one typo behind a '
              'message that simply never appears');
      expect(trigger.filters.single.property, 'ok');
    });
  });

  group('parseCampaignsJson — keep but skip', () {
    test('keeps an unknown message type as unsupported', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "hologram", "body": "b" } }
      '''));

      expect(campaigns, hasLength(1));
      expect(campaigns.single.message.type, GameballMessageType.unsupported);
    });
  });

  group('parseCampaignsJson — drop what can never work', () {
    test('drops a campaign with an unknown trigger type', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "push_click" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('drops a custom_event trigger with no eventName', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "custom_event" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('drops a campaign with no id', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('drops a message with nothing to render', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal" } }
      ''')), isEmpty);
    });

    test('drops a message whose only text fields are empty strings', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "header": "", "body": "",
                       "imageUrl": "" } }
      ''')), isEmpty);
    });

    test('drops a message with no id', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('keeps valid campaigns alongside dropped ones', () {
      final campaigns = parseCampaignsJson(
        '{"campaigns":[$_oneModalCampaign,'
        '{"id":"bad","trigger":{"type":"push_click"},'
        '"message":{"id":"m","type":"modal","body":"b"}}]}',
      );

      expect(campaigns.map((c) => c.id), ['cmp_a']);
    });
  });

  group('parseCampaignsJson — never throws', () {
    test('returns empty for invalid JSON', () {
      expect(parseCampaignsJson('not json at all'), isEmpty);
    });

    test('returns empty when the root is not an object', () {
      expect(parseCampaignsJson('[1,2,3]'), isEmpty);
    });

    test('returns empty when campaigns is missing', () {
      expect(parseCampaignsJson('{}'), isEmpty);
    });

    test('returns empty when campaigns is not a list', () {
      expect(parseCampaignsJson('{"campaigns": 5}'), isEmpty);
    });

    test('skips non-object entries in campaigns', () {
      expect(parseCampaignsJson('{"campaigns": [1, "two", null]}'), isEmpty);
    });
  });

  group('parseColor', () {
    test('parses 6-digit hex as fully opaque', () {
      expect(parseColor('#6C4DF6'), const Color(0xFF6C4DF6));
    });

    test('parses 8-digit hex with alpha', () {
      expect(parseColor('#8000FF00'), const Color(0x8000FF00));
    });

    test('parses hex without a leading hash', () {
      expect(parseColor('FFFFFF'), const Color(0xFFFFFFFF));
    });

    test('parses a packed ARGB int', () {
      expect(parseColor(4278190080), const Color(0xFF000000));
    });

    test('returns null for junk', () {
      expect(parseColor('zzz'), isNull);
      expect(parseColor('#12345'), isNull);
      expect(parseColor(null), isNull);
      expect(parseColor(true), isNull);
    });
  });

  group('triggerMatches', () {
    test('matches session start to session start', () {
      expect(
        triggerMatches(const GameballSessionStartTrigger(), const GameballSessionStartOccurrence()),
        isTrue,
      );
    });

    test('matches custom events with the same name', () {
      expect(
        triggerMatches(
          const GameballCustomEventTrigger('a'),
          const GameballCustomEventOccurrence('a'),
        ),
        isTrue,
      );
    });

    test('does not match custom events with different names', () {
      expect(
        triggerMatches(
          const GameballCustomEventTrigger('a'),
          const GameballCustomEventOccurrence('b'),
        ),
        isFalse,
      );
    });

    test('does not match across trigger types', () {
      expect(
        triggerMatches(
          const GameballSessionStartTrigger(),
          const GameballCustomEventOccurrence('a'),
        ),
        isFalse,
      );
    });

    test('any purchase matches any purchase occurrence', () {
      expect(
        triggerMatches(
          const GameballAnyPurchaseTrigger(),
          const GameballPurchaseOccurrence(
            productId: 'sku-001',
            price: 10,
            currency: 'USD',
          ),
        ),
        isTrue,
      );
    });

    test('specific purchase matches on productId', () {
      const occurrence = GameballPurchaseOccurrence(
        productId: 'sku-001',
        price: 10,
        currency: 'USD',
      );

      expect(
        triggerMatches(
          const GameballSpecificPurchaseTrigger(productId: 'sku-001'),
          occurrence,
        ),
        isTrue,
      );
      expect(
        triggerMatches(
          const GameballSpecificPurchaseTrigger(productId: 'sku-999'),
          occurrence,
        ),
        isFalse,
      );
    });

    test('purchase built-ins are filterable like any other property', () {
      const occurrence = GameballPurchaseOccurrence(
        productId: 'sku-001',
        price: 189.0,
        currency: 'USD',
        quantity: 2,
      );

      expect(
        triggerMatches(
          const GameballSpecificPurchaseTrigger(filters: [
            GameballPropertyFilter(
              property: 'price',
              operator: GameballFilterOperator.greaterThan,
              value: 100,
            ),
          ]),
          occurrence,
        ),
        isTrue,
      );
      expect(
        triggerMatches(
          const GameballSpecificPurchaseTrigger(filters: [
            GameballPropertyFilter(
              property: 'price',
              operator: GameballFilterOperator.greaterThan,
              value: 500,
            ),
          ]),
          occurrence,
        ),
        isFalse,
      );
    });

    test('a custom event filter narrows an otherwise matching name', () {
      const trigger = GameballCustomEventTrigger('add_to_cart', filters: [
        GameballPropertyFilter(
          property: 'price',
          operator: GameballFilterOperator.greaterThan,
          value: 100,
        ),
      ]);

      expect(
        triggerMatches(
          trigger,
          const GameballCustomEventOccurrence('add_to_cart',
              properties: <String, Object>{'price': 189.0}),
        ),
        isTrue,
      );
      expect(
        triggerMatches(
          trigger,
          const GameballCustomEventOccurrence('add_to_cart',
              properties: <String, Object>{'price': 12.99}),
        ),
        isFalse,
      );
    });

    test('a filter on a property the occurrence lacks never matches', () {
      expect(
        triggerMatches(
          const GameballCustomEventTrigger('e', filters: [
            GameballPropertyFilter(
              property: 'tier',
              operator: GameballFilterOperator.equals,
              value: 'gold',
            ),
          ]),
          const GameballCustomEventOccurrence('e'),
        ),
        isFalse,
        reason: 'a filter is a requirement, so a missing property is a failure',
      );
    });
  });
}
