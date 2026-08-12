import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/overlay_presenter.dart';

GameballInAppMessage message({
  Duration? autoDismissAfter,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
}) {
  return GameballInAppMessage(
    id: 'msg',
    type: GameballMessageType.modal,
    body: 'body text',
    autoDismissAfter: autoDismissAfter,
    buttons: buttons,
  );
}

/// Pumps an app with a navigator key the presenter can draw into.
Future<GlobalKey<NavigatorState>> pumpHost(WidgetTester tester) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: key,
    home: const Scaffold(body: Text('host screen')),
  ));
  return key;
}

void main() {
  testWidgets('present inserts the modal and reports shown', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var shown = 0;

    final inserted = presenter.present(
      message: message(),
      onShown: () => shown++,
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () {},
    );
    await tester.pump();

    expect(inserted, isTrue);
    expect(shown, 1);
    expect(presenter.isShowing, isTrue);
    expect(find.text('body text'), findsOneWidget);
    expect(find.text('host screen'), findsOneWidget,
        reason: 'the overlay draws above the host without replacing it');
  });

  testWidgets('present returns false when there is no navigator', (tester) async {
    final presenter = OverlayPresenter(GlobalKey<NavigatorState>());

    final inserted = presenter.present(
      message: message(),
      onShown: () => fail('must not report shown'),
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () => fail('must not report dismissed'),
    );

    expect(inserted, isFalse);
    expect(presenter.isShowing, isFalse);
  });

  testWidgets('present refuses to stack a second message', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () {},
    );
    await tester.pump();

    final second = presenter.present(
      message: message(),
      onShown: () => fail('must not show a second message'),
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () {},
    );

    expect(second, isFalse);
  });

  testWidgets('dismiss removes the overlay and reports dismissed once', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    presenter.dismiss();
    presenter.dismiss(); // second call must be a no-op
    await tester.pump();

    expect(dismissed, 1);
    expect(presenter.isShowing, isFalse);
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('tapping the scrim dismisses', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(dismissed, 1);
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('tapping a button reports it without dismissing', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    final tapped = <String>[];

    presenter.present(
      message: message(buttons: const [
        GameballMessageButton(id: 'b4', text: 'Go', action: GameballDismissAction()),
      ]),
      onShown: () {},
      onButtonPressed: (b) => tapped.add(b.id),
      onMessagePressed: () {},
      onDismissed: () {},
    );
    await tester.pump();

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(tapped, ['b4'],
        reason: 'the service decides what a tap means; the presenter only reports it');
  });

  testWidgets('auto-dismiss fires after the configured delay', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(autoDismissAfter: const Duration(seconds: 3)),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    expect(dismissed, 0);
    await tester.pump(const Duration(seconds: 3));

    expect(dismissed, 1);
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('a manual dismiss cancels the auto-dismiss timer', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(autoDismissAfter: const Duration(seconds: 3)),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    presenter.dismiss();
    await tester.pump(const Duration(seconds: 5));

    expect(dismissed, 1, reason: 'the pending timer must not fire a second dismissal');
  });

  testWidgets('a message can be presented again after dismissal', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () {},
    );
    await tester.pump();
    presenter.dismiss();
    await tester.pump();

    final again = presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onMessagePressed: () {},
      onDismissed: () {},
    );
    await tester.pump();

    expect(again, isTrue);
    expect(find.text('body text'), findsOneWidget);
  });

  group('the presenter picks a layer by type', () {
    testWidgets('a modal gets a blocking scrim', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final presenter = OverlayPresenter(key);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('host')),
      ));

      presenter.present(
        message: const GameballInAppMessage(
          id: '1',
          type: GameballMessageType.modal,
          body: 'blocking',
        ),
        onShown: () {},
        onButtonPressed: (_) {},
        onMessagePressed: () {},
        onDismissed: () {},
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gb_iam_surface')), findsOneWidget);
      expect(find.byKey(const Key('gb_iam_slideup_surface')), findsNothing);
    });

    testWidgets('a slideup gets no scrim, so the host stays reachable',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      final presenter = OverlayPresenter(key);
      var hostTaps = 0;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => hostTaps++,
              child: const Text('host button'),
            ),
          ),
        ),
      ));

      presenter.present(
        message: const GameballInAppMessage(
          id: '1',
          type: GameballMessageType.slideup,
          body: 'non-blocking',
        ),
        onShown: () {},
        onButtonPressed: (_) {},
        onMessagePressed: () {},
        onDismissed: () {},
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gb_iam_slideup_surface')), findsOneWidget);
      expect(find.byKey(const Key('gb_iam_surface')), findsNothing);

      await tester.tap(find.text('host button'));
      await tester.pump();

      expect(hostTaps, 1,
          reason: 'the whole reason slideup is a separate layer: a modal fills '
              'the overlay with a scrim that swallows every tap, and a slideup '
              'must not');
      presenter.dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('a modal with closeBehaviour button ignores a scrim tap',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      final presenter = OverlayPresenter(key);
      var dismissals = 0;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('host')),
      ));

      presenter.present(
        message: const GameballInAppMessage(
          id: '1',
          type: GameballMessageType.modal,
          body: 'close button only',
          dismissOnScrimTap: false,
        ),
        onShown: () {},
        onButtonPressed: (_) {},
        onMessagePressed: () {},
        onDismissed: () => dismissals++,
      );
      await tester.pumpAndSettle();

      // Well outside the card, on the scrim.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(dismissals, 0,
          reason: 'the live campaign 2052 sends closeBehaviour "button", so a '
              'tap outside must do nothing');
      presenter.dismiss();
      await tester.pumpAndSettle();
    });
  });
}
