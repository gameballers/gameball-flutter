import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/engagement/engagement.dart';
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/enums/push_engagement_type.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';
import 'package:gameball_sdk/network/request_calls/report_push_engagement_request.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStore implements ReceivedPushStore {
  List<ReceivedPush> saved = [];

  @override
  Future<List<ReceivedPush>> load() async => saved;

  @override
  Future<void> save(List<ReceivedPush> pushes) async => saved = List.of(pushes);
}

final _uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
final _isoUtcMillis = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

Map<String, dynamic> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('push-engagement request', () {
    late List<http.Request> requests;
    late int status;
    late MockClient client;

    setUp(() {
      requests = [];
      status = 202;
      client = MockClient((request) async {
        requests.add(request);
        return http.Response('', status);
      });
    });

    Future<http.Response> send(PushEngagementType type,
            {int occurredAt = 1794239373022,
            String? prefix,
            String? sessionToken}) =>
        reportPushEngagementRequest(
          clickToken: 'tok-1',
          type: type,
          occurredAt: occurredAt,
          apiKey: 'key-1',
          lang: 'en',
          customApiPrefix: prefix,
          sessionToken: sessionToken,
          client: client,
        );

    test('the numbers are the backend\'s own', () {
      expect(PushEngagementType.values.map((t) => t.value), [1, 2, 3]);
      expect(PushEngagementType.clicked.value, 1);
      expect(PushEngagementType.dismissed.value, 2);
      expect(PushEngagementType.influencedOpen.value, 3);
    });

    test('POSTs to /api/v4.0/integrations/mobile/push-engagement with the usual headers', () async {
      await send(PushEngagementType.clicked);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(),
          'https://api.gameball.co/api/v4.0/integrations/mobile/push-engagement');
      expect(request.headers['ApiKey'], 'key-1');
      expect(request.headers['Lang'], 'en');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['x-gb-agent'], startsWith('GB/flutter/'));
      expect(request.headers.containsKey('X-GB-TOKEN'), isFalse);
    });

    test('uses the custom API prefix, and stays on v4.0 with a session token', () async {
      await send(PushEngagementType.clicked, prefix: 'https://api.example.test', sessionToken: 'st-1');
      final request = requests.single;
      expect(request.url.toString(),
          'https://api.example.test/api/v4.0/integrations/mobile/push-engagement');
      expect(request.headers['X-GB-TOKEN'], 'st-1');
    });

    test('the body has exactly clickToken, engagementType (a number), eventUid and occurredAt', () async {
      await send(PushEngagementType.clicked);
      final body = bodyOf(requests.single);
      expect(body.keys.toSet(), {'clickToken', 'engagementType', 'eventUid', 'occurredAt'});
      expect(body['clickToken'], 'tok-1');
      expect(body['engagementType'], isA<int>());
      expect(body['engagementType'], 1);
    });

    test('each type sends its own number', () async {
      for (final type in PushEngagementType.values) {
        await send(type);
      }
      expect(requests.map((r) => bodyOf(r)['engagementType']), [1, 2, 3]);
    });

    test('every event gets a fresh v4 eventUid', () async {
      await send(PushEngagementType.clicked);
      await send(PushEngagementType.clicked);
      final uids = requests.map((r) => bodyOf(r)['eventUid'] as String).toList();
      expect(uids[0], matches(_uuidV4));
      expect(uids[1], matches(_uuidV4));
      expect(uids[0], isNot(uids[1]));
    });

    test('occurredAt is UTC ISO-8601 with milliseconds', () async {
      await send(PushEngagementType.clicked, occurredAt: 1794239373022);
      await send(PushEngagementType.clicked, occurredAt: 1794239373000);
      final times = requests.map((r) => bodyOf(r)['occurredAt']).toList();
      expect(times, ['2026-11-09T15:49:33.022Z', '2026-11-09T15:49:33.000Z']);
      expect(times[0], matches(_isoUtcMillis));
    });

    test('202 is accepted; any other answer fails after one attempt', () async {
      await send(PushEngagementType.clicked);
      for (final code in [400, 401, 404, 422, 503]) {
        status = code;
        requests.clear();
        await expectLater(send(PushEngagementType.clicked), throwsA(isA<Exception>()));
        expect(requests, hasLength(1), reason: 'one attempt for $code');
      }
    });

    test('the body builder keeps a given eventUid, for a retry of the same event', () {
      final body = pushEngagementBody(
          clickToken: 'tok-1',
          type: PushEngagementType.influencedOpen,
          occurredAt: 1794239373022,
          eventUid: 'uid-1');
      expect(body, {
        'clickToken': 'tok-1',
        'engagementType': 3,
        'eventUid': 'uid-1',
        'occurredAt': '2026-11-09T15:49:33.022Z',
      });
    });
  });

  group('GameballApp reports', () {
    final app = GameballApp.getInstance();
    late List<http.Request> requests;
    late int status;
    late MemoryStore store;
    late List<String> lines;
    late int clock;
    late Engagement engagement;

    setUp(() {
      requests = [];
      status = 202;
      GameballApp.debugHttpClient = MockClient((request) async {
        requests.add(request);
        return http.Response('', status);
      });
      store = MemoryStore();
      lines = [];
      clock = 1794239373022;
      // The wait before an influenced open is decided moves the clock on, so
      // occurredAt must come from the open, not from the decision
      engagement = Engagement(
          store: store, now: () => clock, log: lines.add, waitForTap: () async => clock += 10000);
      GameballApp.debugEngagement = engagement;
      app.init(GameballConfigBuilder().apiKey('key-1').lang('en').build());
    });

    tearDown(() {
      GameballApp.debugHttpClient = null;
      GameballApp.debugEngagement = null;
    });

    Future<void> settle() async {
      await engagement.settled;
      await pumpEventQueue();
    }

    GameballPushPayload push(String token) =>
        GameballPushPayload.from({'isGB': 'true', 'gbClickToken': token})!;

    test('a tap sends clicked (1), at the time the SDK handled it', () async {
      bool? reported;
      expect(app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-x'},
          callback: (status, error) => reported = status), isTrue);
      await settle();
      final request = requests.single;
      expect(request.url.path, '/api/v4.0/integrations/mobile/push-engagement');
      final body = bodyOf(request);
      expect(body['engagementType'], 1);
      expect(body['clickToken'], 'tok-x');
      expect(body['occurredAt'], '2026-11-09T15:49:33.022Z');
      expect(body['eventUid'], matches(_uuidV4));
      expect(reported, isTrue);
    });

    test('the same tap twice sends once', () async {
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-x'});
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-x'});
      await settle();
      expect(requests, hasLength(1));
    });

    test('a tap without a click token is logged but sends nothing', () async {
      expect(app.handlePushClick({'isGB': 'true', 'google.message_id': 'm-1'}), isTrue);
      await settle();
      expect(lines, contains('GameballApp engagement push_click clickToken=null'));
      expect(requests, isEmpty);
    });

    test('a non-Gameball tap sends nothing', () async {
      expect(app.handlePushClick({'gbClickToken': 'tok-x'}), isFalse);
      await settle();
      expect(requests, isEmpty);
    });

    test('a rejected tap report reaches the callback, after one attempt', () async {
      status = 503;
      bool? reported;
      Exception? failure;
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-x'}, callback: (status, error) {
        reported = status;
        failure = error;
      });
      await settle();
      expect(requests, hasLength(1));
      expect(reported, isFalse);
      expect(failure.toString(), contains('503'));
    });

    test('an influenced open sends influencedOpen (3), at the open\'s openedAt', () async {
      engagement.appOpens.onForeground(); // on screen (init may already have opened)
      await settle();
      await engagement.onReceived(push('tok-a'));
      engagement.appOpens.onBackground();
      clock += 31000;
      final openedAt = clock;
      engagement.appOpens.onForeground(); // icon open
      await settle();
      expect(lines.last, startsWith('GameballApp engagement influenced_open clickToken=tok-a '));
      final body = bodyOf(requests.single);
      expect(body['engagementType'], 3);
      expect(body['clickToken'], 'tok-a');
      expect(body['occurredAt'],
          DateTime.fromMillisecondsSinceEpoch(openedAt, isUtc: true).toIso8601String());
      expect(clock, greaterThan(openedAt), reason: 'decided after the wait');
    });

    test('an influenced open of a push without a click token is logged but sends nothing', () async {
      engagement.appOpens.onForeground();
      await settle();
      await engagement.onReceived(GameballPushPayload.from({'isGB': 'true', 'google.message_id': 'm-1'})!);
      engagement.appOpens.onBackground();
      clock += 31000;
      engagement.appOpens.onForeground();
      await settle();
      expect(lines.last, startsWith('GameballApp engagement influenced_open clickToken=null '));
      expect(requests, isEmpty);
    });

    test('an open caused by a tap sends the click only, never an influenced open', () async {
      engagement.appOpens.onForeground();
      await settle();
      await engagement.onReceived(push('tok-a'));
      await engagement.onReceived(push('tok-b'));
      engagement.appOpens.onBackground();
      clock += 31000;
      app.handlePushClick({'isGB': 'true', 'gbClickToken': 'tok-b'}); // while away
      engagement.appOpens.onForeground();
      await settle();
      expect(requests.map((r) => bodyOf(r)['engagementType']), [1]);
      expect(bodyOf(requests.single)['clickToken'], 'tok-b');
    });

    test('app_open and push_received send nothing', () async {
      engagement.appOpens.onForeground();
      await settle();
      await app.handlePushReceived({'isGB': 'true', 'gbClickToken': 'tok-a'});
      engagement.appOpens.onBackground();
      clock += 31000;
      await engagement.onCustomerChanged(); // nothing saved any more
      engagement.appOpens.onForeground();
      await settle();
      expect(lines.where((l) => l.contains('app_open')), isNotEmpty);
      expect(lines.where((l) => l.contains('push_received')), isNotEmpty);
      expect(requests, isEmpty);
    });

    test('a failed influenced-open report is logged and never throws', () async {
      status = 503;
      engagement.appOpens.onForeground();
      await settle();
      await engagement.onReceived(push('tok-a'));
      engagement.appOpens.onBackground();
      clock += 31000;
      engagement.appOpens.onForeground();
      await settle();
      expect(requests, hasLength(1));
      expect(lines.last, startsWith('GameballApp could not report influenced_open'));
    });
  });
}
