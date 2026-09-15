import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/source/http_message_source.dart';

const String _ok = '''
{ "cooldownSeconds": 45,
  "messages": [ { "campaignId": 2051, "messageType": 2,
    "trigger": {"type": "session_start"},
    "content": {}, "locale": {"message": "hello"} } ] }
''';

void main() {
  const audience = CustomerAudience('customer-1');

  test('sends the audience customer id and parses the body', () async {
    final asked = <String>[];
    final source = HttpMessageSource((customerId) async {
      asked.add(customerId);
      return _ok;
    });

    final result = await source.fetch(audience);

    expect(asked, ['customer-1']);
    expect(result.campaigns.single.campaignId, 2051);
    expect(result.cooldown, const Duration(seconds: 45));
    expect(result.rawJson, isNotNull,
        reason: 'the caller stores the payload, so the body has to survive '
            'parsing rather than being discarded');
  });

  test('a null body throws rather than reporting an empty sync', () async {
    final source = HttpMessageSource((_) async => null);

    await expectLater(
      source.fetch(audience),
      throwsA(isA<GameballSyncFailure>()),
      reason: 'the caller treats a failure and an empty success differently — '
          'one keeps the previous cache, the other replaces it. Returning empty '
          'here would silently wipe a good cache on every network blip',
    );
  });

  test('a successful but empty sync is not a failure', () async {
    final source = HttpMessageSource(
      (_) async => '{"messages":[]}',
    );

    final result = await source.fetch(audience);

    expect(result.campaigns, isEmpty,
        reason: 'the backend said "nothing for this user", which is an answer');
  });

  test('a rejected sync yields no campaigns without throwing', () async {
    final source = HttpMessageSource(
      (_) async => '{"detail":"a payload with no messages array"}',
    );

    final result = await source.fetch(audience);

    expect(result.campaigns, isEmpty);
  });
}
