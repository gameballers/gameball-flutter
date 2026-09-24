import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/gameball_widget_view.dart';

void main() {
  test('an object payload decodes for the host', () {
    expect(
      decodeWidgetEvent('{"type":"game_completed","metadata":{"points":100}}'),
      <String, dynamic>{
        'type': 'game_completed',
        'metadata': <String, dynamic>{'points': 100},
      },
    );
  });

  test('anything that is not an object is null, never a throw', () {
    // The bridge carries whatever the page chooses to send, and this runs inside
    // a JavaScript channel callback — a throw there escapes into the host's
    // error handling for a payload the host never wrote.
    for (final bad in const ['not json', '[1,2,3]', '"a string"', '42', '']) {
      expect(decodeWidgetEvent(bad), isNull, reason: bad);
    }
  });
}
