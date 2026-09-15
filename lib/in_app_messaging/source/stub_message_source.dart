import '../models/gameball_audience.dart';
import 'message_parser.dart';
import 'message_source.dart';

/// The event the stub's cart campaign listens for. The sample app already logs
/// this from its product details screen.
const String stubCartEventName = 'add_to_cart';

/// The event the stub's image-only promo campaign listens for. Fired from the
/// sample app's offers screen.
const String stubPromoEventName = 'view_offers';

/// The reserved event a purchase is reported under.
const String stubPurchaseEventName = 'purchase';

/// A stand-in `integrations/inapp-messages/sync` response, shaped exactly like
/// the real one.
///
/// Held as a raw JSON string rather than as constructed objects, so the real
/// parsing rules are exercised from day one — the `content`/`locale`
/// split, button pairing by id, the numeric `messageType`. When the endpoint
/// lands, only the transport changes.
///
/// Six campaigns, chosen to cover every path the parser and evaluator have:
/// both modal layouts, a message-level action, per-campaign filters, competing
/// priorities on one trigger, auto-dismiss, and a campaign with no close button.
const String stubSyncJson = '''
{
  "cooldownSeconds": 30,
  "messages": [
      {
        "campaignId": 2041,
        "variationId": 1,
        "dispatchId": "stub-2041-a1b2c3",
        "name": "Welcome back offer",
        "priority": 100,
        "messageType": 2,
        "contentMode": "prerendered",
        "trigger": { "type": "session_start", "repeatable": false },
        "content": {
          "colors": {
            "background": "#FFFFFF",
            "header": "#111111",
            "text": "#444444",
            "frame": "#99000000",
            "closeButton": "#FFFFFF"
          },
          "textAlignment": { "header": "center", "body": "start" },
          "closeBehaviour": "both",
          "imageUrl": "https://i.ibb.co/fdHs3hrk/welcome.jpg",
          "extras": { "campaignSource": "loyalty-q3" },
          "buttons": [
            { "id": "b1", "action": { "type": "dismiss" },
              "colors": { "background": "#EEEEEE", "text": "#111111" } },
            { "id": "b2",
              "action": { "type": "open_url", "url": "https://gameball.co/rewards" },
              "colors": { "background": "#6C4DF6", "text": "#FFFFFF" } }
          ]
        },
        "locale": {
          "header": "Welcome back!",
          "message": "You have 1,250 points ready to redeem.",
          "buttons": [
            { "id": "b1", "text": "Later" },
            { "id": "b2", "text": "Redeem" }
          ]
        },
        "localeCode": "en",
        "expiresAt": null,
        "isTest": false
      },
      {
        "campaignId": 2042,
        "dispatchId": "stub-2042-d4e5f6",
        "name": "Second session nudge",
        "priority": 90,
        "messageType": 2,
        "contentMode": "prerendered",
        "trigger": { "type": "session_start", "repeatable": false },
        "content": {
          "colors": { "background": "#FFFFFF", "header": "#111111", "text": "#444444" },
          "textAlignment": { "header": "center", "body": "center" },
          "closeBehaviour": "both",
          "buttons": [
            { "id": "b1", "action": { "type": "dismiss" },
              "colors": { "background": "#6C4DF6", "text": "#FFFFFF" } }
          ]
        },
        "locale": {
          "header": "Good to see you again",
          "message": "Your points are still waiting.",
          "buttons": [ { "id": "b1", "text": "Got it" } ]
        },
        "localeCode": "en",
        "isTest": false
      },
      {
        "campaignId": 2043,
        "dispatchId": "stub-2043-g7h8i9",
        "name": "Cart nudge",
        "priority": 50,
        "messageType": 2,
        "contentMode": "prerendered",
        "trigger": {
          "type": "event",
          "eventId": 812,
          "name": "$stubCartEventName",
          "metadataLogicalOperator": "And",
          "metadataFilters": [
            { "metadataId": 4051, "name": "productId",
              "operator": "contains", "value": "sku" }
          ],
          "repeatable": true,
          "minIntervalSeconds": 60
        },
        "content": {
          "colors": { "background": "#FFFFFF", "text": "#444444" },
          "textAlignment": { "body": "center" },
          "closeBehaviour": "both",
          "action": { "type": "navigate", "route": "/cart" },
          "buttons": [
            { "id": "b1",
              "action": { "type": "navigate", "route": "/cart",
                          "arguments": { "from": "cart_nudge" } },
              "colors": { "background": "#6C4DF6", "text": "#FFFFFF" } }
          ]
        },
        "locale": {
          "message": "Add one more item for 2x points. Tap to review your cart.",
          "buttons": [ { "id": "b1", "text": "View cart" } ]
        },
        "localeCode": "en",
        "isTest": false
      },
      {
        "campaignId": 2044,
        "dispatchId": "stub-2044-j1k2l3",
        "name": "Seasonal promo (image only)",
        "priority": 10,
        "messageType": 2,
        "contentMode": "prerendered",
        "trigger": {
          "type": "event",
          "eventId": 813,
          "name": "$stubPromoEventName",
          "repeatable": false
        },
        "content": {
          "colors": { "background": "#FFFFFF", "closeButton": "#FFFFFF" },
          "closeBehaviour": "both",
          "imageUrl": "https://i.ibb.co/G34R4MtM/83312799-summer-sale.jpg",
          "action": { "type": "navigate", "route": "/offers" }
        },
        "locale": {},
        "localeCode": "en",
        "isTest": false
      },
      {
        "campaignId": 2045,
        "dispatchId": "stub-2045-m4n5o6",
        "name": "Thanks for your order",
        "priority": 40,
        "messageType": 2,
        "contentMode": "prerendered",
        "trigger": {
          "type": "event",
          "eventId": 900,
          "name": "$stubPurchaseEventName",
          "repeatable": true,
          "minIntervalSeconds": 0
        },
        "content": {
          "colors": { "background": "#FFFFFF", "header": "#0F7A52", "text": "#444444" },
          "textAlignment": { "header": "center", "body": "center" },
          "closeBehaviour": "swipe",
          "autoDismissSeconds": 5
        },
        "locale": {
          "header": "Thanks for your order!",
          "message": "Points have been added to your balance."
        },
        "localeCode": "en",
        "isTest": false
      },
      {
        "campaignId": 2046,
        "dispatchId": "stub-2046-p7q8r9",
        "name": "Big spender reward",
        "priority": 80,
        "messageType": 2,
        "contentMode": "prerendered",
        "trigger": {
          "type": "event",
          "eventId": 900,
          "name": "$stubPurchaseEventName",
          "metadataLogicalOperator": "And",
          "metadataFilters": [
            { "metadataId": 4100, "name": "price",
              "operator": "greaterThan", "value": 100 }
          ],
          "repeatable": false
        },
        "content": {
          "colors": { "background": "#FFFFFF", "header": "#111111", "text": "#444444" },
          "closeBehaviour": "both",
          "extras": { "campaignSource": "threshold" },
          "buttons": [
            { "id": "b1", "action": { "type": "dismiss" },
              "colors": { "background": "#EEEEEE", "text": "#111111" } },
            { "id": "b2", "action": { "type": "navigate", "route": "/offers" },
              "colors": { "background": "#0F7A52", "text": "#FFFFFF" } }
          ]
        },
        "locale": {
          "header": "You unlocked free delivery",
          "message": "Orders over 100 earn free delivery on your next purchase.",
          "buttons": [
            { "id": "b1", "text": "Later" },
            { "id": "b2", "text": "See offers" }
          ]
        },
        "localeCode": "en",
        "isTest": false
    }
  ]
}
''';

/// Serves campaigns from a fixture instead of the network.
///
/// Used until the backend endpoint exists. Tests inject [json] to control the
/// payload.
class StubMessageSource implements GameballMessageSource {
  StubMessageSource({String? json}) : _json = json ?? stubSyncJson;

  final String _json;

  @override
  Future<GameballSyncResult> fetch(GameballAudience audience) async {
    return parseSyncResponse(_json);
  }
}
