import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_fullscreen.dart';

void main() {
  test('composes the open-details text from type and id', () {
    const content =
        GameballWidgetContent(gameCampaignId: 9645, gameCampaignType: 'wheel');
    expect(content.openDetail, 'details_wheel_9645');
  });

  testWidgets('a fullscreen game with no url fails rather than drawing blank',
      (tester) async {
    // The presenter refuses to mount a widget message without a url, so this is
    // unreachable in practice. It still reports failure rather than occupying
    // the whole screen with nothing, because a blank fullscreen surface is the
    // one failure a customer cannot interpret or escape.
    var failed = 0;

    await tester.pumpWidget(MaterialApp(
      home: GameballInAppMessageFullscreen(
        message: const GameballInAppMessage(
          id: 'g',
          type: GameballMessageType.fullscreen,
          widget: GameballWidgetContent(
            gameCampaignId: 9645,
            gameCampaignType: 'wheel',
          ),
        ),
        onButtonPressed: (_) {},
        onClosePressed: () {},
        onMessagePressed: () {},
        onWidgetFailed: () => failed++,
      ),
    ));

    expect(failed, 1);
  });
}
