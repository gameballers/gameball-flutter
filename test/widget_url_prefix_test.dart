import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';

void main() {
  GameballConfig config({String? widgetUrlPrefix}) => GameballConfigBuilder()
      .apiKey('k')
      .lang('en')
      .widgetUrlPrefix(widgetUrlPrefix)
      .build();

  test('a configured widget host is carried on the config', () {
    expect(
      config(widgetUrlPrefix: 'https://m.gameball.app/alpha').widgetUrlPrefix,
      'https://m.gameball.app/alpha',
    );
  });

  test('omitting it leaves it null, so production is used', () {
    expect(config().widgetUrlPrefix, isNull);
  });

  test('it survives a round trip through json', () {
    // init() logs the config, and the diagnostic log is how a support case
    // establishes which environment a host was actually pointed at.
    final json = config(widgetUrlPrefix: 'https://m.gameball.app/alpha').toJson();

    expect(json['widgetUrlPrefix'], 'https://m.gameball.app/alpha');
    expect(
      GameballConfig.fromJson(json).widgetUrlPrefix,
      'https://m.gameball.app/alpha',
    );
  });
}
