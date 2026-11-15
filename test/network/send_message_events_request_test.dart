import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/batched_message_analytics.dart';
import 'package:gameball_sdk/network/request_calls/send_message_events_request.dart';
import 'package:http/http.dart' as http;

/// One well-formed event, since these tests are about the response rather than
/// the payload.
final List<Map<String, dynamic>> oneEvent = [
  <String, dynamic>{
    'eventUid': 'e1',
    'type': 'impression',
    'campaignId': 2041,
    'occurredAt': '2026-08-10T09:14:22.000Z',
  },
];

/// Runs a request against a stubbed transport and returns the verdict.
Future<GameballAnalyticsSendResult> post({
  int status = 202,
  String body = '{"accepted":1,"rejected":0}',
  void Function(http.Request request)? inspect,
}) async {
  return http.runWithClient(
    () => sendMessageEventsRequest(
      oneEvent,
      customerId: 'customer-1',
      platform: 1,
      apiKey: 'key',
      lang: 'en',
    ),
    () => MockClient((request) async {
      inspect?.call(request);
      return http.Response(body, status);
    }),
  );
}

void main() {
  group('the request', () {
    test('posts to the v4 integrations path', () async {
      Uri? seen;
      await post(inspect: (r) => seen = r.url);

      expect(seen!.path, '/api/v4.0/integrations/inapp-messages/events');
    });

    test('names the customer in the body, not the query', () async {
      Uri? url;
      Map<String, dynamic>? body;
      await post(inspect: (r) {
        url = r.url;
        body = jsonDecode(r.body) as Map<String, dynamic>;
      });

      expect(url!.query, isEmpty,
          reason: 'v4 carries identity in the body; there is no '
              'playerUniqueId parameter and no encrypted id');
      expect(body!['customerId'], 'customer-1');
    });

    test('sends the platform and events at the top level', () async {
      Map<String, dynamic>? body;
      await post(inspect: (r) => body = jsonDecode(r.body) as Map<String, dynamic>);

      expect(body!['platform'], 1);
      expect(body!['events'], hasLength(1));
    });

    test('carries the standard headers', () async {
      Map<String, String>? headers;
      await post(inspect: (r) => headers = r.headers);

      expect(headers!['ApiKey'], 'key');
      expect(headers!['Lang'], 'en');
      expect(headers!['x-gb-agent'], startsWith('GB/flutter/'));
    });
  });

  group('status codes decide the outcome', () {
    // V4 reports failure with the status code rather than inside a 200, so the
    // envelope reader this function used to carry is gone. Every case below was
    // measured against api.alpha.gameball.app on 2026-08-17.

    test('202 with counts is accepted', () async {
      expect(await post(status: 202), GameballAnalyticsSendResult.accepted);
    });

    test('a partial rejection still clears the batch', () async {
      // Verified live: a mixed batch returns 202 {accepted:1, rejected:1}. The
      // good events landed, and the rejected ones can never succeed.
      expect(
        await post(status: 202, body: '{"accepted":1,"rejected":1}'),
        GameballAnalyticsSendResult.accepted,
      );
    });

    test('an unreadable 2xx body is still accepted', () async {
      expect(await post(status: 202, body: 'not json'),
          GameballAnalyticsSendResult.accepted,
          reason: 'the counts are diagnostics; the status said it landed');
    });

    test('400 is discarded', () async {
      expect(await post(status: 400, body: '{"code":3000}'),
          GameballAnalyticsSendResult.discard);
    });

    test('401 is discarded', () async {
      expect(await post(status: 401), GameballAnalyticsSendResult.discard);
    });

    test('404 is discarded', () async {
      expect(await post(status: 404, body: '{"code":7000}'),
          GameballAnalyticsSendResult.discard);
    });

    test('422 is discarded', () async {
      // Overloaded on purpose by the backend: a deactivated customer and a batch
      // in which every event was malformed both land here. Both are permanent
      // for this batch, so they share an outcome — but do not read a 422 as
      // "the customer is deactivated".
      expect(await post(status: 422, body: '{"code":3003}'),
          GameballAnalyticsSendResult.discard);
    });

    test('408 is retried', () async {
      expect(await post(status: 408), GameballAnalyticsSendResult.retry);
    });

    test('429 is retried', () async {
      expect(await post(status: 429), GameballAnalyticsSendResult.retry);
    });

    test('5xx is retried', () async {
      expect(await post(status: 500), GameballAnalyticsSendResult.retry);
    });

    test('503 is retried', () async {
      expect(await post(status: 503), GameballAnalyticsSendResult.retry,
          reason: 'the documented "broker unavailable" case');
    });

    test('a transport failure is retried', () async {
      final result = await http.runWithClient(
        () => sendMessageEventsRequest(
          oneEvent,
          customerId: 'customer-1',
          platform: 1,
          apiKey: 'key',
          lang: 'en',
        ),
        () => MockClient((_) async => throw const _NoNetwork()),
      );

      expect(result, GameballAnalyticsSendResult.retry);
    });
  });
}

class _NoNetwork implements Exception {
  const _NoNetwork();
}

/// A minimal stand-in for `package:http`'s testing client, which is a separate
/// dependency this package does not carry.
class MockClient extends http.BaseClient {
  MockClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replayed = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await _handler(replayed);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
