import 'package:flutter_test/flutter_test.dart';
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
}
