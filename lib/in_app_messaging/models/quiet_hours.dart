import '../iam_log.dart';

/// A daily window during which no message may display.
///
/// Global rather than per-campaign: the backend sends it once at the root of the
/// sync response, beside `cooldownSeconds`, and no campaign object carries one.
/// Both are marketing-pressure controls that apply to everything.
///
/// Held as minutes from midnight rather than as a `DateTime` because the window
/// has no date — it recurs every day, and comparing an instant against it means
/// asking what o'clock that instant is, not which day it falls on.
///
/// **The times are UTC.** Confirmed with the backend 2026-08-24. The wire format
/// is a bare `HH:mm` that says so nowhere, and the earlier reading here was that
/// they were the customer's local wall clock — which is the more usual meaning
/// of "quiet hours" and is wrong for this contract. The difference is not
/// cosmetic: at UTC+3 the two readings disagree for six hours of every day.
class GameballQuietHours {
  const GameballQuietHours({
    required this.startMinute,
    required this.endMinute,
  });

  /// Minutes from UTC midnight at which the window opens. Inclusive.
  final int startMinute;

  /// Minutes from UTC midnight at which it closes. Exclusive.
  final int endMinute;

  /// Whether [instant] falls inside the window, compared in **UTC**.
  ///
  /// [instant] is converted rather than assumed, so a local `DateTime` and the
  /// UTC one for the same moment give the same verdict — the answer depends on
  /// the instant, never on how the caller happened to express it. That also
  /// makes the result independent of where the device is, which is the whole
  /// point of a UTC window.
  ///
  /// Half-open: the start minute is inside the window and the end minute is
  /// not, so a window ending at 08:00 and one beginning there do not overlap.
  bool contains(DateTime instant) {
    final utc = instant.toUtc();
    final minute = utc.hour * 60 + utc.minute;

    // A window that wraps past UTC midnight — 22:00 to 08:00 — is two ranges,
    // not one, and the naive `start <= m && m < end` is false for every minute
    // of it. This is the case the backend actually sends.
    if (startMinute > endMinute) {
      return minute >= startMinute || minute < endMinute;
    }
    return minute >= startMinute && minute < endMinute;
  }
}

/// Reads the `quietHours` block, or null when there is no usable window.
///
/// Null covers absent, disabled, malformed and zero-length alike, because the
/// caller does the same thing with all four: nothing. Every one of them is
/// logged, since a window that silently fails to apply and a window that
/// silently applies are both expensive to discover from the outside.
GameballQuietHours? parseQuietHours(Object? json) {
  if (json == null) return null;
  if (json is! Map<String, dynamic>) {
    iamLog('quiet hours ignored: not an object');
    return null;
  }

  final enabled = json['enabled'];
  if (enabled is bool && !enabled) return null;

  final start = _minuteOfDay(json['start']);
  final end = _minuteOfDay(json['end']);
  if (start == null || end == null) {
    iamLog('quiet hours ignored: could not read "${json['start']}" to '
        '"${json['end']}" as a window');
    return null;
  }

  if (start == end) {
    // Zero length or a full twenty-four hours, and nothing on the wire says
    // which. Refusing to guess beats silencing every campaign on the account
    // because someone set the same time twice.
    iamLog('quiet hours ignored: start and end are both "${json['start']}", '
        'which could mean no window or an endless one');
    return null;
  }

  return GameballQuietHours(startMinute: start, endMinute: end);
}

/// `HH:mm`, or `HH:mm:ss` — minutes from midnight, or null if unreadable.
int? _minuteOfDay(Object? value) {
  if (value is! String) return null;

  final parts = value.split(':');
  if (parts.length < 2 || parts.length > 3) return null;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

  return hour * 60 + minute;
}
