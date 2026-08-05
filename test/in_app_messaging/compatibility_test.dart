import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/requests/event.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';

void main() {
  GameballApp app() => GameballApp.getInstance();

  setUp(() {
    // Static state is shared across tests; leave every test a clean module.
    app().stopInAppMessaging();
  });

  group('the module is inert until started', () {
    test('a fresh SDK reports in-app messaging as not started', () {
      expect(app().isInAppMessagingStarted, isFalse);
    });

    test('nothing is pending before start', () {
      expect(app().pendingInAppMessageCampaign, isNull);
    });

    testWidgets('no overlay is inserted when start is never called', (tester) async {
      final key = GlobalKey<NavigatorState>();
      app().init(GameballConfigBuilder().apiKey('test-key').lang('en').build());

      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('host screen')),
      ));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('host screen'), findsOneWidget);
      expect(app().isInAppMessagingStarted, isFalse);
    });

    testWidgets('sendEvent does not start in-app messaging', (tester) async {
      app().init(GameballConfigBuilder().apiKey('test-key').lang('en').build());

      // `sendEvent` attaches `.then()` with no `catchError`, so the 400 that
      // TestWidgetsFlutterBinding returns for every request escapes as an
      // unhandled async error. That is a PRE-EXISTING SDK defect, documented
      // and deliberately out of scope here, so it is captured in a guarded zone
      // rather than allowed to fail a test that is about something else.
      final escaped = <Object>[];
      await tester.runAsync(() async {
        await runZonedGuarded(
          () async {
            app().sendEvent(
              EventBuilder().customerId('c1').eventName('add_to_cart').build(),
              // Language version is 3.4 here (pubspec pins sdk >=3.4.4), which
              // predates wildcard `_` parameters, so the second must be named.
              (_, __) {},
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
          },
          (error, stack) => escaped.add(error),
        );
      });

      expect(
        escaped.map((e) => e.toString()).join('\n'),
        contains('Failed to send event'),
        reason: 'documents the pre-existing missing catchError; if this stops '
            'escaping, that defect was fixed and this zone can be removed',
      );
      expect(app().isInAppMessagingStarted, isFalse,
          reason: 'the additive hook must never start the module');
    });

    test('stopInAppMessaging before any start is a no-op', () {
      expect(app().stopInAppMessaging, returnsNormally);
    });
  });

  group('lifecycle guards', () {
    test('start without a valid config is ignored rather than throwing', () {
      expect(
        () => app().startInAppMessaging(
          customerId: 'c1',
          navigatorKey: GlobalKey<NavigatorState>(),
        ),
        returnsNormally,
      );
    });
  });

  group('observation stream', () {
    test('onInAppMessage can be subscribed before start', () async {
      final received = <GameballInAppMessage>[];
      final sub = app().onInAppMessage.listen(received.add);
      addTearDown(sub.cancel);

      expect(received, isEmpty);
    });

    test('onInAppMessage returns a broadcast stream usable more than once', () {
      final a = app().onInAppMessage;
      final b = app().onInAppMessage;

      expect(a.isBroadcast, isTrue);
      final subA = a.listen((_) {});
      final subB = b.listen((_) {});
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);
    });
  });

  group('public surface is exported from the single import', () {
    test('the in-app messaging types resolve via gameball_sdk.dart', () {
      // Compile-time assertion: if the barrel export is missing, this file
      // will not compile at all.
      const decision = GameballDisplayDecision.show;
      const type = GameballMessageType.modal;
      const action = GameballDismissAction();
      const trigger = GameballSessionStartTrigger();

      expect(decision, GameballDisplayDecision.show);
      expect(type, GameballMessageType.modal);
      expect(action, isA<GameballClickAction>());
      expect(trigger, isA<GameballMessageTrigger>());
    });
  });
}
