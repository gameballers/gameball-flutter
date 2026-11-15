import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/network/request_calls/sync_in_app_messages_request.dart';
import 'package:http/http.dart' as http;

/// Runs a sync against a stubbed transport and returns what the caller gets.
Future<String?> sync({
  int status = 200,
  String body = '{"cooldownSeconds":30,"messages":[]}',
  int platform = 2,
  void Function(http.Request request)? inspect,
}) async {
  return http.runWithClient(
    () => syncInAppMessagesRequest(
      customerId: 'customer-1',
      platform: platform,
      locale: 'en',
      appVersion: '1.0.0',
      sdkVersion: '3.3.0',
      apiKey: 'key',
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
      await sync(inspect: (r) => seen = r.url);

      expect(seen!.path, '/api/v4.0/integrations/inapp-messages/sync');
    });

    test('names the customer in the body, not the query', () async {
      Uri? url;
      Map<String, dynamic>? body;
      await sync(inspect: (r) {
        url = r.url;
        body = jsonDecode(r.body) as Map<String, dynamic>;
      });

      expect(url!.query, isEmpty,
          reason: 'v4 dropped both playerUniqueId and the encrypted playerId');
      expect(body!['customerId'], 'customer-1');
    });

    test('sends the targeting fields the backend selects on', () async {
      Map<String, dynamic>? body;
      await sync(inspect: (r) => body = jsonDecode(r.body) as Map<String, dynamic>);

      expect(body, {
        'customerId': 'customer-1',
        'platform': 2,
        'locale': 'en',
        'appVersion': '1.0.0',
        'sdkVersion': '3.3.0',
      });
    });

    test('carries the standard headers', () async {
      Map<String, String>? headers;
      await sync(inspect: (r) => headers = r.headers);

      expect(headers!['ApiKey'], 'key');
      expect(headers!['Lang'], 'en');
      expect(headers!['x-gb-agent'], startsWith('GB/flutter/'));
    });
  });

  group('the response', () {
    test('a 200 body is returned verbatim, for the cache to store', () async {
      const payload = '{"cooldownSeconds":45,"messages":[]}';

      expect(await sync(body: payload), payload);
    });

    test('every non-2xx yields null, so the previous cache survives', () async {
      for (final status in <int>[400, 401, 404, 422, 500, 503]) {
        expect(await sync(status: status, body: '{"code":1}'), isNull,
            reason: 'HTTP $status is "could not ask", not "no campaigns"');
      }
    });

    test('a transport failure yields null', () async {
      final result = await http.runWithClient(
        () => syncInAppMessagesRequest(
          customerId: 'customer-1',
          platform: 2,
          locale: 'en',
          appVersion: '1.0.0',
          sdkVersion: '3.3.0',
          apiKey: 'key',
        ),
        () => MockClient((_) async => throw const _NoNetwork()),
      );

      expect(result, isNull);
    });
  });

  group('platform', () {
    // The backend answers an unrecognised platform with 200 and an empty message
    // list rather than an error, and getDevicePlatformCode() sends 0 on macOS,
    // web and every desktop target. Both verified against alpha on 2026-08-17.
    // These tests pin the request down; the log is what makes the silence
    // diagnosable.

    test('an unknown platform is still sent, not corrected', () async {
      Map<String, dynamic>? body;
      await sync(
        platform: 0,
        inspect: (r) => body = jsonDecode(r.body) as Map<String, dynamic>,
      );

      expect(body!['platform'], 0,
          reason: 'reporting a platform we are not is worse than reporting '
              'one the backend does not target');
    });

    test('an empty list from an unknown platform is a success, not a failure',
        () async {
      const empty = '{"cooldownSeconds":30,"messages":[]}';

      expect(await sync(platform: 0, body: empty), empty,
          reason: 'null would mean "could not ask" and would wrongly preserve '
              'a cache from a platform that does have campaigns');
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
