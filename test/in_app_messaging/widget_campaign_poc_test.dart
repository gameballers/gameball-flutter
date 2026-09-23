import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';
import 'package:gameball_sdk/in_app_messaging/source/stub_message_source.dart';

void main() {
  test('widget fixture parses into widget messages', () {
    final result = parseSyncResponse(stubWidgetSyncJson);
    expect(result.campaigns.length, 2);
    for (final c in result.campaigns) {
      expect(c.message.isWidget, isTrue, reason: 'campaign ${c.campaignId}');
      expect(c.message.widget!.openDetail, 'details_wheel');
    }
  });

  test('a widget message survives having no header, body or image', () {
    const json = stubWidgetSyncJson;
    expect(json.contains('"header"'), isFalse);
    expect(parseSyncResponse(json).campaigns, isNotEmpty);
  });
}
