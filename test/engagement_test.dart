import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/engagement/engagement.dart';
import 'package:gameball_sdk/gameball_sdk.dart';

class MemoryStore implements ReceivedPushStore {
  List<ReceivedPush> saved = [];

  @override
  Future<List<ReceivedPush>> load() async => saved;

  @override
  Future<void> save(List<ReceivedPush> pushes) async => saved = List.of(pushes);
}

void main() {
  // Mirrors the Android SDK's AppOpenObserverTest
  group('app opens', () {
    late int clock;
    late List<AppOpen> opens;
    late AppOpenTracker tracker;

    setUp(() {
      clock = 1000000;
      opens = [];
      tracker = AppOpenTracker(now: () => clock, report: opens.add);
    });

    test('first foreground is cold', () {
      tracker.onForeground();
      expect(opens, [const AppOpen('cold', 1000000)]);
    });

    test('return after the gap is warm', () {
      tracker.onForeground();
      tracker.onBackground();
      clock += 31000;
      tracker.onForeground();
      expect(opens.map((o) => o.type), ['cold', 'warm']);
    });

    test('return within the gap is not an open', () {
      tracker.onForeground();
      tracker.onBackground();
      clock += 10000;
      tracker.onForeground();
      expect(opens, hasLength(1));
    });

    test('return at exactly the gap is not an open', () {
      tracker.onForeground();
      tracker.onBackground();
      clock += 30000;
      tracker.onForeground();
      expect(opens, hasLength(1));
    });

    test('visible again after the gap counts as warm even without focus', () {
      tracker.onForeground();
      tracker.onBackground();
      clock += 31000;
      tracker.onVisibleAgain(); // inactive on the way back
      tracker.onForeground(); // resumed once focused: same open
      expect(opens.map((o) => o.type), ['cold', 'warm']);
      expect(opens.last.openedAt, 1031000);
    });

    test('visible again within the gap is not an open', () {
      tracker.onForeground();
      tracker.onBackground();
      clock += 10000;
      tracker.onVisibleAgain();
      expect(opens, hasLength(1));
    });

    test('visible before the first open is not a cold open', () {
      tracker.onVisibleAgain(); // e.g. an inactive start state
      expect(opens, isEmpty);
      tracker.onForeground();
      expect(opens, [const AppOpen('cold', 1000000)]);
    });

    test('a tap while away marks the next return as from a tap', () {
      tracker.onForeground();
      tracker.onBackground();
      clock += 31000;
      tracker.onTap(); // onMessageOpenedApp, before the app is back
      tracker.onForeground();
      expect(opens.last, const AppOpen('warm', 1031000, fromTap: true));
    });

    test('a tap before the first open marks the cold open', () {
      tracker.onTap(); // getInitialMessage handled before init
      clock += 2000;
      tracker.onForeground();
      expect(opens.single, const AppOpen('cold', 1002000, fromTap: true));
    });

    test('a tap more than 60 s before the return does not mark it', () {
      tracker.onForeground();
      tracker.onBackground();
      tracker.onTap();
      clock += 61000;
      tracker.onForeground();
      expect(opens.last.fromTap, isFalse);
    });

    test('a tap while on screen marks nothing', () {
      tracker.onForeground();
      tracker.onTap();
      tracker.onBackground();
      clock += 31000;
      tracker.onForeground();
      expect(opens.map((o) => o.fromTap), [false, false]);
    });

    test('every return uses the mark up, even one within 30 s that is not an open', () {
      tracker.onForeground();
      tracker.onBackground();
      tracker.onTap();
      clock += 10000;
      tracker.onForeground(); // within the gap: no open, mark used up
      tracker.onBackground();
      clock += 31000;
      tracker.onForeground();
      expect(opens.map((o) => o.fromTap), [false, false]);
    });

    test('repeated lifecycle steps count once (hidden then paused, resumed twice)', () {
      tracker.onForeground();
      tracker.onForeground();
      tracker.onBackground(); // hidden
      clock += 20000;
      tracker.onBackground(); // paused, later: must not restart the time away
      clock += 15000;
      tracker.onForeground();
      expect(opens.map((o) => o.type), ['cold', 'warm']);
    });
  });

  // Mirrors the Android SDK's InfluencedOpensTest
  group('influenced opens', () {
    const minute = 60000;
    late int clock;
    late MemoryStore store;
    late InfluencedOpens influenced;

    setUp(() {
      clock = 1000000000;
      store = MemoryStore();
      influenced = InfluencedOpens(store, now: () => clock);
    });

    Future<void> receive(String token) => influenced.onReceived(token, token, clock - 500);
    Future<ReceivedPush?> open() => influenced.influencedBy(AppOpen(AppOpen.warm, clock));

    test('open within the window of an untapped push is influenced', () async {
      await receive('tok-1');
      clock += 10 * minute;
      expect((await open())?.clickToken, 'tok-1');
    });

    test('open at exactly 30 minutes is influenced', () async {
      await receive('tok-1');
      clock += 30 * minute;
      expect((await open())?.clickToken, 'tok-1');
    });

    test('open after the window is not influenced', () async {
      await receive('tok-1');
      clock += 31 * minute;
      expect(await open(), isNull);
    });

    test('tapped push never counts as influenced', () async {
      await receive('tok-1');
      clock += minute;
      await influenced.onTap('tok-1');
      expect(await open(), isNull);
    });

    test('the most recent push gets the credit', () async {
      await receive('tok-1');
      clock += 5 * minute;
      await receive('tok-2');
      clock += 5 * minute;
      expect((await open())?.clickToken, 'tok-2');
    });

    test('no fallback to an older push when the newest is too old', () async {
      await receive('tok-1');
      clock += minute;
      await receive('tok-2');
      clock += 31 * minute;
      expect(await open(), isNull);
    });

    test('an open clears the saved pushes', () async {
      await receive('tok-1');
      clock += minute;
      await open();
      clock += minute;
      expect(await open(), isNull);
      expect(store.saved, isEmpty);
    });

    test('open with no push is not influenced', () async {
      expect(await open(), isNull);
    });

    test('the same push delivered twice is saved once', () async {
      await receive('tok-1');
      await receive('tok-1');
      expect(store.saved, hasLength(1));
    });

    test('at most twenty pushes are kept', () async {
      for (var i = 0; i < 25; i++) {
        await receive('tok-$i');
        clock += 1;
      }
      expect(store.saved, hasLength(InfluencedOpens.maxSaved));
      expect(store.saved.last.clickToken, 'tok-24');
    });

    test('clear forgets everything', () async {
      await receive('tok-1');
      await influenced.clear();
      expect(await open(), isNull);
    });

    test('an open caused by a tap credits nothing and still clears the list', () async {
      await receive('tok-1');
      clock += minute;
      expect(await influenced.influencedBy(AppOpen(AppOpen.warm, clock, fromTap: true)), isNull);
      expect(store.saved, isEmpty);
    });

    test('A ignored, B tapped, then the open from the tap: nothing credited, list empty', () async {
      await receive('tok-A'); // 10:00, ignored
      clock += 5 * minute;
      await receive('tok-B'); // 10:05
      await influenced.onTap('tok-B'); // tapped
      expect(store.saved.map((p) => p.key), ['tok-A']);
      expect(await influenced.influencedBy(AppOpen(AppOpen.warm, clock, fromTap: true)), isNull);
      expect(store.saved, isEmpty);
    });

    test('calls without awaiting still run in order', () async {
      // ignore: unawaited_futures
      receive('tok-1');
      // ignore: unawaited_futures
      influenced.onTap('tok-1');
      expect(await open(), isNull);
    });
  });

  group('engagement log lines', () {
    late int clock;
    late MemoryStore store;
    late List<String> lines;
    late Engagement engagement;
    late Completer<void> grace;

    setUp(() {
      clock = 1700000000000;
      store = MemoryStore();
      lines = [];
      grace = Completer<void>()..complete();
      engagement = Engagement(
          store: store, now: () => clock, log: lines.add, waitForTap: () => grace.future);
    });

    GameballPushPayload push(String token) =>
        GameballPushPayload.from({'isGB': 'true', 'gbClickToken': token})!;

    test('received then open within 30 minutes logs influenced_open', () async {
      await engagement.onReceived(
          GameballPushPayload.from({'isGB': 'true', 'gbClickToken': 'tok-1'})!,
          sentTime: clock - 1000);
      clock += 60000;
      engagement.appOpens.onForeground();
      await engagement.settled;
      expect(lines, [
        'GameballApp engagement push_received clickToken=tok-1 sentAt=1699999999000 receivedAt=1700000000000',
        'GameballApp engagement app_open type=cold openedAt=1700000060000',
        'GameballApp engagement influenced_open clickToken=tok-1 sentAt=1699999999000 '
            'receivedAt=1700000000000 type=cold openedAt=1700000060000',
      ]);
    });

    test('the logged and the saved receive time are the same', () async {
      var ticks = 0;
      final engagement = Engagement(
          store: store, now: () => clock + (ticks++) * 1000, log: lines.add, waitForTap: () async {});
      await engagement.onReceived(push('tok-1'));
      expect(lines.single, endsWith('receivedAt=${store.saved.single.receivedAt}'));
    });

    test('sent time falls back to google.sent_time in the payload', () async {
      await engagement.onReceived(GameballPushPayload.from(
          {'isGB': 'TRUE', 'gbClickToken': 'tok-1', 'google.sent_time': '1699999990000'})!);
      expect(lines.single, contains('sentAt=1699999990000'));
    });

    test('push without a token is keyed by its message id', () async {
      await engagement.onReceived(
          GameballPushPayload.from({'isGB': 'true', 'google.message_id': 'm-1'})!);
      expect(store.saved.single.key, 'm-1');
      expect(lines.single, contains('clickToken=null'));
    });

    test('non-Gameball payloads are not pushes', () {
      expect(GameballPushPayload.from({'gbClickToken': 'tok-1'}), isNull);
      expect(GameballPushPayload.from({'isGB': 'false', 'gbClickToken': 'tok-1'}), isNull);
      expect(GameballPushPayload.from(null), isNull);
    });

    test('a tap reported after the open but within the grace is not influenced', () async {
      await engagement.onReceived(push('tok-1'));
      clock += 60000;
      grace = Completer<void>();
      engagement.appOpens.onForeground(); // the cold open, seen first
      await Future<void>.delayed(Duration.zero);
      expect(engagement.onTap(push('tok-1')), isTrue); // getInitialMessage, a moment later
      grace.complete();
      await engagement.settled;
      expect(lines.where((l) => l.contains('influenced_open')), isEmpty);
      expect(lines.last, 'GameballApp engagement push_click clickToken=tok-1');
    });

    // (a) The user's example, cold: the tap reaches the SDK during the wait
    // (getInitialMessage after the open)
    test('(a) A saved, B saved and tapped during the wait: no influenced_open, list empty', () async {
      await engagement.onReceived(push('tok-A')); // 10:00, ignored
      clock += 5 * 60000;
      await engagement.onReceived(push('tok-B')); // 10:05
      clock += 60000;
      grace = Completer<void>();
      engagement.appOpens.onForeground(); // the cold open the tap caused
      await Future<void>.delayed(Duration.zero);
      engagement.onTap(push('tok-B'));
      grace.complete();
      await engagement.settled;
      expect(lines.where((l) => l.contains('influenced_open')), isEmpty);
      expect(lines.where((l) => l.contains('push_click clickToken=tok-B')), hasLength(1));
      expect(store.saved, isEmpty);
    });

    // (a) The user's example, warm: the tap reaches the SDK while the app is
    // still away (onMessageOpenedApp before the resume)
    test('(a) A saved, B saved and tapped while away: no influenced_open, list empty', () async {
      engagement.appOpens.onForeground(); // cold open earlier, nothing saved
      engagement.appOpens.onBackground();
      await engagement.onReceived(push('tok-A'));
      clock += 5 * 60000;
      await engagement.onReceived(push('tok-B'));
      engagement.onTap(push('tok-B'));
      clock += 2000;
      engagement.appOpens.onForeground(); // the warm open the tap caused
      await engagement.settled;
      expect(lines.where((l) => l.contains('influenced_open')), isEmpty);
      expect(lines.where((l) => l.contains('app_open type=warm')), hasLength(1));
      expect(store.saved, isEmpty);
    });

    test('(b) a tap while on screen does not stop the next icon open from being influenced', () async {
      engagement.appOpens.onForeground(); // on screen
      await engagement.settled;
      await engagement.onReceived(push('tok-A')); // onMessage, on screen
      engagement.onTap(push('tok-X')); // a tap handled while on screen
      engagement.appOpens.onBackground();
      clock += 31000;
      engagement.appOpens.onForeground(); // icon open
      await engagement.settled;
      expect(lines.last,
          startsWith('GameballApp engagement influenced_open clickToken=tok-A '));
    });

    test('(c) a tap followed by a return within 30 s does not affect a later icon open', () async {
      engagement.appOpens.onForeground();
      await engagement.settled;
      engagement.appOpens.onBackground();
      engagement.onTap(push('tok-X')); // marks the next return
      clock += 10000;
      engagement.appOpens.onForeground(); // back within 30 s: not an open, mark used up
      await engagement.onReceived(push('tok-A'));
      engagement.appOpens.onBackground();
      clock += 31000;
      engagement.appOpens.onForeground(); // icon open
      await engagement.settled;
      expect(lines.where((l) => l.contains('app_open')), hasLength(2));
      expect(lines.last,
          startsWith('GameballApp engagement influenced_open clickToken=tok-A '));
    });

    test('the open clears the list before the grace ends', () async {
      await engagement.onReceived(push('tok-1'));
      grace = Completer<void>();
      engagement.appOpens.onForeground();
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, isEmpty);
      grace.complete();
      await engagement.settled;
    });

    test('an open with nothing saved does not wait for taps', () async {
      grace = Completer<void>(); // never completes
      engagement.appOpens.onForeground();
      await engagement.settled;
      expect(lines.single, startsWith('GameballApp engagement app_open type=cold'));
    });

    test('an influenced open is sent as influencedOpen at the open, only with a click token', () async {
      final sent = <String>[];
      final reporting = Engagement(
        store: store,
        now: () => clock,
        log: lines.add,
        waitForTap: () async => clock += 10000, // decided 10 s after the open
        send: (type, token, occurredAt) async => sent.add('${type.value} $token $occurredAt'),
      );
      await reporting.onReceived(push('tok-1'));
      clock += 60000;
      final openedAt = clock;
      reporting.appOpens.onForeground();
      await reporting.settled;
      expect(sent, ['3 tok-1 $openedAt']);

      await reporting.onReceived(GameballPushPayload.from({'isGB': 'true', 'google.message_id': 'm-1'})!);
      reporting.appOpens.onBackground();
      clock += 31000;
      reporting.appOpens.onForeground();
      await reporting.settled;
      expect(lines.last, startsWith('GameballApp engagement influenced_open clickToken=null '));
      expect(sent, hasLength(1));
    });

    test('customer change clears the saved pushes', () async {
      await engagement.onReceived(GameballPushPayload.from({'isGB': 'true', 'gbClickToken': 'tok-1'})!);
      await engagement.onCustomerChanged();
      expect(store.saved, isEmpty);
    });
  });

  group('storage failures', () {
    test('a store whose platform side is missing never throws out of the SDK calls', () async {
      // No shared_preferences platform is registered in plain unit tests
      final lines = <String>[];
      final engagement = Engagement(log: lines.add, waitForTap: () async {});
      final push = GameballPushPayload.from({'isGB': 'true', 'gbClickToken': 'tok-1'})!;
      await engagement.onReceived(push);
      expect(engagement.onTap(push), isTrue);
      engagement.appOpens.onForeground();
      await engagement.settled;
      await engagement.onCustomerChanged();
      expect(lines.where((l) => l.startsWith('GameballApp engagement')), hasLength(3));
      expect(lines.where((l) => l.startsWith('GameballApp could not')), isNotEmpty);
    });
  });

  group('GameballApp', () {
    late MemoryStore store;
    late List<String> lines;
    final app = GameballApp.getInstance();

    setUp(() {
      store = MemoryStore();
      lines = [];
      GameballApp.debugEngagement =
          Engagement(store: store, log: lines.add, waitForTap: () async {});
    });

    tearDown(() => GameballApp.debugEngagement = null);

    List<String> clicks() => lines.where((l) => l.contains(' push_click ')).toList();

    test('handlePushClick counts the same tap once', () {
      final payload = {'isGB': 'true', 'gbClickToken': 'tok-x'};
      expect(app.handlePushClick(payload), isTrue);
      expect(app.handlePushClick(payload), isTrue);
      expect(clicks(), ['GameballApp engagement push_click clickToken=tok-x']);
    });

    test('handlePushClick counts different taps separately', () {
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-a'});
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-b'});
      expect(clicks(), hasLength(2));
    });

    test('handlePushClick dedupes by message id when there is no token', () {
      app.handlePushClick({'isGB': 'true', 'google.message_id': 'm-1'});
      app.handlePushClick({'isGB': 'true', 'google.message_id': 'm-1'});
      expect(clicks(), hasLength(1));
    });

    test('handlePushClick ignores non-Gameball payloads', () {
      expect(app.handlePushClick({'gbClickToken': 'tok-x'}), isFalse);
      expect(lines, isEmpty);
    });

    test('handlePushClick still reports a missing init to the callback', () {
      Exception? error;
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-cb'},
          callback: (_, e) => error = e);
      expect(error.toString(), contains('API key is not initialized'));
    });

    test('a tapped push is removed from the saved list', () async {
      await app.handlePushReceived({'isGB': 'true', 'gbClickToken': 'tok-t'});
      expect(store.saved, hasLength(1));
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-t'});
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, isEmpty);
    });

    test('handlePushReceived saves Gameball pushes and ignores others', () async {
      expect(await app.handlePushReceived({'isGB': 'true', 'gbClickToken': 'tok-r'}, sentTime: 5), isTrue);
      expect(await app.handlePushReceived({'title': 'not ours'}), isFalse);
      expect(store.saved.single.clickToken, 'tok-r');
      expect(lines.single, startsWith('GameballApp engagement push_received clickToken=tok-r sentAt=5 '));
    });
  });
}
