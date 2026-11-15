import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/network/request_calls/fetch_message_variables_request.dart';
import 'package:http/http.dart' as http;

/// Runs a variables fetch against a stubbed transport.
Future<Map<String, String>> fetch({
  int status = 200,
  String body = '{"variables":{"first_name":"Ahmed"}}',
  void Function(http.Request request)? inspect,
}) async {
  return http.runWithClient(
    () => fetchMessageVariablesRequest(
      customerId: 'customer-1',
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
    test('posts to the v4 variables path', () async {
      Uri? seen;
      await fetch(inspect: (r) => seen = r.url);

      expect(seen!.path, '/api/v4.0/integrations/inapp-messages/variables');
    });

    test('sends only the customer id', () async {
      Map<String, dynamic>? body;
      await fetch(inspect: (r) => body = jsonDecode(r.body) as Map<String, dynamic>);

      expect(body, {'customerId': 'customer-1'});
    });
  });

  group('the response', () {
    test('reads the variables map', () async {
      expect(
        await fetch(body: '{"variables":{"first_name":"Ahmed","pts":"1,250"}}'),
        {'first_name': 'Ahmed', 'pts': '1,250'},
      );
    });

    test('values arrive pre-formatted and are not reinterpreted', () async {
      expect(await fetch(body: '{"variables":{"points_balance":"1,250"}}'),
          {'points_balance': '1,250'},
          reason: 'the separator is the server\'s formatting decision, and '
              'parsing it back to a number would lose it');
    });

    test('a non-string value is coerced rather than dropped', () async {
      expect(await fetch(body: '{"variables":{"count":7}}'), {'count': '7'});
    });

    test('a null value is dropped, leaving its token intact', () async {
      expect(await fetch(body: '{"variables":{"a":"1","b":null}}'), {'a': '1'},
          reason: 'an absent key leaves {b} as written, which is the '
              'forward-compatible behaviour the contract asks for');
    });

    test('every failure status yields an empty map', () async {
      for (final status in <int>[400, 401, 404, 422, 500, 503]) {
        expect(await fetch(status: status, body: '{"code":1}'), isEmpty,
            reason: 'HTTP $status means "display the text you already hold"');
      }
    });

    test('a 404 with no body — the undeployed endpoint — yields empty',
        () async {
      // Measured on alpha 2026-08-17: the endpoint is not deployed and answers
      // with a bare 404, byte-identical to a nonexistent path.
      expect(await fetch(status: 404, body: ''), isEmpty);
    });

    test('an unreadable body yields empty rather than throwing', () async {
      expect(await fetch(body: 'not json'), isEmpty);
    });

    test('a payload with no variables key yields empty', () async {
      expect(await fetch(body: '{"other":1}'), isEmpty);
    });

    test('a transport failure yields empty', () async {
      final result = await http.runWithClient(
        () => fetchMessageVariablesRequest(
          customerId: 'customer-1',
          apiKey: 'key',
          lang: 'en',
        ),
        () => MockClient((_) async => throw const _NoNetwork()),
      );

      expect(result, isEmpty);
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
