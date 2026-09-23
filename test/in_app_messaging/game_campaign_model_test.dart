import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';

void main() {
  test('composes the open-details text from type and id', () {
    const content =
        GameballWidgetContent(gameCampaignId: 9645, gameCampaignType: 'wheel');
    expect(content.openDetail, 'details_wheel_9645');
  });

  test('delay and dismissLimit are absent until the backend sends them', () {
    const content =
        GameballWidgetContent(gameCampaignId: 9645, gameCampaignType: 'wheel');
    expect(content.delay, isNull);
    expect(content.dismissLimit, isNull);
  });
}
