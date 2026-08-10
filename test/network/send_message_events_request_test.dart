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
  int status = 200,
  String body = '{"success":true,"response":{"accepted":1,"rejected":0}}',
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
    test('identifies the customer as playerUniqueId in the query', () async {
      Uri? seen;
      await post(inspect: (r) => seen = r.url);

      expect(seen!.path, '/api/v1.0/bots/inapp/events');
      expect(seen!.queryParameters['playerUniqueId'], 'customer-1',
          reason: 'identity comes from the external customer id, which is the '
              'only one this SDK holds');
    });

    test('sends the platform and events at the top level', () async {
      Map<String, dynamic>? sent;
      await post(inspect: (r) => sent = jsonDecode(r.body));

      expect(sent!['platform'], 1);
      expect((sent!['events'] as List).single['eventUid'], 'e1');
    });

    test('carries the standard headers', () async {
      Map<String, String>? headers;
      await post(inspect: (r) => headers = r.headers);

      expect(headers!['ApiKey'], 'key');
      expect(headers!['Lang'], 'en');
      expect(headers!['x-gb-agent'], startsWith('GB/flutter/'));
    });
  });

  group('the envelope, which reports failure inside a 200', () {
    test('success:true is accepted', () async {
      expect(await post(), GameballAnalyticsSendResult.accepted);
    });

    test('success:false is discarded, not treated as a success', () async {
      final result = await post(
        body: '{"success":false,'
            '"errorMsg":"Batch exceeds the maximum of 50 events","errorCode":4}',
      );

      expect(result, GameballAnalyticsSendResult.discard,
          reason: 'reading the status code alone would drop these events while '
              'reporting them as delivered — the worst of both outcomes');
    });

    test('a partial rejection still clears the batch', () async {
      final result = await post(
        body: '{"success":true,"response":{"accepted":9,"rejected":1}}',
      );

      expect(result, GameballAnalyticsSendResult.accepted,
          reason: 'rejected events "will never succeed", and the response does '
              'not say which, so retrying the batch would resend the nine that '
              'were accepted');
    });

    test('an unreadable 200 is retried', () async {
      expect(await post(body: '<html>gateway</html>'),
          GameballAnalyticsSendResult.retry,
          reason: 'more likely a proxy than the backend');
    });

    test('a 200 whose body is not an object is retried', () async {
      expect(await post(body: '[1,2,3]'), GameballAnalyticsSendResult.retry);
    });
  });

  group('status codes', () {
    test('5xx is retried', () async {
      expect(await post(status: 503), GameballAnalyticsSendResult.retry);
    });

    test('429 is retried', () async {
      expect(await post(status: 429), GameballAnalyticsSendResult.retry,
          reason: 'throttling is transient by definition');
    });

    test('408 is retried', () async {
      expect(await post(status: 408), GameballAnalyticsSendResult.retry);
    });

    test('401 is discarded', () async {
      expect(await post(status: 401), GameballAnalyticsSendResult.discard,
          reason: 'an unchanged retry cannot fix an auth failure, and the outbox '
              'is FIFO — retrying forever would block every later event');
    });

    test('400 is discarded', () async {
      expect(await post(status: 400), GameballAnalyticsSendResult.discard);
    });

    test('a transport failure is retried', () async {
      final result = await http.runWithClient(
        () => sendMessageEventsRequest(
          oneEvent,
          customerId: 'c1',
          platform: 2,
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
