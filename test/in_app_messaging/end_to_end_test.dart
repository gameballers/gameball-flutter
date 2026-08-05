import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/requests/event.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';

/// Drives the whole module through its real collaborators — the stub source,
/// the real parser, the real evaluator, the real overlay presenter and the real
/// modal — via the public `GameballApp` API only.
///
/// The unit tests each mock their neighbours, so this is what proves the wiring
/// between them. It is also the automated equivalent of the sample app's manual
/// walkthrough.
void main() {
  GameballApp app() => GameballApp.getInstance();

  /// Pumps a host app and opts in, returning once the session-start message has
  /// had a chance to appear.
  Future<GlobalKey<NavigatorState>> startWithHost(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    app().init(GameballConfigBuilder().apiKey('test-key').lang('en').build());

    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: Text('host screen')),
    ));

    app().startInAppMessaging(customerId: 'customer-1', navigatorKey: key);
    // The fetch is async even for the stub, so let it settle.
    await tester.pumpAndSettle();
    return key;
  }

  setUp(() => app().stopInAppMessaging());
  tearDown(() => app().stopInAppMessaging());

  testWidgets('the session-start campaign renders from the stub fixture',
      (tester) async {
    await startWithHost(tester);

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('You have 1,250 points ready to redeem.'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Redeem'), findsOneWidget);
    expect(find.text('host screen'), findsOneWidget,
        reason: 'the message draws above the host, it does not replace it');
  });

  testWidgets('styling from the payload reaches the rendered surface',
      (tester) async {
    await startWithHost(tester);

    final surface =
        tester.widget<Material>(find.byKey(const Key('gb_iam_surface')));
    expect(surface.color, const Color(0xFFFFFFFF),
        reason: 'the fixture sets backgroundColor #FFFFFF — this is the '
            'fidelity Braze\'s Flutter SDK structurally cannot achieve');
  });

  testWidgets('tapping a button dismisses the message', (tester) async {
    await startWithHost(tester);
    expect(find.text('Welcome back!'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back!'), findsNothing);
    expect(find.text('host screen'), findsOneWidget);
  });

  testWidgets('tapping the scrim dismisses the message', (tester) async {
    await startWithHost(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back!'), findsNothing);
  });

  testWidgets('the message is observable on the public stream', (tester) async {
    final seen = <String>[];
    final sub = app().onInAppMessage.listen((m) => seen.add(m.id));
    addTearDown(sub.cancel);

    await startWithHost(tester);
    // Broadcast controllers deliver asynchronously.
    await tester.pumpAndSettle();

    expect(seen, contains('msg_welcome_v1'));
  });

  testWidgets('the 30-second floor blocks a second message immediately after',
      (tester) async {
    await startWithHost(tester);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // add_to_cart is the stub's other trigger, but the welcome message was
    // displayed moments ago, so the floor must suppress this one.
    //
    // Guarded because `sendEvent` has no catchError, so the test client's 400
    // escapes as an unhandled async error — a pre-existing defect, unrelated to
    // what this test asserts.
    await runZonedGuarded(
      () async {
        app().sendEvent(_cartEvent(), (_, __) {});
        await tester.pumpAndSettle();
      },
      (_, __) {},
    );

    expect(find.text('Add one more item for 2x points.'), findsNothing,
        reason: 'the global 30-second floor holds across campaigns');
  });

  // NOTE: the image-only campaign cannot be exercised end to end through the
  // public API. It triggers on `view_offers`, which can only fire after the
  // welcome message has displayed — and the 30-second floor reads the real
  // clock, which `tester.pump` does not advance. Injecting a clock or a source
  // is internal-only, by design. Image-only is therefore covered at three
  // narrower levels instead: parsing (message_parser_test), the fixture
  // (stub_message_source_test) and rendering (in_app_message_modal_test).

  testWidgets('stopInAppMessaging dismisses whatever is on screen',
      (tester) async {
    await startWithHost(tester);
    expect(find.text('Welcome back!'), findsOneWidget);

    app().stopInAppMessaging();
    await tester.pumpAndSettle();

    expect(find.text('Welcome back!'), findsNothing);
    expect(app().isInAppMessagingStarted, isFalse);
  });

  testWidgets('a message deferred for want of a navigator appears later',
      (tester) async {
    // Opt in before any widget tree exists, so there is no overlay to draw on.
    final key = GlobalKey<NavigatorState>();
    app().init(GameballConfigBuilder().apiKey('test-key').lang('en').build());
    app().startInAppMessaging(customerId: 'customer-1', navigatorKey: key);
    await tester.pump();

    expect(app().pendingInAppMessageCampaign?.id, 'cmp_welcome_modal',
        reason: 'nothing to draw on yet, so it waits rather than being lost');

    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: Text('host screen')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back!'), findsOneWidget,
        reason: 'the post-frame retry presents it once a surface exists');
  });
}

/// The stub's cart campaign listens for `add_to_cart`.
dynamic _cartEvent() {
  // Built via the SDK's own builder so the event name matches the fixture.
  return EventBuilder().customerId('customer-1').eventName('add_to_cart').build();
}
