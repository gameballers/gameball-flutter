import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_fullscreen.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_modal.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_slideup.dart';

/// Geometry and reading direction — the two things every other widget test in
/// this module is blind to, because they all run in the default 800x600 window
/// at 1x text scale and in English.
///
/// Both blind spots hid real defects. Long promotional copy on a small phone
/// overflowed the modal by 296 logical pixels, and accessibility text at 2x
/// overflowed it by 1552 — which in a release build silently clips the buttons,
/// so the call to action the campaign exists for becomes unreachable. And with
/// no directional layout primitives anywhere, an Arabic message put its gaps on
/// the wrong side and pointed its chevron backwards.

/// Copy of a length a marketer will absolutely write.
const longCopy =
    'Your loyalty rewards are ready. Redeem points for discounts on your next '
    'order, unlock exclusive member pricing, and earn double points every '
    'weekend this month. Terms apply: points expire after twelve months of '
    'inactivity and cannot be combined with other promotional offers or '
    'applied retroactively to completed purchases.';

GameballMessageButton btn(String text) =>
    GameballMessageButton(id: text, text: text, action: const GameballDismissAction());

/// Pumps [child] on a viewport of [size], at [textScale], in [direction].
Future<void> pumpOn(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: reduceMotion,
    ),
    child: Directionality(
      textDirection: direction,
      child: MaterialApp(
        home: Directionality(textDirection: direction, child: Scaffold(body: child)),
      ),
    ),
  ));
}

Widget modal(GameballInAppMessage message) => GameballInAppMessageModal(
      message: message,
      onButtonPressed: (_) {},
      onClosePressed: () {},
      onMessagePressed: () {},
    );

Widget fullscreen(GameballInAppMessage message) => GameballInAppMessageFullscreen(
      message: message,
      onButtonPressed: (_) {},
      onClosePressed: () {},
      onMessagePressed: () {},
    );

void main() {
  group('the modal survives real content', () {
    testWidgets('long copy on the smallest phone still supported', (tester) async {
      await pumpOn(
        tester,
        modal(GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          header: 'Your rewards are ready',
          body: longCopy,
          buttons: [btn('Redeem now'), btn('Maybe later')],
        )),
        size: const Size(320, 568), // iPhone SE, 1st generation
      );

      expect(tester.takeException(), isNull,
          reason: 'an overflow here clips the buttons in release, so the call '
              'to action becomes unreachable');
    });

    testWidgets('accessibility text at 2x', (tester) async {
      await pumpOn(
        tester,
        modal(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          header: 'Your rewards are ready',
          body: longCopy,
        )),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull,
          reason: 'a customer who needs large text must still get the message');
    });

    testWidgets('two long localised button labels', (tester) async {
      await pumpOn(
        tester,
        modal(GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          body: 'Short.',
          buttons: [btn('Jetzt Punkte einlösen'), btn('Vielleicht später')],
        )),
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull,
          reason: 'German and Arabic labels are longer than English ones');
    });

    testWidgets('copy that does not fit becomes scrollable', (tester) async {
      await pumpOn(
        tester,
        modal(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          header: 'Your rewards are ready',
          body: longCopy,
        )),
        size: const Size(320, 568),
      );

      expect(find.byType(Scrollable), findsWidgets,
          reason: 'clipping loses content silently; scrolling does not');
    });

    testWidgets('a short message is still only as tall as its content',
        (tester) async {
      await pumpOn(
        tester,
        modal(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          body: 'Short.',
        )),
      );

      final card = tester.getSize(find.byKey(const Key('gb_iam_surface')));
      expect(card.height, lessThan(200),
          reason: 'making it scrollable must not make it full-height');
    });
  });

  group('the fullscreen stacked variant survives real content', () {
    testWidgets('long copy at 2x text scale', (tester) async {
      await pumpOn(
        tester,
        fullscreen(GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.fullscreen,
          header: 'Your rewards are ready',
          body: longCopy,
          buttons: [btn('Redeem')],
        )),
        size: const Size(360, 640),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('short copy still leaves the artwork most of the screen',
        (tester) async {
      // The fix for the overflow above bounded the copy. This pins the thing it
      // must not have cost: with short copy the image still takes whatever the
      // text does not need, which is the full-bleed look the variant exists for.
      await pumpOn(
        tester,
        fullscreen(GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.fullscreen,
          header: 'Order placed',
          imageUrl: 'https://cdn/promo.png',
          buttons: [btn('Track it')],
        )),
      );

      final image =
          tester.getSize(find.byKey(const Key('gb_iam_fullscreen_image')));
      expect(image.height, greaterThan(844 * 0.4),
          reason: 'the image is greedy, not capped at a fixed proportion');
    });
  });

  group('arriving on screen', () {
    testWidgets('the modal fades in rather than blinking into place',
        (tester) async {
      await pumpOn(
        tester,
        modal(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          body: 'Welcome back',
        )),
      );
      // First frame of the entrance.
      await tester.pump(const Duration(milliseconds: 1));

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, lessThan(1.0),
          reason: 'the slideup animates its entrance; a modal that appears '
              'instantly beside it reads as unfinished');

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1.0);
    });

    testWidgets('reduce-motion gets the message immediately, not slowly',
        (tester) async {
      await pumpOn(
        tester,
        modal(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          body: 'Welcome back',
        )),
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 1));

      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1.0,
          reason: 'someone who asked the OS for less movement gets none, not a '
              'shorter version of it');
    });

    testWidgets('the fullscreen surface fades without moving its artwork',
        (tester) async {
      await pumpOn(
        tester,
        fullscreen(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.fullscreen,
          layout: GameballMessageLayout.imageOnly,
          imageUrl: 'https://cdn/promo.png',
        )),
      );
      await tester.pump(const Duration(milliseconds: 1));

      final surface =
          tester.getSize(find.byKey(const Key('gb_iam_fullscreen_surface')));
      expect(surface, const Size(390, 844),
          reason: 'fade only — a scaling fullscreen surface would move the '
              'artwork bounds this variant is measured on');
    });
  });

  group('right to left', () {
    testWidgets("the modal's close button moves to the reading end",
        (tester) async {
      await pumpOn(
        tester,
        modal(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.modal,
          header: 'مرحبا',
          body: 'لديك نقاط جاهزة للاستبدال',
        )),
        direction: TextDirection.rtl,
      );

      final card = tester.getRect(find.byKey(const Key('gb_iam_surface')));
      final close = tester.getRect(find.byKey(const Key('gb_iam_close')));

      expect(close.center.dx, lessThan(card.center.dx),
          reason: 'in Arabic the trailing corner is the left one');
    });

    testWidgets("the fullscreen close button moves to the reading end",
        (tester) async {
      await pumpOn(
        tester,
        fullscreen(const GameballInAppMessage(
          id: 'm',
          type: GameballMessageType.fullscreen,
          header: 'مرحبا',
          body: 'لديك نقاط جاهزة',
        )),
        direction: TextDirection.rtl,
      );

      final close =
          tester.getRect(find.byKey(const Key('gb_iam_fullscreen_close')));

      expect(close.center.dx, lessThan(390 / 2),
          reason: 'in Arabic the trailing corner is the left one');
    });

    for (final (direction, expectLeft) in <(TextDirection, bool)>[
      (TextDirection.ltr, false),
      (TextDirection.rtl, true),
    ]) {
      testWidgets(
          'the slideup chevron points the way the text reads '
          '(${direction.name})', (tester) async {
        await pumpOn(
          tester,
          GameballInAppMessageSlideup(
            message: const GameballInAppMessage(
              id: 'm',
              type: GameballMessageType.slideup,
              body: 'لديك نقاط جاهزة للاستبدال',
              clickAction: GameballDismissAction(),
            ),
            onMessagePressed: () {},
            onDismissRequested: () {},
          ),
          direction: direction,
        );
        await tester.pumpAndSettle();

        // Which icon was chosen is not the question — which way it is painted
        // is. Both chevrons carry `matchTextDirection: true`, so under RTL the
        // Icon widget mirrors the glyph before painting it and a `chevron_left`
        // comes out pointing right. The previous assertion here compared the
        // codepoint, so it passed against exactly that defect: the icon was
        // swapped by hand *and* mirrored by Flutter, and Arabic customers saw a
        // chevron pointing backwards for as long as this test was green.
        final icon = tester.widget<Icon>(find.byType(Icon));
        final mirrored =
            icon.icon!.matchTextDirection && direction == TextDirection.rtl;
        final pointsLeft = (icon.icon == Icons.chevron_left) != mirrored;

        expect(pointsLeft, expectLeft,
            reason: 'a right-pointing chevron in Arabic points backwards');
      });
    }

    testWidgets('the slideup icon sits at the leading edge for the reader',
        (tester) async {
      await pumpOn(
        tester,
        GameballInAppMessageSlideup(
          message: const GameballInAppMessage(
            id: 'm',
            type: GameballMessageType.slideup,
            body: 'لديك نقاط',
            iconUrl: 'https://cdn/icon.png',
          ),
          onMessagePressed: () {},
          onDismissRequested: () {},
        ),
        direction: TextDirection.rtl,
      );
      await tester.pumpAndSettle();

      final icon = tester.getRect(find.byKey(const Key('gb_iam_slideup_icon')));
      final text = tester.getRect(find.byKey(const Key('gb_iam_slideup_text')));

      expect(icon.center.dx, greaterThan(text.center.dx),
          reason: 'the reader starts on the right in Arabic');
    });
  });
}
