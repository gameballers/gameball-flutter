import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/campaign_key.dart';

void main() {
  test('a message and a game with the same number are different keys', () {
    // The contract warns these sequences overlap. Keying on the bare number
    // would make one campaign's history suppress the other's.
    expect(const CampaignKey.message(9645) == const CampaignKey.game(9645),
        isFalse);
  });

  test('equal keys share a hash, so they collapse in a map', () {
    final seen = <CampaignKey, int>{};
    seen[const CampaignKey.game(9645)] = 1;
    seen[const CampaignKey.game(9645)] = 2;
    expect(seen.length, 1);
    expect(seen[const CampaignKey.game(9645)], 2);
  });

  test('round-trips through its storage form', () {
    for (final key in const [
      CampaignKey.message(2215),
      CampaignKey.game(9645),
    ]) {
      expect(CampaignKey.parse(key.storageKey), key);
    }
  });

  test('a bare number parses as a message, for histories written before this',
      () {
    expect(CampaignKey.parse('2215'), const CampaignKey.message(2215));
  });

  test('unparseable input is null rather than a wrong key', () {
    for (final bad in const ['', 'game:', 'game:abc', 'other:1', ':1']) {
      expect(CampaignKey.parse(bad), isNull, reason: bad);
    }
  });
}
