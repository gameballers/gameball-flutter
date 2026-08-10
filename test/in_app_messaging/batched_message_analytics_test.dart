import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/batched_message_analytics.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/message_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _outboxKey = 'gameball_iam_analytics_outbox';

GameballMessageEvent event(
  GameballMessageEventType type, {
  int campaignId = 2041,
  int? variationId,
  String? dispatchId = 'disp_a',
  String? buttonId,
  String? url,
  String? eventUid,
}) {
  return GameballMessageEvent(
    type: type,
    campaignId: campaignId,
    variationId: variationId,
    dispatchId: dispatchId,
    occurredAt: DateTime.utc(2026, 8, 10, 9, 14, 22),
    buttonId: buttonId,
    url: url,
    eventUid: eventUid,
  );
}

/// Records batches and answers with a scripted verdict.
class FakeSender {
  FakeSender({this.result = GameballAnalyticsSendResult.accepted});

  GameballAnalyticsSendResult result;
  final List<List<Map<String, dynamic>>> batches = [];

  Future<GameballAnalyticsSendResult> call(
    List<Map<String, dynamic>> events,
  ) async {
    batches.add(events);
    return result;
  }
}

void main() {
  // SharedPreferences needs a binding and a mock store; without them every
  // persistence call would throw and be swallowed, hiding real regressions.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  BatchedMessageAnalytics build(
    FakeSender sender, {
    Duration interval = const Duration(minutes: 5),
    int batchSize = 20,
    int maxBuffered = maxBufferedAnalyticsEvents,
  }) {
    return BatchedMessageAnalytics(
      send: sender.call,
      flushInterval: interval,
      batchSize: batchSize,
      maxBuffered: maxBuffered,
    );
  }

  group('the wire shape', () {
    test('an impression serialises to exactly the agreed fields', () {
      final json = event(GameballMessageEventType.impression, eventUid: 'e1')
          .toJson();

      expect(json, {
        'eventUid': 'e1',
        'type': 'impression',
        'campaignId': 2041,
        'occurredAt': '2026-08-10T09:14:22.000Z',
        'dispatchId': 'disp_a',
      });
    });

    test('a button tap and a surface tap are both clicks, told apart by buttonId',
        () {
      final button =
          event(GameballMessageEventType.click, buttonId: 'cta').toJson();
      final surface = event(GameballMessageEventType.click).toJson();

      expect(button['type'], 'click');
      expect(surface['type'], 'click',
          reason: 'the backend has no separate button-click type');
      expect(button['buttonId'], 'cta');
      expect(surface.containsKey('buttonId'), isFalse,
          reason: 'a null buttonId is omitted rather than sent as null, which is '
              'what lets presence mean "a button was tapped"');
    });

    test('a missing dispatchId is omitted, not sent as null', () {
      final json = event(GameballMessageEventType.impression, dispatchId: null)
          .toJson();

      expect(json.containsKey('dispatchId'), isFalse);
      expect(json['campaignId'], 2041,
          reason: 'the campaign id still correlates the event without one');
    });

    test('occurredAt is always UTC on the wire', () {
      final local = GameballMessageEvent(
        type: GameballMessageEventType.impression,
        campaignId: 2041,
        occurredAt: DateTime(2026, 8, 10, 12),
      );

      expect(local.toJson()['occurredAt'], endsWith('Z'));
    });

    test('event ids are unique, because they are the idempotency key', () {
      final ids = List.generate(
        200,
        (_) => event(GameballMessageEventType.impression, eventUid: null).eventUid,
      ).toSet();

      expect(ids, hasLength(200));
    });
  });

  group('batching', () {
    test('logging does not send straight away', () {
      final sender = FakeSender();
      final analytics = build(sender);

      analytics.log(event(GameballMessageEventType.impression));

      expect(sender.batches, isEmpty,
          reason: 'an impression must never wait on a network round trip');
      expect(analytics.bufferedCount, 1);
      expect(analytics.hasScheduledFlush, isTrue);
      analytics.dispose();
    });

    test('reaching the batch size sends without waiting for the timer',
        () async {
      final sender = FakeSender();
      final analytics = build(sender, batchSize: 2);

      analytics.log(event(GameballMessageEventType.impression));
      analytics.log(event(GameballMessageEventType.click));
      await pumpEventQueue();

      expect(sender.batches, hasLength(1));
      expect(sender.batches.single.map((e) => e['type']),
          ['impression', 'click']);
      expect(analytics.bufferedCount, 0);
      analytics.dispose();
    });

    test('the timer sends what is buffered', () async {
      final sender = FakeSender();
      final analytics =
          build(sender, interval: const Duration(milliseconds: 10));

      analytics.log(event(GameballMessageEventType.impression));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sender.batches, hasLength(1));
      expect(analytics.bufferedCount, 0);
      analytics.dispose();
    });

    test('a rejected batch stays queued and is retried', () async {
      final sender = FakeSender(result: GameballAnalyticsSendResult.retry);
      final analytics =
          build(sender, interval: const Duration(milliseconds: 10));

      analytics.log(event(GameballMessageEventType.impression));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sender.batches, isNotEmpty);
      expect(analytics.bufferedCount, 1,
          reason: 'dropping events on a failed send silently understates the '
              'only number the feature is judged on');

      sender.result = GameballAnalyticsSendResult.accepted;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(analytics.bufferedCount, 0);
      analytics.dispose();
    });

    test('a refused batch is dropped so it cannot block later events', () async {
      final sender = FakeSender(result: GameballAnalyticsSendResult.discard);
      final analytics = build(sender, batchSize: 1);

      analytics.log(event(GameballMessageEventType.impression, eventUid: 'bad'));
      await pumpEventQueue();

      expect(analytics.bufferedCount, 0,
          reason: 'the outbox is FIFO, so a permanently rejected batch retried '
              'forever would take every later event down with it');

      sender.result = GameballAnalyticsSendResult.accepted;
      analytics.log(event(GameballMessageEventType.click, eventUid: 'good'));
      await pumpEventQueue();

      expect(sender.batches.last.single['eventUid'], 'good');
      analytics.dispose();
    });

    test('a throwing sender keeps the events', () async {
      final analytics = BatchedMessageAnalytics(
        send: (_) => throw StateError('no network'),
        flushInterval: const Duration(milliseconds: 10),
      );

      analytics.log(event(GameballMessageEventType.impression));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(analytics.bufferedCount, 1);
      analytics.dispose();
    });

    test('events logged during a send belong to the next batch', () async {
      final sender = FakeSender();
      var released = false;
      final analytics = BatchedMessageAnalytics(
        send: (events) async {
          sender.batches.add(events);
          while (!released) {
            await Future<void>.delayed(Duration.zero);
          }
          return GameballAnalyticsSendResult.accepted;
        },
        batchSize: 1,
      );

      analytics.log(event(GameballMessageEventType.impression));
      await pumpEventQueue();
      analytics.log(event(GameballMessageEventType.dismiss));
      released = true;
      await pumpEventQueue();

      expect(sender.batches.first.single['type'], 'impression');
      expect(analytics.bufferedCount, 1,
          reason: 'the dismiss arrived mid-send, so removing the sent batch '
              'from the front must not take it with them');
      analytics.dispose();
    });

    test('the outbox is bounded, and says so', () async {
      final sender = FakeSender(result: GameballAnalyticsSendResult.retry);
      final analytics = build(sender, batchSize: 1000, maxBuffered: 3);

      for (var i = 0; i < 5; i++) {
        analytics.log(event(GameballMessageEventType.impression,
            eventUid: 'e$i'));
      }

      expect(analytics.bufferedCount, 3);
      analytics.dispose();
    });
  });

  group('persistence — surviving the process dying', () {
    test('a logged event reaches storage before any send', () async {
      final analytics = build(FakeSender());

      analytics.log(event(GameballMessageEventType.impression, eventUid: 'e1'));
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(_outboxKey)!) as List;
      expect(stored.single['eventUid'], 'e1');
      analytics.dispose();
    });

    test('load restores what a previous run never sent', () async {
      SharedPreferences.setMockInitialValues({
        _outboxKey: jsonEncode([
          event(GameballMessageEventType.impression, eventUid: 'old').toJson(),
        ]),
      });
      final sender = FakeSender();
      final analytics =
          build(sender, interval: const Duration(milliseconds: 10));

      await analytics.load();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sender.batches.single.single['eventUid'], 'old');
      analytics.dispose();
    });

    test('a successful send clears storage', () async {
      final analytics = build(FakeSender(), batchSize: 1);

      analytics.log(event(GameballMessageEventType.impression));
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_outboxKey), isNull,
          reason: 'leaving sent events on disk would resend them next launch');
      analytics.dispose();
    });

    test('a corrupt outbox is discarded, not thrown', () async {
      SharedPreferences.setMockInitialValues({_outboxKey: 'not json at all'});
      final analytics = build(FakeSender());

      await analytics.load();

      expect(analytics.bufferedCount, 0);
    });

    test('a stored non-list is discarded', () async {
      SharedPreferences.setMockInitialValues({_outboxKey: '{"a":1}'});
      final analytics = build(FakeSender());

      await analytics.load();

      expect(analytics.bufferedCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_outboxKey), isNull);
    });
  });

  group('lifecycle', () {
    test('dispose leaves no timer pending', () {
      final analytics = build(FakeSender());
      analytics.log(event(GameballMessageEventType.impression));
      expect(analytics.hasScheduledFlush, isTrue);

      analytics.dispose();

      expect(analytics.hasScheduledFlush, isFalse);
    });

    test('a failed send after dispose does not re-arm', () async {
      final sender = FakeSender(result: GameballAnalyticsSendResult.retry);
      final analytics =
          build(sender, interval: const Duration(milliseconds: 10));
      analytics.log(event(GameballMessageEventType.impression));

      await analytics.flush();
      analytics.dispose();
      await pumpEventQueue();

      expect(analytics.hasScheduledFlush, isFalse,
          reason: 'a stopped module that keeps retrying forever is a leak');
      expect(analytics.bufferedCount, 1, reason: 'but the events are kept');
    });

    test('load reactivates after dispose, so a restart resumes', () async {
      final sender = FakeSender();
      final analytics =
          build(sender, interval: const Duration(milliseconds: 10));
      analytics.dispose();

      await analytics.load();
      analytics.log(event(GameballMessageEventType.impression));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sender.batches, hasLength(1));
      analytics.dispose();
    });

    test('flushing an empty outbox sends nothing', () async {
      final sender = FakeSender();
      final analytics = build(sender);

      await analytics.flush();

      expect(sender.batches, isEmpty);
    });
  });
}
