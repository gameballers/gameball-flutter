import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/quiet_hours.dart';

/// Local, not UTC: the window is the marketer's `HH:mm` as typed, and it is
/// judged on the device's own clock (decided with product 2026-09-05), so the
/// hour that matters is the local hour.
///
/// Building these as local literals is also what keeps this suite
/// machine-independent: 23:00 local is inside a 22:00–08:00 window in Cairo and
/// in Los Angeles alike.
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 8, 24, hour, minute);

void main() {
  group(
      "the window is judged on the device's clock, however the instant is "
      'expressed', () {
    const night = GameballQuietHours(startMinute: 22 * 60, endMinute: 8 * 60);

    test('the same instant gives the same answer as local or as UTC', () {
      final instant = DateTime(2026, 8, 24, 23, 30);

      expect(night.contains(instant), isTrue);
      expect(night.contains(instant.toUtc()), isTrue,
          reason: 'toUtc() changes only the representation, not the instant, '
              'so the verdict must not move with how the caller wrote it');
    });

    test('an instant outside the window is outside it either way', () {
      final instant = DateTime(2026, 8, 24, 12, 0);

      expect(night.contains(instant), isFalse);
      expect(night.contains(instant.toUtc()), isFalse);
    });

    test('a UTC-expressed instant is judged by its local hour', () {
      // 23:30 local, written as UTC. Unless the device runs on UTC its UTC hour
      // is a different number, and the verdict must still follow the local one.
      final instant = DateTime(2026, 8, 24, 23, 30).toUtc();

      expect(night.contains(instant), isTrue);
      expect(instant.toLocal().hour, 23);
    });
  });

  group('a window that wraps past midnight', () {
    const night = GameballQuietHours(startMinute: 22 * 60, endMinute: 8 * 60);

    test('covers the late evening',
        () => expect(night.contains(at(23)), isTrue));
    test('covers the small hours', () => expect(night.contains(at(2)), isTrue));
    test('is open at midday', () => expect(night.contains(at(12)), isFalse));

    test('includes its start minute', () {
      expect(night.contains(at(22, 0)), isTrue);
      expect(night.contains(at(21, 59)), isFalse);
    });

    test('excludes its end minute, so 08:00 is already daytime', () {
      expect(night.contains(at(7, 59)), isTrue);
      expect(night.contains(at(8, 0)), isFalse,
          reason: 'half-open, or a window ending where another begins would '
              'overlap by a minute');
    });
  });

  group('a window inside one day', () {
    const lunch = GameballQuietHours(startMinute: 9 * 60, endMinute: 17 * 60);

    test('covers the middle', () => expect(lunch.contains(at(12)), isTrue));
    test('is open before', () => expect(lunch.contains(at(8, 59)), isFalse));
    test('is open after', () => expect(lunch.contains(at(17)), isFalse));
  });

  group('parsing what the backend sends', () {
    test('reads the live shape', () {
      final window = parseQuietHours(<String, dynamic>{
        'enabled': true,
        'start': '22:00',
        'end': '08:00',
      });

      expect(window, isNotNull);
      expect(window!.startMinute, 22 * 60);
      expect(window.endMinute, 8 * 60);
    });

    test('disabled means no window at all', () {
      expect(
        parseQuietHours(<String, dynamic>{
          'enabled': false,
          'start': '22:00',
          'end': '08:00',
        }),
        isNull,
      );
    });

    test('absent means no window', () => expect(parseQuietHours(null), isNull));

    test('a start equal to its end is treated as no window', () {
      // Zero length or twenty-four hours, and nothing says which. Refusing to
      // guess beats silencing every campaign on the account over a typo.
      expect(
        parseQuietHours(<String, dynamic>{
          'enabled': true,
          'start': '22:00',
          'end': '22:00',
        }),
        isNull,
      );
    });

    test('an unreadable time is no window rather than a wrong one', () {
      for (final bad in <Object?>[
        '", "',
        'noon',
        '25:00',
        '22:70',
        '22',
        7,
        null
      ]) {
        expect(
          parseQuietHours(<String, dynamic>{
            'enabled': true,
            'start': bad,
            'end': '08:00',
          }),
          isNull,
          reason: 'start "$bad" should not produce a window',
        );
      }
    });

    test('seconds on the wire are tolerated', () {
      final window = parseQuietHours(<String, dynamic>{
        'enabled': true,
        'start': '22:00:00',
        'end': '08:30:00',
      });

      expect(window?.startMinute, 22 * 60);
      expect(window?.endMinute, 8 * 60 + 30);
    });
  });
}
