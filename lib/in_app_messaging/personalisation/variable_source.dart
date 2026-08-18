import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../iam_log.dart';

/// How long a fetched variable map stays usable.
///
/// Several messages can display in quick succession — a session-start message
/// dismissed, then an event-triggered one — and refetching for each would put
/// avoidable latency on the display path for values that cannot have moved.
const Duration defaultVariableCacheTtl = Duration(seconds: 60);

/// Current personalisation values for a customer.
///
/// Internal: not exported to hosts. A seam like the source, presenter, frequency
/// cap, analytics and prefetcher, so the service can be tested without a network.
abstract interface class VariableSource {
  /// Current values for [customerId]. **Empty when unavailable** — never throws,
  /// because the caller's only response to a failure is to use the text it has.
  Future<Map<String, String>> fetch(String customerId);

  /// Forgets anything held for a previous customer.
  ///
  /// On the interface rather than only on the caching implementation, so the
  /// service can say what it means — "this customer is gone" — without testing
  /// which implementation it was given. A source that holds nothing does
  /// nothing, which is a correct answer rather than an empty one.
  void clear();

  /// Names the tokens the currently held campaigns actually use.
  ///
  /// Only these are written to the device. The endpoint returns the customer's
  /// name and email alongside their points, and a campaign that never mentions
  /// an email gives the SDK no reason to keep one at rest.
  void retainOnly(Set<String> tokenNames);
}

/// Wraps a fetcher in a short in-memory cache, backed by the device.
///
/// Two layers, and they answer different questions. The memory cache answers
/// "several messages are displaying in a burst, must each pay a round trip" —
/// no, for [ttl]. The stored copy answers "the fetch just failed, what do we
/// show" — the last values that worked, which read correctly where a raw
/// `{token}` does not.
///
/// Only the tokens named by [retainOnly] reach the device. See
/// `tokensIn` in `token_substitution.dart` for where that set comes from.
class CachingVariableSource implements VariableSource {
  CachingVariableSource({
    required Future<Map<String, String>> Function(String customerId) fetcher,
    this.ttl = defaultVariableCacheTtl,
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? preferences,
  })  : _fetch = fetcher,
        _clock = clock ?? DateTime.now,
        _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<Map<String, String>> Function(String customerId) _fetch;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _preferences;
  final Duration ttl;

  static const String _key = 'gameball_iam_variables';

  /// Tokens worth keeping at rest. Empty until the first sync names them, which
  /// means nothing is stored before we know what any campaign needs.
  Set<String> _retained = const <String>{};

  String? _customerId;
  Map<String, String>? _values;
  DateTime? _fetchedAt;

  @override
  Future<Map<String, String>> fetch(String customerId) async {
    final at = _fetchedAt;
    final cached = _values;
    // Keyed on the customer as well as the clock: personalising one customer's
    // message with another's name is the worst thing this feature can do, and a
    // cache that only checked the time would do exactly that on a fast switch.
    if (_customerId == customerId &&
        cached != null &&
        at != null &&
        _clock().difference(at) < ttl) {
      return cached;
    }

    Map<String, String> values;
    try {
      values = await _fetch(customerId);
    } catch (error) {
      // Not cached in memory: a failure is a moment, not a value, and caching it
      // would extend one dead request into a minute of stale text. But the last
      // values that *did* work are still worth having — without them the message
      // displays its raw `{tokens}`, which is worse than a slightly old number.
      iamLog('variables unavailable ($error); falling back to stored values');
      return _readStored(customerId);
    }

    _customerId = customerId;
    _values = values;
    _fetchedAt = _clock();
    unawaited(_store(customerId, values));
    return values;
  }

  /// Writes the retained subset. Fire and forget: a display must never wait on
  /// storage, and a failed write only costs the next offline session.
  ///
  /// Re-checks the customer first. Because the write is not awaited, a `clear()`
  /// — a logout, or a customer change — can be issued while it is still in
  /// flight, and without this check the write would land afterwards and put the
  /// values back on a device they had just been removed from.
  Future<void> _store(String customerId, Map<String, String> values) async {
    final keep = <String, String>{
      for (final entry in values.entries)
        if (_retained.contains(entry.key)) entry.key: entry.value,
    };

    try {
      final prefs = await _preferences();
      // Checked *after* awaiting storage, not before: a synchronous check would
      // pass while the clear that overtakes us has not been issued yet.
      if (_customerId != customerId) return;

      if (keep.isEmpty) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(
        _key,
        jsonEncode(<String, dynamic>{'customerId': customerId, 'values': keep}),
      );
    } catch (error) {
      iamLog('could not store personalisation values ($error)');
    }
  }

  Future<Map<String, String>> _readStored(String customerId) async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const <String, String>{};

      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) {
        await prefs.remove(_key);
        return const <String, String>{};
      }
      if (envelope['customerId'] != customerId) {
        // Never reused across customers. Showing one person their own name in
        // someone else's session is the worst thing this feature can do.
        iamLog('stored values belonged to another customer; discarded');
        await prefs.remove(_key);
        return const <String, String>{};
      }

      final values = envelope['values'];
      if (values is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in values.entries) '${entry.key}': '${entry.value}',
      };
    } catch (error) {
      iamLog('could not read stored personalisation values ($error)');
      return const <String, String>{};
    }
  }

  @override
  void retainOnly(Set<String> tokenNames) => _retained = tokenNames;

  /// Forgets everything, on the device as well as in memory.
  ///
  /// Called when the customer changes and on stop — so logging out does not
  /// leave a name behind.
  @override
  void clear() {
    _customerId = null;
    _values = null;
    _fetchedAt = null;
    unawaited(_forgetStored());
  }

  /// Fire and forget, so logging out never waits on storage. The window between
  /// the call and the write landing is milliseconds; a process killed inside it
  /// leaves the values on disk, where the customer check at read still stops
  /// them reaching anyone else.
  Future<void> _forgetStored() async {
    try {
      final prefs = await _preferences();
      await prefs.remove(_key);
    } catch (error) {
      iamLog('could not clear stored personalisation values ($error)');
    }
  }
}
