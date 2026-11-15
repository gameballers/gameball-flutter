import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _key = 'gameball_iam_display_history';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 8, 5, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the fallback cooldown is 30 seconds', () {
    // The live value now arrives with each sync, so this is only what applies
    // when a response omits it.
    expect(defaultDisplayCooldown, const Duration(seconds: 30));
  });

  group('InMemoryFrequencyCap', () {
    test('a fresh cap has shown nothing and no last display', () {
      final snapshot = InMemoryFrequencyCap().snapshot();

      expect(snapshot.shownCampaignIds, isEmpty);
      expect(snapshot.lastDisplayAt, isNull);
    });

    test('recording a display makes it visible in the next snapshot', () {
      final cap = InMemoryFrequencyCap()..recordDisplay(2041, t0);

      final snapshot = cap.snapshot();
      expect(snapshot.shownCampaignIds, {2041});
      expect(snapshot.lastDisplayByCampaign[2041], t0);
      expect(snapshot.lastDisplayAt, t0);
    });

    test('lastDisplayAt tracks the most recent display across campaigns', () {
      final cap = InMemoryFrequencyCap()
        ..recordDisplay(2041, t0)
        ..recordDisplay(2042, t0.add(const Duration(minutes: 5)));

      final snapshot = cap.snapshot();
      expect(snapshot.shownCampaignIds, {2041, 2042});
      expect(snapshot.lastDisplayAt, t0.add(const Duration(minutes: 5)),
          reason: 'the cooldown is global, so only the latest display matters');
    });

    test('a re-display overwrites that campaign own timestamp', () {
      final later = t0.add(const Duration(minutes: 5));
      final cap = InMemoryFrequencyCap()
        ..recordDisplay(2041, t0)
        ..recordDisplay(2041, later);

      expect(cap.snapshot().lastDisplayByCampaign[2041], later,
          reason: 'a repeatable campaign interval is measured from its most '
              'recent display, not its first');
    });

    test('a snapshot does not change when the cap is mutated afterwards', () {
      final cap = InMemoryFrequencyCap()..recordDisplay(2041, t0);
      final snapshot = cap.snapshot();

      cap.recordDisplay(2042, t0.add(const Duration(seconds: 1)));

      expect(snapshot.shownCampaignIds, {2041},
          reason: 'the evaluator must see a stable view of history');
    });

    test('a snapshot cannot be mutated by its holder', () {
      final snapshot =
          (InMemoryFrequencyCap()..recordDisplay(2041, t0)).snapshot();

      expect(() => snapshot.lastDisplayByCampaign[2042] = t0,
          throwsUnsupportedError);
    });

    test('nothing survives a new instance', () async {
      InMemoryFrequencyCap().recordDisplay(2041, t0);

      final fresh = InMemoryFrequencyCap();
      await fresh.load('c1');

      expect(fresh.snapshot().shownCampaignIds, isEmpty,
          reason: 'which is exactly why StoredFrequencyCap exists — with this '
              'one, a once-ever campaign returns on every cold start');
    });
  });

  group('StoredFrequencyCap — surviving a restart', () {
    test('a recorded display is readable by a fresh instance', () async {
      final first = StoredFrequencyCap();
      await first.load('c1');
      first.recordDisplay(2041, t0);
      await pumpEventQueue();

      final second = StoredFrequencyCap();
      await second.load('c1');

      expect(second.snapshot().lastDisplayByCampaign[2041], t0,
          reason: 'the backend requires "once ever" to hold locally too, which '
              'means across process death');
      expect(second.snapshot().lastDisplayAt, t0);
    });

    test('history from another customer is discarded, not inherited', () async {
      final first = StoredFrequencyCap();
      await first.load('c1');
      first.recordDisplay(2041, t0);
      await pumpEventQueue();

      final second = StoredFrequencyCap();
      await second.load('c2');

      expect(second.snapshot().shownCampaignIds, isEmpty,
          reason: 'attributing one customer display history to another is worse '
              'than showing a message twice');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), isNull, reason: 'and it is cleared, not kept');
    });

    test('load clears whatever was in memory first', () async {
      final cap = StoredFrequencyCap();
      await cap.load('c1');
      cap.recordDisplay(2041, t0);
      await pumpEventQueue();

      await cap.load('c2');

      expect(cap.snapshot().shownCampaignIds, isEmpty);
    });

    test('timestamps are normalised to UTC', () async {
      final cap = StoredFrequencyCap();
      await cap.load('c1');
      cap.recordDisplay(2041, DateTime(2026, 8, 5, 12));
      await pumpEventQueue();

      final reloaded = StoredFrequencyCap();
      await reloaded.load('c1');

      expect(reloaded.snapshot().lastDisplayByCampaign[2041]!.isUtc, isTrue,
          reason: 'a local timestamp written on one side of a DST change and '
              'read on the other would shift an interval by an hour');
    });

    test('corrupt storage is discarded rather than thrown', () async {
      SharedPreferences.setMockInitialValues({_key: 'not json'});
      final cap = StoredFrequencyCap();

      await cap.load('c1');

      expect(cap.snapshot().shownCampaignIds, isEmpty,
          reason: 'losing history shows a message twice; throwing here shows '
              'none at all');
    });

    test('unparseable entries are skipped individually', () async {
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode({
          'customerId': 'c1',
          'campaigns': {'2041': t0.toIso8601String(), 'oops': 'nope', '2042': 12},
        }),
      });
      final cap = StoredFrequencyCap();

      await cap.load('c1');

      expect(cap.snapshot().shownCampaignIds, {2041});
    });

    test('lastDisplayAt is the latest of the restored entries', () async {
      final later = t0.add(const Duration(hours: 3));
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode({
          'customerId': 'c1',
          'campaigns': {
            '2041': t0.toIso8601String(),
            '2042': later.toIso8601String(),
          },
        }),
      });
      final cap = StoredFrequencyCap();

      await cap.load('c1');

      expect(cap.snapshot().lastDisplayAt, later,
          reason: 'the global cooldown has to survive a restart too, or a kill '
              'and relaunch would let two messages show back to back');
    });
  });
}
