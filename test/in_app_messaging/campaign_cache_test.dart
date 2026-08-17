import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/source/campaign_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _key = 'gameball_iam_campaign_cache';

/// A sync response with one campaign and an explicit cooldown, so both halves of
/// the cached result can be checked.
String payload({int campaignId = 2041, int cooldown = 45}) => '''
{
  "cooldownSeconds": $cooldown,
  "messages": [
    { "campaignId": $campaignId, "messageType": 2,
      "trigger": {"type": "session_start"},
      "content": {}, "locale": {"message": "cached body"} }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, make) in <(String, CampaignCache Function())>[
    ('InMemoryCampaignCache', InMemoryCampaignCache.new),
    ('StoredCampaignCache', StoredCampaignCache.new),
  ]) {
    group('$name — shared behaviour', () {
      test('reads back what was written', () async {
        final cache = make();
        await cache.write('c1', payload());

        final result = await cache.read('c1');

        expect(result.campaigns.single.campaignId, 2041);
        expect(result.campaigns.single.message.body, 'cached body');
        expect(result.cooldown, const Duration(seconds: 45),
            reason: 'the cooldown has to survive with the campaigns, or a cached '
                'launch would silently fall back to the default');
      });

      test('reads nothing when there is nothing', () async {
        expect((await make().read('c1')).campaigns, isEmpty);
      });

      test('never serves one customer cache to another', () async {
        final cache = make();
        await cache.write('c1', payload());

        expect((await cache.read('c2')).campaigns, isEmpty,
            reason: 'this is the failure the scoping exists to prevent');
      });

      test('a write replaces rather than merges', () async {
        final cache = make();
        await cache.write('c1', payload(campaignId: 1));
        await cache.write('c1', payload(campaignId: 2));

        final result = await cache.read('c1');

        expect(result.campaigns.map((c) => c.campaignId), [2],
            reason: 'a sync response is the whole truth, so the cache mirrors it '
                'wholesale — the backend says "replace the entire cache"');
      });

      test('clear empties it', () async {
        final cache = make();
        await cache.write('c1', payload());

        await cache.clear();

        expect((await cache.read('c1')).campaigns, isEmpty);
      });

      test('a cached read reports no raw payload', () async {
        final cache = make();
        await cache.write('c1', payload());

        expect((await cache.read('c1')).rawJson, isNull,
            reason: 'otherwise a read could trigger a redundant write back');
      });
    });
  }

  group('StoredCampaignCache — durability', () {
    test('survives a new instance', () async {
      await StoredCampaignCache().write('c1', payload());

      final fresh = await StoredCampaignCache().read('c1');

      expect(fresh.campaigns.single.campaignId, 2041,
          reason: 'a launch with no network has to have something to show');
    });

    test('a mismatched customer clears the stored entry', () async {
      await StoredCampaignCache().write('c1', payload());

      await StoredCampaignCache().read('c2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), isNull);
    });

    test('corrupt storage reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({_key: 'not json'});

      expect((await StoredCampaignCache().read('c1')).campaigns, isEmpty);
    });

    test('a stored payload that no longer parses reads as empty', () async {
      await StoredCampaignCache().write('c1', '{"no":"messages"}');

      expect((await StoredCampaignCache().read('c1')).campaigns, isEmpty,
          reason: 'the payload is re-parsed by the current rules, so a response '
              'a newer SDK rejects is not resurrected as stale objects');
    });
  });
}
