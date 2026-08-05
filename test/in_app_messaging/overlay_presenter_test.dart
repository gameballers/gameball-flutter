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
    final tapped = <int>[];

    presenter.present(
      message: message(buttons: const [
        GameballMessageButton(id: 3, text: 'Go', action: GameballDismissAction()),
      ]),
      onShown: () {},
      onButtonPressed: (b) => tapped.add(b.id),
      onMessagePressed: () {},
      onDismissed: () {},
    );
    await tester.pump();

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(tapped, [3],
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
}
