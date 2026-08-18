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
}

/// Wraps a fetcher in a short per-customer cache.
class CachingVariableSource implements VariableSource {
  CachingVariableSource({
    required Future<Map<String, String>> Function(String customerId) fetcher,
    this.ttl = defaultVariableCacheTtl,
    DateTime Function()? clock,
  })  : _fetch = fetcher,
        _clock = clock ?? DateTime.now;

  final Future<Map<String, String>> Function(String customerId) _fetch;
  final DateTime Function() _clock;
  final Duration ttl;

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
      // Not cached: a failure is a moment, not a value. Caching it would extend
      // one dead request into a minute of stale text.
      iamLog('variables unavailable ($error)');
      return const <String, String>{};
    }

    _customerId = customerId;
    _values = values;
    _fetchedAt = _clock();
    return values;
  }

  /// Forgets everything. Called when the customer changes and on stop.
  @override
  void clear() {
    _customerId = null;
    _values = null;
    _fetchedAt = null;
  }
}
