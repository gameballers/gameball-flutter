import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_modal.dart';

GameballInAppMessage message({
  String? body = 'body text',
  String? header,
  String? imageUrl,
  GameballClickAction? clickAction,
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
    clickAction: clickAction,
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
  VoidCallback? onMessagePressed,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameballInAppMessageModal(
        message: m,
        onButtonPressed: onButtonPressed ?? (_) {},
        onMessagePressed: onMessagePressed ?? () {},
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

  group('image sizing', () {
    testWidgets('never crops — the image is fitted, not covered', (tester) async {
      await pump(tester, message(imageUrl: 'https://example.com/a.png'));

      final image = tester.widget<Image>(find.byKey(const Key('gb_iam_image')));
      expect(image.fit, BoxFit.contain,
          reason: 'cropping would discard the design a marketer uploaded');
      expect(image.height, isNull,
          reason: 'height comes from the image aspect ratio, not a fixed band');
    });

    testWidgets('a banner above copy is capped modestly', (tester) async {
      await pump(tester, message(
        body: 'text alongside',
        imageUrl: 'https://example.com/a.png',
      ));

      final box = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_image')),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      expect(box.constraints.maxHeight, 220);
    });

    testWidgets('an image-only message gets most of the screen', (tester) async {
      await pump(tester, message(
        body: null,
        imageUrl: 'https://example.com/promo.png',
      ));

      final box = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_image')),
          matching: find.byType(ConstrainedBox),
        ).first,
      );
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(box.constraints.maxHeight, closeTo(screenHeight * 0.65, 0.5),
          reason: 'the artwork is the content, so it gets the room');
    });
  });

  testWidgets('a failing image does not prevent the message rendering', (tester) async {
    // The test HTTP client returns a 400 for every request, so the network
    // image always fails — which is exactly the case being asserted.
    await pump(tester, message(body: 'still here', imageUrl: 'https://example.com/nope.png'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('still here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Braze layout: Image Only', () {
    testWidgets('renders the image with no text block at all', (tester) async {
      await pump(tester, message(
        body: null,
        imageUrl: 'https://example.com/promo.png',
      ));

      expect(find.byKey(const Key('gb_iam_image')), findsOneWidget);
      expect(find.byKey(const Key('gb_iam_body')), findsNothing);
      expect(find.byKey(const Key('gb_iam_header')), findsNothing);
      expect(find.byKey(const Key('gb_iam_buttons')), findsNothing,
          reason: 'no padding band should be laid out under the artwork');
    });

    testWidgets('still shows the close button', (tester) async {
      await pump(tester, message(
        body: null,
        imageUrl: 'https://example.com/promo.png',
      ));

      expect(find.byKey(const Key('gb_iam_close')), findsOneWidget);
    });

    testWidgets('renders buttons even with no text', (tester) async {
      await pump(tester, message(
        body: null,
        imageUrl: 'https://example.com/promo.png',
        buttons: const [
          GameballMessageButton(id: 0, text: 'Shop', action: GameballDismissAction()),
        ],
      ));

      expect(find.text('Shop'), findsOneWidget);
    });
  });

  group('Braze layout: header without body', () {
    testWidgets('renders the header alone', (tester) async {
      await pump(tester, message(body: null, header: 'Gold unlocked'));

      expect(find.text('Gold unlocked'), findsOneWidget);
      expect(find.byKey(const Key('gb_iam_body')), findsNothing);
    });
  });

  group('message-level click action', () {
    testWidgets('the surface is not tappable without an action', (tester) async {
      await pump(tester, message());

      expect(find.byKey(const Key('gb_iam_surface_tap')), findsNothing,
          reason: 'an inert message must not absorb taps');
    });

    testWidgets('the surface is tappable when an action is set', (tester) async {
      var pressed = 0;
      await pump(
        tester,
        message(clickAction: const GameballOpenUrlAction('app://x')),
        onMessagePressed: () => pressed++,
      );

      expect(find.byKey(const Key('gb_iam_surface_tap')), findsOneWidget);
      await tester.tap(find.byKey(const Key('gb_iam_body')));
      await tester.pump();

      expect(pressed, 1);
    });

    testWidgets('a button tap does not also fire the message action', (tester) async {
      var messagePressed = 0;
      final buttonsTapped = <int>[];
      await pump(
        tester,
        message(
          clickAction: const GameballOpenUrlAction('app://body'),
          buttons: const [
            GameballMessageButton(id: 7, text: 'Go', action: GameballDismissAction()),
          ],
        ),
        onButtonPressed: (b) => buttonsTapped.add(b.id),
        onMessagePressed: () => messagePressed++,
      );

      await tester.tap(find.text('Go'));
      await tester.pump();

      expect(buttonsTapped, [7]);
      expect(messagePressed, 0,
          reason: 'the button wins the hit test; the tap must not propagate');
    });

    testWidgets('the close button does not fire the message action', (tester) async {
      var messagePressed = 0;
      var closed = 0;
      await pump(
        tester,
        message(clickAction: const GameballOpenUrlAction('app://body')),
        onClosePressed: () => closed++,
        onMessagePressed: () => messagePressed++,
      );

      await tester.tap(find.byKey(const Key('gb_iam_close')));
      await tester.pump();

      expect(closed, 1);
      expect(messagePressed, 0);
    });
  });
}
