import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gameball_sdk/in_app_messaging/personalisation/variable_source.dart';

void main() {
  group('CachingVariableSource', () {
    test('fetches once and serves the cache inside the ttl', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 8, 17, 12);
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          return <String, String>{'points_balance': '1,250'};
        },
        ttl: const Duration(seconds: 60),
        clock: () => now,
      );

      expect(await source.fetch('c1'), {'points_balance': '1,250'});
      now = now.add(const Duration(seconds: 30));
      expect(await source.fetch('c1'), {'points_balance': '1,250'});

      expect(calls, 1, reason: 'several messages in one burst share one fetch');
    });

    test('refetches once the ttl has passed', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 8, 17, 12);
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          return <String, String>{'n': '$calls'};
        },
        ttl: const Duration(seconds: 60),
        clock: () => now,
      );

      await source.fetch('c1');
      now = now.add(const Duration(seconds: 61));

      expect(await source.fetch('c1'), {'n': '2'});
      expect(calls, 2);
    });

    test('a different customer never reads the previous one\'s cache', () async {
      final now = DateTime.utc(2026, 8, 17, 12);
      final source = CachingVariableSource(
        fetcher: (id) async => <String, String>{'who': id},
        clock: () => now,
      );

      expect(await source.fetch('c1'), {'who': 'c1'});
      expect(await source.fetch('c2'), {'who': 'c2'},
          reason: 'one customer being personalised with another one\'s name is '
              'the worst outcome this whole feature can produce');
    });

    test('clear() drops the cache', () async {
      var calls = 0;
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          return <String, String>{};
        },
      );

      await source.fetch('c1');
      source.clear();
      await source.fetch('c1');

      expect(calls, 2);
    });

    test('a failing fetch yields an empty map rather than throwing', () async {
      final source = CachingVariableSource(
        fetcher: (_) async => throw StateError('offline'),
      );

      expect(await source.fetch('c1'), isEmpty,
          reason: 'the only correct response to every documented failure is '
              '"use the text you already hold"');
    });

    test('a failure is not cached', () async {
      var calls = 0;
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return <String, String>{'ok': 'yes'};
        },
      );

      expect(await source.fetch('c1'), isEmpty);
      expect(await source.fetch('c1'), {'ok': 'yes'},
          reason: 'a failure is a moment, not a value — caching it would turn '
              'one dead request into a minute of stale text');
    });
  });

  group('CachingVariableSource — surviving a restart', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    CachingVariableSource build({
      required Future<Map<String, String>> Function(String) fetcher,
      Set<String> retain = const <String>{'first_name', 'points_balance'},
    }) {
      final source = CachingVariableSource(fetcher: fetcher);
      source.retainOnly(retain);
      return source;
    }

    test('a failed fetch falls back to the last values that worked', () async {
      var online = true;
      final first = build(
        fetcher: (_) async => online
            ? <String, String>{'points_balance': '1,250'}
            : throw StateError('offline'),
      );
      await first.fetch('c1');

      // A new launch: nothing in memory, and the network is gone.
      online = false;
      final afterRestart = build(fetcher: (_) async => throw StateError('offline'));

      expect(await afterRestart.fetch('c1'), {'points_balance': '1,250'},
          reason: 'a slightly old number reads correctly; a raw {token} does '
              'not');
    });

    test('only the tokens campaigns actually use are written', () async {
      final source = build(
        fetcher: (_) async => <String, String>{
          'first_name': 'Ahmed',
          'points_balance': '1,250',
          'player_email': 'ahmed@example.com',
          'player_last_name': 'El Assy',
        },
        retain: const <String>{'first_name', 'points_balance'},
      );
      await source.fetch('c1');

      final restored = build(fetcher: (_) async => throw StateError('offline'));

      expect(await restored.fetch('c1'),
          {'first_name': 'Ahmed', 'points_balance': '1,250'},
          reason: 'no campaign mentions the email, so there is no reason for '
              'it to sit on the device');
    });

    test('the live fetch still returns everything, filtering is only on disk',
        () async {
      final source = build(
        fetcher: (_) async => <String, String>{
          'first_name': 'Ahmed',
          'player_email': 'ahmed@example.com',
        },
        retain: const <String>{'first_name'},
      );

      expect(await source.fetch('c1'), hasLength(2),
          reason: 'a token a campaign gained since the last sync should still '
              'substitute while we hold real values');
    });

    test('another customer never reads the stored values', () async {
      final source = build(
        fetcher: (_) async => <String, String>{'first_name': 'Ahmed'},
      );
      await source.fetch('c1');

      final other = build(fetcher: (_) async => throw StateError('offline'));

      expect(await other.fetch('c2'), isEmpty,
          reason: 'showing one person their name in another person\'s session '
              'is the worst thing this feature can do');
    });

    test('clear() removes the stored values too', () async {
      final source = build(
        fetcher: (_) async => <String, String>{'first_name': 'Ahmed'},
      );
      await source.fetch('c1');
      source.clear();
      // clear() is fire-and-forget so a logout never waits on storage; let the
      // removal land before checking.
      await pumpEventQueue();

      final restored = build(fetcher: (_) async => throw StateError('offline'));

      expect(await restored.fetch('c1'), isEmpty,
          reason: 'logout must not leave a name on the device');
    });

    test('retaining nothing stores nothing', () async {
      final source = build(
        fetcher: (_) async => <String, String>{'first_name': 'Ahmed'},
        retain: const <String>{},
      );
      await source.fetch('c1');

      final restored = build(fetcher: (_) async => throw StateError('offline'));

      expect(await restored.fetch('c1'), isEmpty,
          reason: 'no campaign uses tokens, so nothing is worth keeping');
    });
  });
}
