import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_modal.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_view_metrics.dart';

GameballInAppMessage message({
  GameballMessageLayout layout = GameballMessageLayout.textWithImage,
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
    layout: layout,
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
    final tapped = <String>[];
    await pump(
      tester,
      message(buttons: const [
        GameballMessageButton(id: 'b1', text: 'Later', action: GameballDismissAction()),
        GameballMessageButton(id: 'b2', text: 'Redeem', action: GameballDismissAction()),
      ]),
      onButtonPressed: (b) => tapped.add(b.id),
    );

    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Redeem'), findsOneWidget);

    await tester.tap(find.text('Redeem'));
    await tester.pump();

    expect(tapped, ['b2']);
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

  group('close button legibility', () {
    Color? glyph(WidgetTester tester) =>
        tester.widget<IconButton>(find.byKey(const Key('gb_iam_close'))).color;

    Iterable<DecoratedBox> discs(WidgetTester tester) =>
        tester.widgetList<DecoratedBox>(find.ancestor(
          of: find.byKey(const Key('gb_iam_close')),
          matching: find.byType(DecoratedBox),
        )).where((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle;
        });

    testWidgets('draws no disc, even over artwork', (tester) async {
      await pump(tester, message(imageUrl: 'https://example.com/dark.png'));

      expect(discs(tester), isEmpty,
          reason: 'legibility comes from the derived glyph colour now, not '
              'from a scrim behind it');
    });

    testWidgets('uses the same glyph size as fullscreen', (tester) async {
      // Was 20 on a modal and 24 on fullscreen. Nothing about a modal argues
      // for a smaller control, and one number is one fewer thing for four
      // platforms to get differently.
      await pump(tester, message());

      final button =
          tester.widget<IconButton>(find.byKey(const Key('gb_iam_close')));
      expect(button.iconSize, MessageMetrics.closeGlyphSize);
    });

    testWidgets('a light card takes a dark glyph', (tester) async {
      await pump(tester, message(
        style: const GameballMessageStyle(backgroundColor: Color(0xFFFFFFFF)),
      ));

      expect(glyph(tester), MessageMetrics.closeGlyphOnLight);
    });

    testWidgets('a dark card takes a light glyph', (tester) async {
      await pump(tester, message(
        style: const GameballMessageStyle(backgroundColor: Color(0xFF111827)),
      ));

      expect(glyph(tester), MessageMetrics.closeGlyphOnDark);
    });

    testWidgets('artwork does not change the derivation', (tester) async {
      // The regression this replaces. A contained portrait image letterboxes,
      // so the glyph lands on card background rather than on the artwork —
      // and keying the colour off "this message has an image" painted a white
      // glyph onto a white card. Three live campaigns were exactly that.
      await pump(tester, message(
        imageUrl: 'https://example.com/portrait.png',
        style: const GameballMessageStyle(backgroundColor: Color(0xFFFFFFFF)),
      ));

      expect(glyph(tester), MessageMetrics.closeGlyphOnLight);
    });

    testWidgets('a campaign colour wins', (tester) async {
      await pump(tester, message(
        imageUrl: 'https://example.com/dark.png',
        style: const GameballMessageStyle(
          backgroundColor: Color(0xFFFFFFFF),
          closeButtonColor: Color(0xFFFF0000),
        ),
      ));

      expect(glyph(tester), const Color(0xFFFF0000));
    });

    testWidgets('with no background it defers to the host theme',
        (tester) async {
      await pump(tester, message());

      expect(glyph(tester), isNull,
          reason: 'null lets IconButton take the theme colour, which Material '
              'already guarantees contrasts with its own surface');
    });
  });

  group('image sizing', () {
    Future<void> pumpOn(WidgetTester tester, Size surface,
        GameballInAppMessage m) async {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester, m);
    }

    double imageCap(WidgetTester tester) => tester
        .widget<ConstrainedBox>(find.ancestor(
          of: find.byKey(const Key('gb_iam_image')),
          matching: find.byType(ConstrainedBox),
        ).first)
        .constraints
        .maxHeight;

    double cardWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('gb_iam_surface'))).width;

    testWidgets('never crops — the image is fitted, not covered', (tester) async {
      await pump(tester, message(imageUrl: 'https://example.com/a.png'));

      final image = tester.widget<Image>(find.byKey(const Key('gb_iam_image')));
      expect(image.fit, BoxFit.contain,
          reason: 'cropping would discard the design a marketer uploaded');
      expect(image.height, isNull,
          reason: 'height comes from the image aspect ratio, not a fixed band');
    });

    testWidgets('the bar threshold is a shape, identical on every device',
        (tester) async {
      // The rule this replaces capped the image at 40% of screen height while
      // the card's width came from screen width, so the ratio at which bars
      // appeared slid with the device — 1.013 on a tall phone, 1.226 on a short
      // one, and the same square image was clean on one and barred on the
      // other. Against a ratio it is one number everywhere.
      for (final surface in const [Size(390, 844), Size(414, 896)]) {
        await pumpOn(tester, surface, message(
          body: 'text alongside',
          imageUrl: 'https://example.com/a.png',
        ));

        expect(
          imageCap(tester) / cardWidth(tester),
          closeTo(1 / ModalMetrics.minImageRatio, 0.01),
          reason: 'on $surface the threshold must still be '
              '${ModalMetrics.minImageRatio}',
        );
      }
    });

    testWidgets('a portrait poster fills the card width without bars',
        (tester) async {
      // The live campaign artwork is 384x640 — ratio 0.60. Under the old cap it
      // painted 203 wide inside a 342 card and left 70 of background either
      // side. It must now fit under the cap, which is what "no bars" means.
      await pumpOn(tester, const Size(390, 844), message(
        body: 'text alongside',
        imageUrl: 'https://example.com/poster.png',
      ));

      const liveArtworkRatio = 0.6;
      expect(
        cardWidth(tester) / liveArtworkRatio,
        lessThanOrEqualTo(imageCap(tester)),
        reason: 'the poster at full card width is shorter than the cap, so it '
            'is never clamped and never letterboxed',
      );
    });

    testWidgets('artwork can never squeeze out the copy and buttons',
        (tester) async {
      // Braze has no equivalent guard: its aspect constraint simply wins, which
      // on a cramped screen means a broken constraint rather than a decision.
      const surface = Size(360, 640);
      await pumpOn(tester, surface, message(
        body: 'text alongside',
        imageUrl: 'https://example.com/tall.png',
        buttons: const [
          GameballMessageButton(
            id: 'b', text: 'Go', action: GameballDismissAction()),
        ],
      ));

      final available = surface.height - ModalMetrics.margin.vertical;
      expect(
        imageCap(tester),
        closeTo(available - ModalMetrics.copyReserve, 0.5),
        reason: 'on a short screen the reserve binds before the shape does',
      );
    });

    testWidgets('with nothing below it, the artwork keeps the whole card',
        (tester) async {
      await pumpOn(tester, const Size(390, 844), message(
        body: null,
        imageUrl: 'https://example.com/promo.png',
      ));

      expect(
        imageCap(tester) / cardWidth(tester),
        closeTo(1 / ModalMetrics.minImageRatio, 0.01),
        reason: 'no copy and no buttons means no reserve to keep',
      );
    });
  });

  group('only the copy scrolls', () {
    testWidgets('the buttons sit outside the scroll view', (tester) async {
      // The whole point of the restructure. When image, copy and buttons shared
      // one scroll view, a tall poster pushed the buttons below the fold and
      // the customer had to scroll to reach the only control that does
      // anything.
      await pump(tester, message(
        header: 'Header',
        body: 'body',
        imageUrl: 'https://example.com/a.png',
        buttons: const [
          GameballMessageButton(
            id: 'b', text: 'Go', action: GameballDismissAction()),
        ],
      ));

      expect(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_buttons')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    testWidgets('the copy is inside it, and yields to the artwork',
        (tester) async {
      await pump(tester, message(header: 'Header', body: 'body'));

      expect(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_body')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_body')),
          matching: find.byType(Flexible),
        ),
        findsWidgets,
        reason: 'Flexible is what lets the copy give way rather than the image',
      );
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
          GameballMessageButton(id: 'b1', text: 'Shop', action: GameballDismissAction()),
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
      final buttonsTapped = <String>[];
      await pump(
        tester,
        message(
          clickAction: const GameballOpenUrlAction('app://body'),
          buttons: const [
            GameballMessageButton(id: 'b8', text: 'Go', action: GameballDismissAction()),
          ],
        ),
        onButtonPressed: (b) => buttonsTapped.add(b.id),
        onMessagePressed: () => messagePressed++,
      );

      await tester.tap(find.text('Go'));
      await tester.pump();

      expect(buttonsTapped, ['b8']);
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

  group('layout: image_only', () {
    const cta = GameballMessageButton(
      id: 'cta',
      text: 'Shop the sale',
      action: GameballDismissAction(),
    );

    GameballInAppMessage imageOnly({
      String? imageUrl = 'https://example.com/poster.png',
      List<GameballMessageButton> buttons = const [cta],
      String? header = 'ignored',
      String? body = 'also ignored',
    }) =>
        message(
          layout: GameballMessageLayout.imageOnly,
          imageUrl: imageUrl,
          header: header,
          body: body,
          buttons: buttons,
        );

    testWidgets('the artwork fills the card rather than sitting above the copy',
        (tester) async {
      await pump(tester, imageOnly());

      final image = tester.widget<Image>(find.byKey(const Key('gb_iam_image')));
      expect(image.fit, BoxFit.cover,
          reason: 'the card takes the artwork\'s own ratio, so there is '
              'normally nothing to crop — cover only matters once the height '
              'cap clamps a very tall poster, and bars would defeat the '
              'composition');
    });

    testWidgets('no text is drawn, even when the campaign supplied some',
        (tester) async {
      await pump(tester, imageOnly());

      expect(find.byKey(const Key('gb_iam_header')), findsNothing);
      expect(find.byKey(const Key('gb_iam_body')), findsNothing);
    });

    testWidgets('the buttons are laid over the artwork, not beneath it',
        (tester) async {
      await pump(tester, imageOnly());

      expect(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_buttons')),
          matching: find.byType(Positioned),
        ),
        findsWidgets,
        reason: 'a Positioned in the surface Stack is what puts them over the '
            'artwork; in the default layout they sit in the content column',
      );
    });

    testWidgets('the default layout still puts its buttons in the column',
        (tester) async {
      // Guards the branch: a message with buttons and no text used to reach the
      // image-only-ish rendering by accident, and must not now be overlaid.
      await pump(tester, message(
        body: null,
        imageUrl: 'https://example.com/poster.png',
        buttons: const [cta],
      ));

      expect(
        find.ancestor(
          of: find.byKey(const Key('gb_iam_buttons')),
          matching: find.byType(Positioned),
        ),
        findsNothing,
      );
    });

    testWidgets('with no artwork it falls back to the stacked composition',
        (tester) async {
      // Otherwise this renders a blank card that still logs an impression.
      await pump(tester, imageOnly(imageUrl: null));

      expect(find.byKey(const Key('gb_iam_header')), findsOneWidget);
      expect(find.byKey(const Key('gb_iam_body')), findsOneWidget);
    });

    testWidgets('carries no button band, so there is no blank strip',
        (tester) async {
      await pump(tester, imageOnly());

      final paddings = tester.widgetList<Padding>(find.ancestor(
        of: find.byKey(const Key('gb_iam_buttons')),
        matching: find.byType(Padding),
      ));
      expect(
        paddings.where((p) => p.padding == ModalMetrics.contentPadding),
        isEmpty,
        reason: 'the content padding exists for a text block that is not here; '
            'stacking it with the button padding is what produced the 40 dead '
            'band this layout replaces',
      );
    });

    testWidgets('the close button is still drawn', (tester) async {
      await pump(tester, imageOnly());

      expect(find.byKey(const Key('gb_iam_close')), findsOneWidget);
    });
  });
}
