import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/message_analytics.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/message_event.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/in_app_messaging_service.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/models/property_filter.dart';
import 'package:gameball_sdk/in_app_messaging/personalisation/variable_source.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/artwork_prefetcher.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_navigator.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_presenter.dart';
import 'package:gameball_sdk/in_app_messaging/source/campaign_cache.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';

// ---------------------------------------------------------------- test doubles

class FakeSource implements GameballMessageSource {
  FakeSource(this.campaigns);

  List<InAppMessageCampaign> campaigns;
  Object? throwOnFetch;
  int fetchCount = 0;
  GameballAudience? lastAudience;

  /// What the next sync reports as the global cooldown.
  Duration cooldown = defaultDisplayCooldown;

  /// The payload the sync "arrived as". Null by default, because a source with no
  /// raw response — as this fake is — has nothing for the cache to store, and the
  /// service must not invent one.
  String? rawJson;

  @override
  Future<GameballSyncResult> fetch(GameballAudience audience) async {
    fetchCount++;
    lastAudience = audience;
    final error = throwOnFetch;
    if (error != null) throw error;
    return GameballSyncResult(
      campaigns: campaigns,
      cooldown: cooldown,
      rawJson: rawJson,
    );
  }
}

class FakePresenter implements GameballMessagePresenter {
  bool available = true;
  bool _showing = false;

  final List<String> shownMessageIds = <String>[];

  /// What the presenter was actually handed, which personalisation changes.
  final List<String?> shownHeaders = <String?>[];
  final List<String?> shownBodies = <String?>[];
  VoidCallback? _onDismissed;
  void Function(GameballMessageButton)? _onButtonPressed;
  VoidCallback? _onMessagePressed;

  @override
  bool get isShowing => _showing;

  @override
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onMessagePressed,
    required VoidCallback onDismissed,
  }) {
    if (!available || _showing) return false;
    _showing = true;
    _onDismissed = onDismissed;
    _onButtonPressed = onButtonPressed;
    _onMessagePressed = onMessagePressed;
    shownMessageIds.add(message.id);
    shownHeaders.add(message.header);
    shownBodies.add(message.body);
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
    _onMessagePressed = null;
    onDismissed?.call();
  }

  /// Simulates the user tapping a button.
  void tapButton(GameballMessageButton button) => _onButtonPressed?.call(button);

  /// Simulates the user tapping the message surface.
  void tapMessage() => _onMessagePressed?.call();
}

class FakeArtworkPrefetcher implements ArtworkPrefetcher {
  /// Message ids whose artwork fails to load. Everything else is ready.
  final Set<String> failing = <String>{};

  /// Message ids whose prefetch never answers, for the timeout bound.
  final Set<String> hanging = <String>{};

  /// Every message offered for warming, in order.
  final List<String> requested = <String>[];

  @override
  Future<bool> prefetch(GameballInAppMessage message) {
    requested.add(message.id);
    if (hanging.contains(message.id)) return Completer<bool>().future;
    return Future<bool>.value(!failing.contains(message.id));
  }
}

class FakeVariableSource implements VariableSource {
  Map<String, String> values = const <String, String>{};
  bool hang = false;
  int fetches = 0;

  @override
  Future<Map<String, String>> fetch(String customerId) {
    fetches++;
    if (hang) return Completer<Map<String, String>>().future;
    return Future<Map<String, String>>.value(values);
  }
}

class RecordingNavigator implements MessageNavigator {
  bool available = true;
  final List<String> pushed = <String>[];
  Object? lastArguments;

  @override
  bool pushNamed(String route, {Object? arguments}) {
    if (!available) return false;
    pushed.add(route);
    lastArguments = arguments;
    return true;
  }
}

class RecordingAnalytics implements MessageAnalytics {
  final List<GameballMessageEvent> events = <GameballMessageEvent>[];
  int flushes = 0;
  int loads = 0;

  /// Reported back as the test's own campaign labels, so assertions stay legible
  /// now that the wire identity is a number.
  List<String> _labels(GameballMessageEventType type) => events
      .where((e) => e.type == type)
      .map((e) => labelOf(e.campaignId))
      .toList();

  List<String> get impressions => _labels(GameballMessageEventType.impression);
  List<String> get dismissals => _labels(GameballMessageEventType.dismiss);

  /// A click with no button: the message surface itself was tapped.
  ///
  /// Button clicks and surface clicks share one wire type now, and `buttonId`
  /// presence is the only thing that distinguishes them — so splitting them here
  /// is what proves the merge kept them distinguishable.
  List<String> get bodyClicks => events
      .where((e) =>
          e.type == GameballMessageEventType.click && e.buttonId == null)
      .map((e) => labelOf(e.campaignId))
      .toList();

  List<String> get clicks => events
      .where((e) =>
          e.type == GameballMessageEventType.click && e.buttonId != null)
      .map((e) => '${labelOf(e.campaignId)}/${e.buttonId}')
      .toList();

  @override
  Future<void> load() async => loads++;

  @override
  void log(GameballMessageEvent event) => events.add(event);

  /// Makes a flush take time, for the pre-action bound.
  Duration? flushDelay;

  @override
  Future<void> flush() async {
    flushes++;
    final delay = flushDelay;
    if (delay != null) await Future<void>.delayed(delay);
  }

  @override
  void dispose() => disposals++;

  int disposals = 0;
}

// ------------------------------------------------------------------- fixtures

final DateTime t0 = DateTime.utc(2026, 8, 5, 12);

/// Campaigns are keyed by the backend's numeric id, but these tests read better
/// with names. [idFor] hands out a stable id per label, and [labelOf] maps back so
/// analytics assertions can name the campaign they mean.
final Map<String, int> _idsByLabel = <String, int>{};
int idFor(String label) =>
    _idsByLabel.putIfAbsent(label, () => 2000 + _idsByLabel.length);
String labelOf(int campaignId) => _idsByLabel.entries
    .firstWhere((e) => e.value == campaignId,
        orElse: () => MapEntry('#$campaignId', campaignId))
    .key;

InAppMessageCampaign campaign(
  String label, {
  GameballMessageTrigger trigger = const GameballSessionStartTrigger(),
  int priority = 0,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
  GameballClickAction? clickAction,
  String? dispatchId,
  bool isTest = false,
  DateTime? expiresAt,
}) {
  return InAppMessageCampaign(
    campaignId: idFor(label),
    trigger: trigger,
    priority: priority,
    dispatchId: dispatchId,
    isTest: isTest,
    expiresAt: expiresAt,
    message: GameballInAppMessage(
      id: 'msg_$label',
      type: GameballMessageType.modal,
      body: 'body',
      buttons: buttons,
      clickAction: clickAction,
    ),
  );
}

/// A real sync response, for seeding the cache — which stores payloads, not the
/// constructed campaigns the fake source hands out.
String rawSync({int campaignId = 2041, String body = 'cached body'}) => '''
{
  "cooldownSeconds": 30,
  "messages": [
    { "campaignId": $campaignId, "messageType": 2,
      "trigger": {"type": "session_start"},
      "content": {}, "locale": {"message": "$body"} }
  ]
}
''';

/// Assembles a service with controllable collaborators.
({
  InAppMessagingService service,
  FakeSource source,
  FakePresenter presenter,
  RecordingAnalytics analytics,
  InMemoryFrequencyCap cap,
  InMemoryCampaignCache cache,
  RecordingNavigator navigator,
  FakeArtworkPrefetcher prefetcher,
  FakeVariableSource variables,
  List<GameballInAppMessage> emitted,
  void Function(bool) setWidgetOpen,
  void Function(DateTime) setNow,
}) build({
  List<InAppMessageCampaign>? campaigns,
  InMemoryCampaignCache? cache,
  Duration? prefetchTimeout,
  Duration? variableTimeout,
}) {
  final source = FakeSource(campaigns ?? [campaign('a')]);
  final presenter = FakePresenter();
  final analytics = RecordingAnalytics();
  final cap = InMemoryFrequencyCap();
  final theCache = cache ?? InMemoryCampaignCache();
  final navigator = RecordingNavigator();
  final prefetcher = FakeArtworkPrefetcher();
  final variables = FakeVariableSource();
  final emitted = <GameballInAppMessage>[];
  var widgetOpen = false;
  var now = t0;

  final service = InAppMessagingService(
    source: source,
    presenter: presenter,
    frequencyCap: cap,
    campaignCache: theCache,
    analytics: analytics,
    isHostWidgetOpen: () => widgetOpen,
    navigator: navigator,
    prefetcher: prefetcher,
    variables: variables,
    emit: emitted.add,
    clock: () => now,
    launcher: (uri, {bool external = false}) async => true,
    prefetchTimeout: prefetchTimeout ?? defaultArtworkPrefetchTimeout,
    variableTimeout: variableTimeout ?? defaultVariableTimeout,
  );

  return (
    service: service,
    source: source,
    presenter: presenter,
    analytics: analytics,
    cap: cap,
    cache: theCache,
    navigator: navigator,
    prefetcher: prefetcher,
    variables: variables,
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

      expect(h.analytics.impressions, ['a']);
      expect(h.cap.snapshot().shownCampaignIds, {idFor('a')});
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
      expect(h.service.pendingCampaign?.campaignId, idFor('cart'));
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
      expect(h.service.pendingCampaign?.campaignId, idFor('cart'));

      // Another message lands while 'cart' waits, moving the floor forward.
      h.cap.recordDisplay(idFor('other'), t0.add(const Duration(seconds: 40)));
      h.setNow(t0.add(const Duration(seconds: 45)));

      h.setWidgetOpen(false);
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_first'],
          reason: 'only 5s since the intervening display, so the floor holds');
      expect(h.service.pendingCampaign?.campaignId, idFor('cart'), reason: 'it stays pending');

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
      expect(h.service.pendingCampaign?.campaignId, idFor('cart'));
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

      expect(h.service.pendingCampaign?.campaignId, idFor('two'));
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
      expect(h.service.pendingCampaign?.campaignId, idFor('a'));
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
          GameballMessageButton(id: 'b5', text: 'Go', action: GameballDismissAction()),
        ]),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapButton(const GameballMessageButton(
        id: 'b5',
        text: 'Go',
        action: GameballDismissAction(),
      ));

      expect(h.analytics.clicks, ['a/b5']);
      expect(h.presenter.isShowing, isFalse);
    });
  });

  group('dismissal — the event Braze has no equivalent of', () {
    test('closing without interacting logs a dismiss', () async {
      final h = build(campaigns: [campaign('a')]);
      await h.service.start(customerId: 'c1');

      h.presenter.dismiss();

      expect(h.analytics.impressions, ['a']);
      expect(h.analytics.dismissals, ['a']);
    });

    test('a button tap suppresses the dismiss that follows it', () async {
      const button =
          GameballMessageButton(id: 'b1', text: 'Go', action: GameballDismissAction());
      final h = build(campaigns: [campaign('a', buttons: const [button])]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapButton(button);

      expect(h.analytics.clicks, ['a/b1']);
      expect(h.analytics.dismissals, isEmpty,
          reason: 'a tapped message was not ignored. Keeping these disjoint is '
              'what makes impressions = clicks + dismissals an identity the '
              'backend can rely on');
    });

    test('tapping the surface suppresses the dismiss too', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballDismissAction()),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapMessage();

      expect(h.analytics.bodyClicks, ['a']);
      expect(h.analytics.dismissals, isEmpty);
    });

    test('every event carries the campaign token and the injected clock',
        () async {
      final h = build(campaigns: [campaign('a', dispatchId: 'tok_a')]);
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();

      expect(h.analytics.events.map((e) => e.dispatchId),
          ['tok_a', 'tok_a'],
          reason: 'the token has to ride every event, not just the impression — '
              'a click the backend cannot attribute to a variant is no better '
              'than no click');
      expect(h.analytics.events.map((e) => e.occurredAt), [t0, t0],
          reason: 'timestamps come from the service clock, not the transport, so '
              'they are the moment it happened and are testable');
    });
  });

  group('analytics lifecycle', () {
    test('pausing flushes, because the app may never resume', () async {
      final h = build(campaigns: [campaign('a')]);
      await h.service.start(customerId: 'c1');

      h.service.onAppPaused();

      expect(h.analytics.flushes, 1);
    });

    test('stopping flushes and then stops scheduling', () async {
      final h = build(campaigns: [campaign('a')]);
      await h.service.start(customerId: 'c1');

      h.service.stop();

      expect(h.analytics.flushes, 1);
      expect(h.analytics.disposals, 1);
    });

    test('start recovers a previous run\'s unsent events', () async {
      final h = build(campaigns: [campaign('a')]);

      await h.service.start(customerId: 'c1');

      expect(h.analytics.loads, 1);
    });
  });

  group('navigate action', () {
    test('a button pushes the route and dismisses', () async {
      final h = build(campaigns: [
        campaign('a', buttons: const [
          GameballMessageButton(
            id: 'b1',
            text: 'View cart',
            action: GameballNavigateAction('/cart', arguments: {'from': 'iam'}),
          ),
        ]),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapButton(const GameballMessageButton(
        id: 'b1',
        text: 'View cart',
        action: GameballNavigateAction('/cart', arguments: {'from': 'iam'}),
      ));
      await pumpEventQueue();

      expect(h.navigator.pushed, ['/cart']);
      expect(h.navigator.lastArguments, {'from': 'iam'});
      expect(h.presenter.isShowing, isFalse);
    });

    test('the message surface can navigate too', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapMessage();
      await pumpEventQueue();

      expect(h.navigator.pushed, ['/rewards']);
    });

    test('the message is dismissed before the route is pushed', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapMessage();

      expect(h.presenter.isShowing, isFalse,
          reason: 'leaving the overlay up would briefly cover the pushed route');
    });

    test('a missing navigator is logged, not thrown', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);
      await h.service.start(customerId: 'c1');
      h.navigator.available = false;

      expect(h.presenter.tapMessage, returnsNormally);
      expect(h.navigator.pushed, isEmpty);
    });
  });

  group('onAction hook', () {
    test('returning true suppresses the built-in action', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);
      final seen = <String>[];

      await h.service.start(
        customerId: 'c1',
        onAction: (message, button, action) {
          seen.add('${message.id}/${button?.id}/${action.runtimeType}');
          return true;
        },
      );
      h.presenter.tapMessage();

      expect(seen, ['msg_a/null/GameballNavigateAction'],
          reason: 'button is null for a surface tap');
      expect(h.navigator.pushed, isEmpty,
          reason: 'the host said it handled the action');
    });

    test('returning false lets the built-in action run', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);

      await h.service.start(
        customerId: 'c1',
        onAction: (_, __, ___) => false,
      );
      h.presenter.tapMessage();
      await pumpEventQueue();

      expect(h.navigator.pushed, ['/rewards']);
    });

    test('the click is still logged and the message still dismissed', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);

      await h.service.start(
        customerId: 'c1',
        onAction: (_, __, ___) => true,
      );
      h.presenter.tapMessage();

      expect(h.analytics.bodyClicks, ['a'],
          reason: 'the hook replaces the action, not the bookkeeping');
      expect(h.presenter.isShowing, isFalse);
    });

    test('a throwing hook falls back to the built-in action', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballNavigateAction('/rewards')),
      ]);

      await h.service.start(
        customerId: 'c1',
        onAction: (_, __, ___) => throw StateError('host bug'),
      );
      h.presenter.tapMessage();
      await pumpEventQueue();

      expect(h.navigator.pushed, ['/rewards'],
          reason: 'a buggy host loses its override, not the action');
    });

    test('the hook receives the button for a button tap', () async {
      const button = GameballMessageButton(
        id: 'b4',
        text: 'Go',
        action: GameballDismissAction(),
      );
      final h = build(campaigns: [campaign('a', buttons: const [button])]);
      final seen = <String?>[];

      await h.service.start(
        customerId: 'c1',
        onAction: (message, b, action) {
          seen.add(b?.id);
          return true;
        },
      );
      h.presenter.tapButton(button);

      expect(seen, ['b4']);
    });
  });

  group('message-surface taps', () {
    test('a tap logs a body click and dismisses', () async {
      final h = build(campaigns: [
        campaign('a', clickAction: const GameballOpenUrlAction('app://x')),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapMessage();

      expect(h.analytics.bodyClicks, ['a']);
      expect(h.analytics.clicks, isEmpty,
          reason: 'a body click is not a button click');
      expect(h.presenter.isShowing, isFalse);
    });

    test('a tap on a message with no action does nothing', () async {
      final h = build(campaigns: [campaign('a')]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapMessage();

      expect(h.analytics.bodyClicks, isEmpty);
      expect(h.presenter.isShowing, isTrue,
          reason: 'an inert message must not dismiss on a stray tap');
    });
  });

  group('purchase triggers', () {
    test('any purchase displays regardless of the product', () async {
      final h = build(campaigns: [
        campaign('promo', trigger: const GameballCustomEventTrigger(gameballPurchaseEventName)),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onPurchase(
        productId: 'anything',
        price: 5,
        currency: 'USD',
      );

      expect(h.presenter.shownMessageIds, ['msg_promo']);
    });

    test('specific purchase matches only its product', () async {
      final h = build(campaigns: [
        campaign(
          'acc',
          trigger: const GameballCustomEventTrigger(
            gameballPurchaseEventName,
            filters: [
              GameballPropertyFilter(
                property: 'productId',
                operator: GameballFilterOperator.equals,
                value: 'sku-001',
              ),
            ],
          ),
        ),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onPurchase(productId: 'sku-999', price: 5, currency: 'USD');
      expect(h.presenter.shownMessageIds, isEmpty);

      h.service.onPurchase(productId: 'sku-001', price: 5, currency: 'USD');
      expect(h.presenter.shownMessageIds, ['msg_acc']);
    });

    test('a price filter narrows a purchase trigger', () async {
      final h = build(campaigns: [
        campaign('big', trigger: const GameballCustomEventTrigger(gameballPurchaseEventName, filters: [
          GameballPropertyFilter(
            property: 'price',
            operator: GameballFilterOperator.greaterThan,
            value: 100,
          ),
        ])),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onPurchase(productId: 'sku-x', price: 12.99, currency: 'USD');
      expect(h.presenter.shownMessageIds, isEmpty,
          reason: 'below the threshold');

      h.service.onPurchase(productId: 'sku-x', price: 189, currency: 'USD');
      expect(h.presenter.shownMessageIds, ['msg_big']);
    });

    test('does nothing before start', () {
      final h = build();

      h.service.onPurchase(productId: 'sku', price: 1, currency: 'USD');

      expect(h.presenter.shownMessageIds, isEmpty);
    });
  });

  group('sessions', () {
    test('a resume after the timeout starts a new session and fires again',
        () async {
      final h = build(campaigns: [
        campaign('cold', priority: 100),
        campaign('warm', priority: 50),
      ]);
      await h.service.start(customerId: 'c1');
      expect(h.presenter.shownMessageIds, ['msg_cold']);
      h.presenter.dismiss();

      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(minutes: 5)));
      h.service.onAppResumed();
      // A new session now re-syncs before evaluating, so the warm message
      // arrives after a round trip rather than synchronously.
      await pumpEventQueue();

      expect(h.presenter.shownMessageIds, ['msg_cold', 'msg_warm'],
          reason: 'caps survive the new session, so the next campaign shows');
    });

    test('a brief resume stays in the same session', () async {
      final h = build(campaigns: [
        campaign('cold', priority: 100),
        campaign('warm', priority: 50),
      ]);
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();

      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(seconds: 5)));
      h.service.onAppResumed();

      expect(h.presenter.shownMessageIds, ['msg_cold'],
          reason: 'below the session timeout, so no new session began');
    });

    test('a resume with no preceding pause does nothing', () async {
      final h = build();
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();
      final before = h.presenter.shownMessageIds.length;

      h.service.onAppResumed();

      expect(h.presenter.shownMessageIds, hasLength(before));
    });

    test('lifecycle callbacks do nothing before start', () {
      final h = build();

      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(hours: 1)));
      h.service.onAppResumed();

      expect(h.presenter.shownMessageIds, isEmpty);
    });
  });

  group('customer changes', () {
    test('a new customer refetches and resets caps', () async {
      final h = build();
      await h.service.start(customerId: 'c1');
      expect(h.cap.snapshot().shownCampaignIds, {idFor('a')});

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
    });

    test('does not erase display history', () async {
      final h = build();
      await h.service.start(customerId: 'c1');

      h.service.stop();

      expect(h.cap.snapshot().shownCampaignIds, isNotEmpty,
          reason: 'history belongs to the customer, not the session. Wiping it '
              'on logout would let a once-ever campaign show again the moment '
              'they log back in — and load() already discards it when a '
              'different customer starts');
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
      expect(h.service.pendingCampaign?.campaignId, idFor('a'));
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

  group('the campaign cache', () {
    test('a failed sync falls back to the cache instead of going silent',
        () async {
      final h = build();
      await h.cache.write('c1', rawSync(campaignId: 4242));
      h.source.throwOnFetch = StateError('no network');

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, ['4242'],
          reason: 'the backend rule is "on sync failure keep the previous '
              'cache" — clearing would make every offline launch silent');
    });

    test('a successful sync wins over the cache', () async {
      final h = build(campaigns: [campaign('fresh')]);
      await h.cache.write('c1', rawSync(campaignId: 999));

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, ['msg_fresh'],
          reason: 'the cache is a fallback, never a preference');
    });

    test('a successful sync is written to the cache', () async {
      final h = build();
      h.source.rawJson = rawSync(campaignId: 55);

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect((await h.cache.read('c1')).campaigns.single.campaignId, 55);
    });

    test('a sync with no raw payload writes nothing', () async {
      final h = build();

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect((await h.cache.read('c1')).campaigns, isEmpty,
          reason: 'the service must not invent a payload to cache');
    });

    test('a failed sync writes nothing', () async {
      final h = build();
      h.source.throwOnFetch = StateError('no network');

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect((await h.cache.read('c1')).campaigns, isEmpty,
          reason: 'a failure must not overwrite a good cache with nothing');
    });
  });

  group('sync per session', () {
    test('a warm session re-syncs rather than reusing the cold-start list',
        () async {
      final h = build(campaigns: [
        campaign('cold', priority: 100),
        campaign('warm', priority: 50),
      ]);
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();
      expect(h.source.fetchCount, 1);

      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(minutes: 5)));
      h.service.onAppResumed();
      await pumpEventQueue();

      expect(h.source.fetchCount, 2,
          reason: 'a session start is when campaign edits, expiries and '
              'eligibility changes land');
    });

    test('a resume inside the timeout does not sync', () async {
      final h = build();
      await h.service.start(customerId: 'c1');

      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(seconds: 5)));
      h.service.onAppResumed();
      await pumpEventQueue();

      expect(h.source.fetchCount, 1);
    });

    test('a warm session evaluates against the cache when the sync fails',
        () async {
      final h = build(campaigns: [
        campaign('cold', priority: 100),
        campaign('warm', priority: 50),
      ]);
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();

      h.source.throwOnFetch = StateError('offline');
      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(minutes: 5)));
      h.service.onAppResumed();
      await pumpEventQueue();

      expect(h.presenter.shownMessageIds, ['msg_cold', 'msg_warm'],
          reason: 'the campaigns already in memory stay usable');
    });
  });

  group('flushing before an action that leaves the app', () {
    Future<int> flushesAfterTapping(GameballClickAction action) async {
      final button =
          GameballMessageButton(id: 'b1', text: 'Go', action: action);
      final h = build(campaigns: [campaign('a', buttons: [button])]);
      await h.service.start(customerId: 'c1');
      final before = h.analytics.flushes;

      h.presenter.tapButton(button);
      await pumpEventQueue();

      return h.analytics.flushes - before;
    }

    test('open_url flushes first', () async {
      expect(
        await flushesAfterTapping(const GameballOpenUrlAction('https://x')),
        1,
        reason: 'an external browser may never hand control back, so the click '
            'that caused it is the event most at risk of being lost',
      );
    });

    test('navigate flushes first', () async {
      expect(await flushesAfterTapping(const GameballNavigateAction('/cart')), 1,
          reason: 'the OS can reclaim a backgrounded app at any point');
    });

    test('dismiss does not', () async {
      expect(await flushesAfterTapping(const GameballDismissAction()), 0,
          reason: 'nothing is leaving, so the timer is soon enough');
    });

    test('a slow flush does not stop the action', () async {
      const button = GameballMessageButton(
        id: 'b1',
        text: 'Go',
        action: GameballNavigateAction('/cart'),
      );
      final h = build(campaigns: [campaign('a', buttons: [button])]);
      await h.service.start(customerId: 'c1');
      h.analytics.flushDelay = const Duration(seconds: 30);

      h.presenter.tapButton(button);
      await pumpEventQueue();
      // Far less than the flush would take, and well past the 800ms bound.
      await Future<void>.delayed(const Duration(seconds: 1));
      await pumpEventQueue();

      expect(h.navigator.pushed, ['/cart'],
          reason: 'a dead network must not swallow a tap the user is waiting on');
    });
  });

  group('artwork prefetch', () {
    test('does not display a campaign whose artwork failed to load', () async {
      final h = build();
      h.prefetcher.failing.add('msg_a');

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.analytics.impressions, isEmpty,
          reason: 'an impression for artwork nobody saw is the thing this '
              'prevents');
    });

    test('displays a lower-priority campaign when the winner has no artwork',
        () async {
      final h = build(campaigns: [
        campaign('winner', priority: 10),
        campaign('runner_up', priority: 1),
      ]);
      h.prefetcher.failing.add('msg_winner');

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, ['msg_runner_up']);
    });

    test('warms every campaign at sync, not only the one that shows', () async {
      final h = build(campaigns: [
        campaign('shown', priority: 10),
        campaign('on_event',
            trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);

      await h.service.start(customerId: 'c1');

      expect(h.prefetcher.requested, containsAll(['msg_shown', 'msg_on_event']),
          reason: 'an event trigger can fire at any moment with no time to '
              'fetch, so its artwork has to be warm before it does');
    });

    test('an event-triggered campaign is skipped when its artwork failed',
        () async {
      final h = build(campaigns: [
        campaign('evt', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      h.prefetcher.failing.add('msg_evt');

      await h.service.start(customerId: 'c1');
      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, isEmpty);
    });

    test('a prefetch that never answers is bounded, and the campaign skipped',
        () async {
      final h = build(prefetchTimeout: const Duration(milliseconds: 50));
      h.prefetcher.hanging.add('msg_a');

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, isEmpty,
          reason: 'a wedged image host must not hang start() forever');
    });

    test('artwork readiness is recomputed on the next sync', () async {
      final h = build();
      h.prefetcher.failing.add('msg_a');
      await h.service.start(customerId: 'c1');
      expect(h.presenter.shownMessageIds, isEmpty);

      // The image host recovers. A new session must re-evaluate rather than
      // inherit the earlier failure for the life of the process.
      h.prefetcher.failing.clear();
      h.service.onAppPaused();
      h.setNow(t0.add(const Duration(minutes: 10)));
      h.service.onAppResumed();
      await pumpEventQueue();

      expect(h.presenter.shownMessageIds, ['msg_a']);
    });
  });

  group('personalisation', () {
    InAppMessageCampaign tokenCampaign(String label) => InAppMessageCampaign(
          campaignId: idFor(label),
          trigger: const GameballSessionStartTrigger(),
          priority: 0,
          message: GameballInAppMessage(
            id: 'msg_$label',
            type: GameballMessageType.modal,
            header: 'Hi {first_name}',
            body: 'You have {points_balance}',
          ),
        );

    test('a message with no token never asks for variables', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, ['msg_a']);
      expect(h.variables.fetches, 0,
          reason: 'the scan is what keeps this inert until tokens exist');
    });

    test('a token-bearing message displays with values substituted', () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{
        'first_name': 'Ahmed',
        'points_balance': '1,250',
      };

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.variables.fetches, 1);
      expect(h.presenter.shownHeaders, ['Hi Ahmed']);
      expect(h.presenter.shownBodies, ['You have 1,250']);
    });

    test('an empty map displays the text already held', () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{};

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.presenter.shownHeaders, ['Hi {first_name}'],
          reason: 'never block or drop a display on this call');
    });

    test('a hung fetch is bounded and the message still displays', () async {
      final h = build(
        campaigns: [tokenCampaign('promo')],
        variableTimeout: const Duration(milliseconds: 50),
      );
      h.variables.hang = true;

      await h.service.start(customerId: 'c1');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(h.presenter.shownHeaders, ['Hi {first_name}']);
    });

    test('the impression is still logged once, at display', () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{'first_name': 'Ahmed'};

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.analytics.impressions, ['promo']);
    });

    test('the cap is recorded against the campaign, not the copy', () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{'first_name': 'Ahmed'};

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.cap.snapshot().shownCampaignIds, {idFor('promo')});
    });

    test('a trigger during the fetch does not stack a second message',
        () async {
      final h = build(campaigns: [tokenCampaign('promo'), campaign('other')]);
      h.variables.hang = true;

      await h.service.start(customerId: 'c1');
      h.service.onCustomEvent('anything');
      await pumpEventQueue();

      expect(h.presenter.shownMessageIds, isEmpty,
          reason: 'one is still resolving; the other must not jump the queue');
    });

    test('stopping while a fetch is in flight shows nothing afterwards',
        () async {
      final h = build(
        campaigns: [tokenCampaign('promo')],
        variableTimeout: const Duration(milliseconds: 50),
      );
      h.variables.hang = true;

      await h.service.start(customerId: 'c1');
      h.service.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(h.presenter.shownMessageIds, isEmpty,
          reason: 'a message resolving when the host logged out must not '
              'appear over whatever replaced it');
    });
  });
}
