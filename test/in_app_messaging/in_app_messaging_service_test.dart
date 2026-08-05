import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/message_analytics.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/in_app_messaging_service.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_presenter.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';

// ---------------------------------------------------------------- test doubles

class FakeSource implements GameballMessageSource {
  FakeSource(this.campaigns);

  List<InAppMessageCampaign> campaigns;
  Object? throwOnFetch;
  int fetchCount = 0;
  GameballAudience? lastAudience;

  @override
  Future<List<InAppMessageCampaign>> fetch(GameballAudience audience) async {
    fetchCount++;
    lastAudience = audience;
    final error = throwOnFetch;
    if (error != null) throw error;
    return campaigns;
  }
}

class FakePresenter implements GameballMessagePresenter {
  bool available = true;
  bool _showing = false;

  final List<String> shownMessageIds = <String>[];
  VoidCallback? _onDismissed;
  void Function(GameballMessageButton)? _onButtonPressed;

  @override
  bool get isShowing => _showing;

  @override
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onDismissed,
  }) {
    if (!available || _showing) return false;
    _showing = true;
    _onDismissed = onDismissed;
    _onButtonPressed = onButtonPressed;
    shownMessageIds.add(message.id);
    onShown();
    return true;
  }

  @override
  void dismiss() {
    if (!_showing) return;
    _showing = false;
    final onDismissed = _onDismissed;
    _onDismissed = null;
    _onButtonPressed = null;
    onDismissed?.call();
  }

  /// Simulates the user tapping a button.
  void tapButton(GameballMessageButton button) => _onButtonPressed?.call(button);
}

class RecordingAnalytics implements MessageAnalytics {
  final List<String> impressions = <String>[];
  final List<String> clicks = <String>[];

  @override
  void logImpression(GameballInAppMessage message, {required String campaignId}) {
    impressions.add('$campaignId/${message.id}');
  }

  @override
  void logButtonClick(
    GameballInAppMessage message, {
    required String campaignId,
    required int buttonId,
  }) {
    clicks.add('$campaignId/${message.id}/$buttonId');
  }
}

// ------------------------------------------------------------------- fixtures

final DateTime t0 = DateTime.utc(2026, 8, 5, 12);

InAppMessageCampaign campaign(
  String id, {
  GameballMessageTrigger trigger = const GameballSessionStartTrigger(),
  int priority = 0,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
}) {
  return InAppMessageCampaign(
    id: id,
    trigger: trigger,
    priority: priority,
    message: GameballInAppMessage(
      id: 'msg_$id',
      type: GameballMessageType.modal,
      body: 'body',
      buttons: buttons,
    ),
  );
}

/// Assembles a service with controllable collaborators.
({
  InAppMessagingService service,
  FakeSource source,
  FakePresenter presenter,
  RecordingAnalytics analytics,
  InMemoryFrequencyCap cap,
  List<GameballInAppMessage> emitted,
  void Function(bool) setWidgetOpen,
  void Function(DateTime) setNow,
}) build({List<InAppMessageCampaign>? campaigns}) {
  final source = FakeSource(campaigns ?? [campaign('a')]);
  final presenter = FakePresenter();
  final analytics = RecordingAnalytics();
  final cap = InMemoryFrequencyCap();
  final emitted = <GameballInAppMessage>[];
  var widgetOpen = false;
  var now = t0;

  final service = InAppMessagingService(
    source: source,
    presenter: presenter,
    frequencyCap: cap,
    analytics: analytics,
    isHostWidgetOpen: () => widgetOpen,
    emit: emitted.add,
    clock: () => now,
    launcher: (uri, {bool external = false}) async => true,
  );

  return (
    service: service,
    source: source,
    presenter: presenter,
    analytics: analytics,
    cap: cap,
    emitted: emitted,
    setWidgetOpen: (v) => widgetOpen = v,
    setNow: (v) => now = v,
  );
}

void main() {
  group('start', () {
    test('fetches once and displays the session-start message', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.source.fetchCount, 1);
      expect(h.source.lastAudience, isA<CustomerAudience>());
      expect(h.presenter.shownMessageIds, ['msg_a']);
      expect(h.service.isStarted, isTrue);
    });

    test('logs an impression and records the cap at display', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.analytics.impressions, ['a/msg_a']);
      expect(h.cap.snapshot().shownCampaignIds, {'a'});
      expect(h.cap.snapshot().lastDisplayAt, t0);
    });

    test('emits the message for observers', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.emitted.map((m) => m.id), ['msg_a']);
    });

    test('a second start for the same customer does not refetch', () async {
      final h = build();

      await h.service.start(customerId: 'c1');
      await h.service.start(customerId: 'c1');

      expect(h.source.fetchCount, 1);
    });

    test('a fetch failure leaves no campaigns and does not throw', () async {
      final h = build();
      h.source.throwOnFetch = Exception('network down');

      await expectLater(h.service.start(customerId: 'c1'), completes);

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.isStarted, isTrue);
    });
  });

  group('custom event trigger', () {
    test('displays a matching campaign', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, ['msg_cart']);
    });

    test('ignores a non-matching event', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onCustomEvent('checkout');

      expect(h.presenter.shownMessageIds, isEmpty);
    });

    test('does nothing before start', () {
      final h = build();

      h.service.onCustomEvent('add_to_cart');

      expect(h.source.fetchCount, 0);
      expect(h.presenter.shownMessageIds, isEmpty);
    });
  });

  group('deferral and retry', () {
    test('defers while the host widget is open', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setWidgetOpen(true);

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign?.id, 'cart');
    });

    test('displays the pending message once the widget closes', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setWidgetOpen(true);
      h.service.onCustomEvent('add_to_cart');

      h.setWidgetOpen(false);
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_cart']);
      expect(h.service.pendingCampaign, isNull);
    });

    test('a trigger inside the floor is dropped, not deferred', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1'); // shows 'first' at t0
      h.presenter.dismiss();

      // Only 5s since the last display, so the floor blocks selection outright.
      h.setNow(t0.add(const Duration(seconds: 5)));
      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, ['msg_first']);
      expect(h.service.pendingCampaign, isNull,
          reason: 'rate-limited messages are dropped, not queued — deferral is '
              'for blocked display, not for cap violations');
    });

    test('a retry re-validates the floor rather than bypassing it', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1'); // shows 'first' at t0
      h.presenter.dismiss();

      // Floor is clear, so the event selects 'cart', but the widget blocks it.
      h.setNow(t0.add(const Duration(seconds: 31)));
      h.setWidgetOpen(true);
      h.service.onCustomEvent('add_to_cart');
      expect(h.service.pendingCampaign?.id, 'cart');

      // Another message lands while 'cart' waits, moving the floor forward.
      h.cap.recordDisplay('other', t0.add(const Duration(seconds: 40)));
      h.setNow(t0.add(const Duration(seconds: 45)));

      h.setWidgetOpen(false);
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_first'],
          reason: 'only 5s since the intervening display, so the floor holds');
      expect(h.service.pendingCampaign?.id, 'cart', reason: 'it stays pending');

      // Once the new floor has elapsed, the same retry path displays it.
      h.setNow(t0.add(const Duration(seconds: 75)));
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_first', 'msg_cart']);
    });

    test('a pending message displays once the widget closes', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();

      h.setNow(t0.add(const Duration(seconds: 31)));
      h.setWidgetOpen(true);
      h.service.onCustomEvent('add_to_cart');
      h.setWidgetOpen(false);
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_first', 'msg_cart']);
    });

    test('a pending message already shown is dropped rather than repeated', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');

      // Show it normally, then force it pending and mark it shown.
      h.service.onCustomEvent('add_to_cart');
      expect(h.presenter.shownMessageIds, ['msg_cart']);
      h.setWidgetOpen(true);
      h.setNow(t0.add(const Duration(seconds: 60)));
      h.service.onCustomEvent('add_to_cart');

      expect(h.service.pendingCampaign, isNull,
          reason: 'an already-shown campaign is never selected again');
    });

    test('defers when a message is already showing', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setNow(t0.add(const Duration(seconds: 31)));

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, ['msg_first']);
      expect(h.service.pendingCampaign?.id, 'cart');
    });

    test('the pending message displays when the current one is dismissed', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setNow(t0.add(const Duration(seconds: 31)));
      h.service.onCustomEvent('add_to_cart');

      h.presenter.dismiss();

      expect(h.presenter.shownMessageIds, ['msg_first', 'msg_cart']);
    });

    test('a newer deferral displaces an older one', () async {
      final h = build(campaigns: [
        campaign('one', trigger: const GameballCustomEventTrigger('e1')),
        campaign('two', trigger: const GameballCustomEventTrigger('e2')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setWidgetOpen(true);

      h.service.onCustomEvent('e1');
      h.service.onCustomEvent('e2');

      expect(h.service.pendingCampaign?.id, 'two');
    });
  });

  group('beforeDisplay hook', () {
    test('discard prevents display and leaves nothing pending', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => GameballDisplayDecision.discard,
      );

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign, isNull);
    });

    test('later defers using the same pending slot', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => GameballDisplayDecision.later,
      );

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign?.id, 'a');
    });

    test('show displays as normal', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => GameballDisplayDecision.show,
      );

      expect(h.presenter.shownMessageIds, ['msg_a']);
    });

    test('a throwing hook falls back to show', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => throw StateError('host bug'),
      );

      expect(h.presenter.shownMessageIds, ['msg_a'],
          reason: 'the no-hook default is show, so falling back to it is least surprising');
    });

    test('the hook still receives messages it will not see displayed', () async {
      final seen = <String>[];
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (m) {
          seen.add(m.id);
          return GameballDisplayDecision.discard;
        },
      );

      expect(seen, ['msg_a']);
    });
  });

  group('button taps', () {
    test('a tap logs a click and dismisses', () async {
      final h = build(campaigns: [
        campaign('a', buttons: const [
          GameballMessageButton(id: 4, text: 'Go', action: GameballDismissAction()),
        ]),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapButton(const GameballMessageButton(
        id: 4,
        text: 'Go',
        action: GameballDismissAction(),
      ));

      expect(h.analytics.clicks, ['a/msg_a/4']);
      expect(h.presenter.isShowing, isFalse);
    });
  });

  group('customer changes', () {
    test('a new customer refetches and resets caps', () async {
      final h = build();
      await h.service.start(customerId: 'c1');
      expect(h.cap.snapshot().shownCampaignIds, {'a'});

      h.service.onCustomerChanged('c2');
      await Future<void>.delayed(Duration.zero);

      expect(h.source.fetchCount, 2);
      expect((h.source.lastAudience! as CustomerAudience).customerId, 'c2');
    });

    test('the same customer does not refetch', () async {
      final h = build();
      await h.service.start(customerId: 'c1');

      h.service.onCustomerChanged('c1');
      await Future<void>.delayed(Duration.zero);

      expect(h.source.fetchCount, 1);
    });

    test('does nothing before start', () async {
      final h = build();

      h.service.onCustomerChanged('c1');
      await Future<void>.delayed(Duration.zero);

      expect(h.source.fetchCount, 0);
    });
  });

  group('stop', () {
    test('dismisses, clears pending, and forgets the customer', () async {
      final h = build();
      await h.service.start(customerId: 'c1');

      h.service.stop();

      expect(h.presenter.isShowing, isFalse);
      expect(h.service.isStarted, isFalse);
      expect(h.service.pendingCampaign, isNull);
      expect(h.cap.snapshot().shownCampaignIds, isEmpty);
    });

    test('is a no-op when not started', () {
      final h = build();

      expect(h.service.stop, returnsNormally);
    });

    test('events after stop are ignored', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.service.stop();

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, isEmpty);
    });
  });

  group('no presentation surface', () {
    testWidgets('defers when the presenter cannot draw', (tester) async {
      final h = build();
      h.presenter.available = false;

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign?.id, 'a');
    });

    testWidgets('displays on retry once a surface appears', (tester) async {
      final h = build();
      h.presenter.available = false;
      await h.service.start(customerId: 'c1');

      h.presenter.available = true;
      h.service.onHostWidgetClosed(); // any retry trigger

      expect(h.presenter.shownMessageIds, ['msg_a']);
    });
  });
}
