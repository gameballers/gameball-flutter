import '../models/gameball_audience.dart';
import '../models/in_app_message_campaign.dart';
import 'message_parser.dart';
import 'message_source.dart';

/// The custom event the stub's cart campaign listens for. The sample app
/// already logs this event from its product details screen.
const String stubCartEventName = 'add_to_cart';

/// The custom event the stub's image-only promo campaign listens for. Fired from
/// the sample app's debug screen.
const String stubPromoEventName = 'view_offers';

/// A stand-in payload shaped exactly like the response the backend will return.
///
/// Held as a raw JSON string, not as constructed objects, so the real parsing
/// rules are exercised from day one. When the endpoint lands, only the
/// transport changes — the parser and its tests are untouched.
const String stubCampaignsJson = '''
{
  "campaigns": [
    {
      "id": "cmp_welcome_modal",
      "priority": 100,
      "trigger": { "type": "session_start" },
      "message": {
        "id": "msg_welcome_v1",
        "type": "modal",
        "header": "Welcome back!",
        "body": "You have 1,250 points ready to redeem.",
        "imageUrl": "https://i.ibb.co/fdHs3hrk/welcome.jpg",
        "showCloseButton": true,
        "autoDismissAfterMs": null,
        "isTestSend": false,
        "buttons": [
          {
            "id": 0,
            "text": "Later",
            "action": { "type": "dismiss" },
            "style": {
              "backgroundColor": "#EEEEEE",
              "textColor": "#111111",
              "borderColor": "#DDDDDD"
            }
          },
          {
            "id": 1,
            "text": "Redeem",
            "action": { "type": "open_url", "url": "https://gameball.co", "external": false },
            "style": {
              "backgroundColor": "#6C4DF6",
              "textColor": "#FFFFFF",
              "borderColor": "#6C4DF6"
            }
          }
        ],
        "style": {
          "backgroundColor": "#FFFFFF",
          "headerColor": "#111111",
          "bodyColor": "#444444",
          "scrimColor": "#99000000",
          "headerAlign": "center",
          "bodyAlign": "start"
        },
        "extras": { "campaignSource": "loyalty-q3" }
      }
    },
    {
      "id": "cmp_cart_nudge",
      "priority": 50,
      "trigger": { "type": "custom_event", "eventName": "$stubCartEventName" },
      "message": {
        "id": "msg_cart_v1",
        "type": "modal",
        "body": "Add one more item for 2x points.",
        "showCloseButton": true,
        "buttons": []
      }
    },
    {
      "id": "cmp_seasonal_promo",
      "priority": 10,
      "trigger": { "type": "custom_event", "eventName": "$stubPromoEventName" },
      "message": {
        "id": "msg_promo_v1",
        "type": "modal",
        "imageUrl": "https://i.ibb.co/G34R4MtM/83312799-summer-sale-discount-promo-poster-or-banner-for-seasonal-shopping-50-percent-discount-of-pa.jpg",
        "action": { "type": "open_url", "url": "https://gameball.co/offers", "external": false },
        "showCloseButton": true,
        "style": { "scrimColor": "#B3000000" },
        "extras": { "campaignSource": "seasonal" }
      }
    }
  ]
}
''';

/// Serves campaigns from a fixture instead of the network.
///
/// Used until the backend endpoint exists. Tests inject [json] to control the
/// payload.
class StubMessageSource implements GameballMessageSource {
  StubMessageSource({String? json}) : _json = json ?? stubCampaignsJson;

  final String _json;

  @override
  Future<List<InAppMessageCampaign>> fetch(GameballAudience audience) async {
    return parseCampaignsJson(_json);
  }
}
