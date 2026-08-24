import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_fullscreen.dart';

GameballInAppMessage fullscreen({
  GameballMessageLayout layout = GameballMessageLayout.textWithImage,
  String? header = 'Big orders. Bigger savings.',
  String? body = 'Up to 50% off this week.',
  String? imageUrl = 'https://cdn/promo.png',
  GameballClickAction? action,
  bool showCloseButton = true,
  List<GameballMessageButton> buttons = const [
    GameballMessageButton(
      id: 'cta',
      text: 'Order Now',
      action: GameballDismissAction(),
    ),
  ],
  GameballMessageStyle style = const GameballMessageStyle(),
}) {
  return GameballInAppMessage(
    id: '1',
    type: GameballMessageType.fullscreen,
    layout: layout,
    header: header,
    body: body,
    imageUrl: imageUrl,
    clickAction: action,
    showCloseButton: showCloseButton,
    buttons: buttons,
    style: style,
  );
}

void main() {
  Future<({List<String> log,})> pump(
    WidgetTester tester,
    GameballInAppMessage message, {
    Size surface = const Size(390, 844),
  }) async {
    final log = <String>[];
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: GameballInAppMessageFullscreen(
        message: message,
        onButtonPressed: (b) => log.add('button:${b.id}'),
        onClosePressed: () => log.add('close'),
        onMessagePressed: () => log.add('surface'),
      ),
    ));
    await tester.pump();
    return (log: log,);
  }

  group('it fills the screen', () {
    testWidgets('the surface covers the whole viewport', (tester) async {
      await pump(tester, fullscreen());

      final size = tester.getSize(
          find.byKey(const Key('gb_iam_fullscreen_surface')));
      expect(size, const Size(390, 844),
          reason: 'edge to edge is what separates this from a modal, which is a '
              'centred card with margins');
    });
  });

  group('the stacked variant', () {
    testWidgets('shows image, header, body and buttons', (tester) async {
      await pump(tester, fullscreen());

      expect(find.byKey(const Key('gb_iam_fullscreen_image')), findsOneWidget);
      expect(find.text('Big orders. Bigger savings.'), findsOneWidget);
      expect(find.text('Up to 50% off this week.'), findsOneWidget);
      expect(find.text('Order Now'), findsOneWidget);
    });

    testWidgets('the button spans the width', (tester) async {
      await pump(tester, fullscreen());

      final button = tester.getSize(find.widgetWithText(TextButton, 'Order Now'));
      expect(button.width, greaterThan(300),
          reason: 'a fullscreen call to action fills the width; the modal row '
              'would look lost here');
    });
    testWidgets('shows the whole artwork rather than cropping it',
        (tester) async {
      await pump(tester, fullscreen());

      final image = tester
          .widget<Image>(find.byKey(const Key('gb_iam_fullscreen_image')));
      expect(image.fit, BoxFit.contain,
          reason: 'here the image shares the screen with copy instead of '
              'bleeding to the edges, and promotional artwork usually has text '
              'baked into it — cropping deletes the offer. The modal already '
              'reasons this way; the two must not treat one image differently');
    });
  });

  group('the image-only variant', () {
    testWidgets('renders the button over the artwork, not below it',
        (tester) async {
      await pump(
        tester,
        fullscreen(layout: GameballMessageLayout.imageOnly, header: null, body: null),
      );

      final image = tester.getRect(
          find.byKey(const Key('gb_iam_fullscreen_image')));
      final button = tester.getRect(find.widgetWithText(TextButton, 'Order Now'));

      expect(image.height, 844, reason: 'the artwork fills the screen');
      expect(button.top, greaterThan(image.top));
      expect(button.bottom, lessThanOrEqualTo(image.bottom),
          reason: 'the button sits inside the image bounds — over it, which is '
              'what GRAPHIC means and what the inference alone cannot produce');
    });

    testWidgets('omits the copy entirely', (tester) async {
      await pump(
        tester,
        fullscreen(layout: GameballMessageLayout.imageOnly, header: null, body: null),
      );

      expect(find.byKey(const Key('gb_iam_fullscreen_header')), findsNothing);
      expect(find.byKey(const Key('gb_iam_fullscreen_body')), findsNothing);
    });

    testWidgets('crops rather than letterboxing', (tester) async {
      await pump(
        tester,
        fullscreen(layout: GameballMessageLayout.imageOnly, header: null, body: null),
      );

      final image =
          tester.widget<Image>(find.byKey(const Key('gb_iam_fullscreen_image')));
      expect(image.fit, BoxFit.cover,
          reason: 'the one place cropping is right — bands of background where '
              'the designer expected bleed would read as a bug');
    });
  });

  group('the close button', () {
    testWidgets('reports a close without counting as engagement',
        (tester) async {
      final h = await pump(tester, fullscreen());

      await tester.tap(find.byKey(const Key('gb_iam_fullscreen_close')));
      await tester.pump();

      expect(h.log, ['close']);
    });

    testWidgets('gets a scrim disc when it sits over artwork', (tester) async {
      await pump(tester, fullscreen());

      final decorated = tester.widget<DecoratedBox>(find.ancestor(
        of: find.byKey(const Key('gb_iam_fullscreen_close')),
        matching: find.byType(DecoratedBox),
      ).first);
      final decoration = decorated.decoration as BoxDecoration;

      expect(decoration.color, isNotNull,
          reason: 'a dark glyph on a dark photograph is invisible');
    });

    testWidgets('can be omitted', (tester) async {
      await pump(tester, fullscreen(showCloseButton: false));

      expect(find.byKey(const Key('gb_iam_fullscreen_close')), findsNothing);
    });
  });

  group('the surface action', () {
    testWidgets('is inert without one', (tester) async {
      final h = await pump(tester, fullscreen());

      expect(find.byKey(const Key('gb_iam_fullscreen_tap')), findsNothing);
      expect(h.log, isEmpty);
    });

    testWidgets('reports a tap when the campaign set one', (tester) async {
      final h = await pump(
        tester,
        fullscreen(action: const GameballDismissAction()),
      );

      await tester.tap(find.byKey(const Key('gb_iam_fullscreen_tap')),
          warnIfMissed: false);
      await tester.pump();

      expect(h.log, ['surface']);
    });

    testWidgets('a button tap does not also fire the surface', (tester) async {
      final h = await pump(
        tester,
        fullscreen(action: const GameballDismissAction()),
      );

      await tester.tap(find.text('Order Now'));
      await tester.pump();

      expect(h.log, ['button:cta'],
          reason: 'the button wins its own hit test, or every CTA would report '
              'two clicks');
    });
  });

  group('styling', () {
    testWidgets('uses the campaign background', (tester) async {
      await pump(
        tester,
        fullscreen(
          style: const GameballMessageStyle(backgroundColor: Color(0xFF223344)),
        ),
      );

      final material = tester.widget<Material>(
          find.byKey(const Key('gb_iam_fullscreen_surface')));
      expect(material.color, const Color(0xFF223344));
    });

    testWidgets('a dead image does not stop the message', (tester) async {
      // Every image load fails in a widget test, which is the same outcome as a
      // campaign pointing at a 403.
      await pump(tester, fullscreen());

      expect(find.text('Order Now'), findsOneWidget);
      expect(find.text('Big orders. Bigger savings.'), findsOneWidget);
    });
  });
}
