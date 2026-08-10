import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 5, 12);

  test('the fallback cooldown is 30 seconds', () {
    // The live value now arrives with each sync, so this is only what applies
    // when a response omits it.
    expect(defaultDisplayCooldown, const Duration(seconds: 30));
  });

  test('a fresh cap has shown nothing and no last display', () {
    final snapshot = InMemoryFrequencyCap().snapshot();

    expect(snapshot.shownCampaignIds, isEmpty);
    expect(snapshot.lastDisplayAt, isNull);
  });

  test('load completes for the in-memory implementation', () async {
    await expectLater(InMemoryFrequencyCap().load(), completes);
  });

  test('recording a display makes it visible in the next snapshot', () {
    final cap = InMemoryFrequencyCap()..recordDisplay(2041, t0);

    final snapshot = cap.snapshot();
    expect(snapshot.shownCampaignIds, {2041});
    expect(snapshot.lastDisplayAt, t0);
  });

  test('lastDisplayAt tracks the most recent display across campaigns', () {
    final cap = InMemoryFrequencyCap()
      ..recordDisplay(2041, t0)
      ..recordDisplay(2042, t0.add(const Duration(minutes: 5)));

    final snapshot = cap.snapshot();
    expect(snapshot.shownCampaignIds, {2041, 2042});
    expect(snapshot.lastDisplayAt, t0.add(const Duration(minutes: 5)),
        reason: 'the floor is global, so only the latest display matters');
  });

  test('reset clears both shown ids and the last display', () {
    final cap = InMemoryFrequencyCap()
      ..recordDisplay(2041, t0)
      ..reset();

    final snapshot = cap.snapshot();
    expect(snapshot.shownCampaignIds, isEmpty);
    expect(snapshot.lastDisplayAt, isNull);
  });

  test('a snapshot does not change when the cap is mutated afterwards', () {
    final cap = InMemoryFrequencyCap()..recordDisplay(2041, t0);
    final snapshot = cap.snapshot();

    cap.recordDisplay(2042, t0.add(const Duration(seconds: 1)));

    expect(snapshot.shownCampaignIds, {2041},
        reason: 'the evaluator must see a stable view of cap state');
  });

  test('a snapshot cannot be mutated by its holder', () {
    final snapshot = (InMemoryFrequencyCap()..recordDisplay(2041, t0)).snapshot();

    expect(() => snapshot.shownCampaignIds.add(2042), throwsUnsupportedError);
  });
}
