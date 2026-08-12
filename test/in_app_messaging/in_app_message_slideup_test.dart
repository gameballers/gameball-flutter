import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_slideup.dart';

GameballInAppMessage slideup({
  String? body = 'Your points are waiting.',
  String? header,
  String? iconUrl,
  GameballClickAction? action,
  GameballSlidePosition position = GameballSlidePosition.bottom,
  GameballMessageStyle style = const GameballMessageStyle(),
}) {
  return GameballInAppMessage(
    id: '1',
    type: GameballMessageType.slideup,
    body: body,
    header: header,
    iconUrl: iconUrl,
    clickAction: action,
    slidePosition: position,
    style: style,
  );
}

void main() {
  /// Pumps the banner inside a host screen, so "does it block the app" is
  /// answerable: the host has a button that must stay reachable.
  Future<({List<String> log,})> pumpWithHost(
    WidgetTester tester,
    GameballInAppMessage message,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Center(
              child: ElevatedButton(
                onPressed: () => log.add('host'),
                child: const Text('host button'),
              ),
            ),
            GameballInAppMessageSlideup(
              message: message,
              onMessagePressed: () => log.add('tapped'),
              onDismissRequested: () => log.add('dismissed'),
            ),
          ],
        ),
      ),
    ));
    // Let the slide-in finish, or hit tests land on a banner mid-flight.
    await tester.pumpAndSettle();
    return (log: log,);
  }

  group('rendering', () {
    testWidgets('shows the copy', (tester) async {
      await pumpWithHost(tester, slideup());

      expect(find.text('Your points are waiting.'), findsOneWidget);
    });

    testWidgets('falls back to the header when there is no body',
        (tester) async {
      await pumpWithHost(tester, slideup(body: null, header: 'From header'));

      expect(find.text('From header'), findsOneWidget);
    });

    testWidgets('truncates rather than growing to fit long copy',
        (tester) async {
      await pumpWithHost(
        tester,
        slideup(body: 'word ' * 200),
      );

      final text = tester.widget<Text>(find.byKey(const Key('gb_iam_slideup_text')));
      expect(text.maxLines, 3,
          reason: 'a banner that grew with its copy would end up covering the '
              'screen it exists not to block');
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('honours the campaign background colour', (tester) async {
      await pumpWithHost(
        tester,
        slideup(
          style: const GameballMessageStyle(backgroundColor: Color(0xFF102030)),
        ),
      );

      final surface = tester.widget<Material>(
          find.byKey(const Key('gb_iam_slideup_surface')));
      expect(surface.color, const Color(0xFF102030));
    });

    testWidgets('shows an icon when the campaign has one', (tester) async {
      await pumpWithHost(tester, slideup(iconUrl: 'https://cdn/i.png'));

      expect(find.byKey(const Key('gb_iam_slideup_icon')), findsOneWidget);
    });

    testWidgets('has no icon slot when there is none', (tester) async {
      await pumpWithHost(tester, slideup());

      expect(find.byKey(const Key('gb_iam_slideup_icon')), findsNothing);
    });
  });

  group('position', () {
    testWidgets('bottom sits below top', (tester) async {
      await pumpWithHost(tester, slideup(position: GameballSlidePosition.bottom));
      final bottomY =
          tester.getCenter(find.byKey(const Key('gb_iam_slideup_surface'))).dy;

      await pumpWithHost(tester, slideup(position: GameballSlidePosition.top));
      final topY =
          tester.getCenter(find.byKey(const Key('gb_iam_slideup_surface'))).dy;

      expect(topY, lessThan(bottomY));
    });
  });

  group('non-blocking — the point of the type', () {
    testWidgets('the app underneath stays tappable', (tester) async {
      final h = await pumpWithHost(tester, slideup());

      await tester.tap(find.text('host button'));
      await tester.pump();

      expect(h.log, ['host'],
          reason: 'a slideup occupies only its own band. A modal blocks the '
              'screen with a scrim; this must not');
    });

    testWidgets('it does not cover the whole screen', (tester) async {
      await pumpWithHost(tester, slideup());

      final size = tester.getSize(
          find.byKey(const Key('gb_iam_slideup_surface')));
      final screen = tester.getSize(find.byType(MaterialApp));

      expect(size.height, lessThan(screen.height / 3));
    });
  });

  group('interaction', () {
    testWidgets('tapping reports it when the campaign set an action',
        (tester) async {
      final h = await pumpWithHost(
        tester,
        slideup(action: const GameballDismissAction()),
      );

      await tester.tap(find.byKey(const Key('gb_iam_slideup_tap')));
      await tester.pump();

      expect(h.log, ['tapped']);
    });

    testWidgets('with no action the surface is inert and shows no chevron',
        (tester) async {
      final h = await pumpWithHost(tester, slideup());

      expect(find.byKey(const Key('gb_iam_slideup_tap')), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing,
          reason: 'the affordance has to match the behaviour');
      expect(h.log, isEmpty);
    });

    testWidgets('a chevron appears when it is tappable', (tester) async {
      await pumpWithHost(
        tester,
        slideup(action: const GameballDismissAction()),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group('swipe to dismiss — often the only way out', () {
    testWidgets('a bottom banner swipes down', (tester) async {
      final h = await pumpWithHost(
        tester,
        slideup(position: GameballSlidePosition.bottom),
      );

      await tester.fling(
        find.byKey(const Key('gb_iam_slideup_surface')),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(h.log, ['dismissed'],
          reason: 'a slideup has no close glyph and often no auto-dismiss, so '
              'without this a campaign with neither would be permanent');
    });

    testWidgets('a top banner swipes up', (tester) async {
      final h = await pumpWithHost(
        tester,
        slideup(position: GameballSlidePosition.top),
      );

      await tester.fling(
        find.byKey(const Key('gb_iam_slideup_surface')),
        const Offset(0, -300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(h.log, ['dismissed']);
    });

    testWidgets('a bottom banner does not dismiss on an upward swipe',
        (tester) async {
      final h = await pumpWithHost(
        tester,
        slideup(position: GameballSlidePosition.bottom),
      );

      await tester.fling(
        find.byKey(const Key('gb_iam_slideup_surface')),
        const Offset(0, -300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(h.log, isEmpty,
          reason: 'only towards its own edge — the other direction belongs to '
              'whatever is scrolling underneath');
    });
  });
}
