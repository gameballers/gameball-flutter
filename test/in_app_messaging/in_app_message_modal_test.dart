import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_modal.dart';

GameballInAppMessage message({
  String body = 'body text',
  String? header,
  String? imageUrl,
  bool showCloseButton = true,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
  GameballMessageStyle style = const GameballMessageStyle(),
}) {
  return GameballInAppMessage(
    id: 'msg',
    type: GameballMessageType.modal,
    body: body,
    header: header,
    imageUrl: imageUrl,
    showCloseButton: showCloseButton,
    buttons: buttons,
    style: style,
  );
}

Future<void> pump(
  WidgetTester tester,
  GameballInAppMessage m, {
  void Function(GameballMessageButton)? onButtonPressed,
  VoidCallback? onClosePressed,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameballInAppMessageModal(
        message: m,
        onButtonPressed: onButtonPressed ?? (_) {},
        onClosePressed: onClosePressed ?? () {},
      ),
    ),
  ));
}

void main() {
  testWidgets('renders the body', (tester) async {
    await pump(tester, message(body: 'hello there'));

    expect(find.text('hello there'), findsOneWidget);
  });

  testWidgets('renders the header when present', (tester) async {
    await pump(tester, message(header: 'Welcome'));

    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('omits the header when absent', (tester) async {
    await pump(tester, message());

    expect(find.byKey(const Key('gb_iam_header')), findsNothing);
  });

  testWidgets('shows a close button when requested', (tester) async {
    await pump(tester, message(showCloseButton: true));

    expect(find.byKey(const Key('gb_iam_close')), findsOneWidget);
  });

  testWidgets('hides the close button when not requested', (tester) async {
    await pump(tester, message(showCloseButton: false));

    expect(find.byKey(const Key('gb_iam_close')), findsNothing);
  });

  testWidgets('invokes onClosePressed when the close button is tapped', (tester) async {
    var closed = 0;
    await pump(tester, message(), onClosePressed: () => closed++);

    await tester.tap(find.byKey(const Key('gb_iam_close')));
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('renders each button and reports which was tapped', (tester) async {
    final tapped = <int>[];
    await pump(
      tester,
      message(buttons: const [
        GameballMessageButton(id: 0, text: 'Later', action: GameballDismissAction()),
        GameballMessageButton(id: 1, text: 'Redeem', action: GameballDismissAction()),
      ]),
      onButtonPressed: (b) => tapped.add(b.id),
    );

    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Redeem'), findsOneWidget);

    await tester.tap(find.text('Redeem'));
    await tester.pump();

    expect(tapped, [1]);
  });

  testWidgets('renders no button row when there are no buttons', (tester) async {
    await pump(tester, message());

    expect(find.byKey(const Key('gb_iam_buttons')), findsNothing);
  });

  testWidgets('applies the background colour from style', (tester) async {
    await pump(
      tester,
      message(style: const GameballMessageStyle(backgroundColor: Color(0xFF00FF00))),
    );

    final card = tester.widget<Material>(find.byKey(const Key('gb_iam_surface')));
    expect(card.color, const Color(0xFF00FF00));
  });

  testWidgets('renders an image slot when imageUrl is present', (tester) async {
    await pump(tester, message(imageUrl: 'https://example.com/a.png'));

    expect(find.byKey(const Key('gb_iam_image')), findsOneWidget);
  });

  testWidgets('omits the image slot when imageUrl is absent', (tester) async {
    await pump(tester, message());

    expect(find.byKey(const Key('gb_iam_image')), findsNothing);
  });

  testWidgets('a failing image does not prevent the message rendering', (tester) async {
    // The test HTTP client returns a 400 for every request, so the network
    // image always fails — which is exactly the case being asserted.
    await pump(tester, message(body: 'still here', imageUrl: 'https://example.com/nope.png'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('still here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
