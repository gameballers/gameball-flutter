import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../iam_log.dart';
import 'message_analytics.dart';
import 'message_event.dart';

/// How long a non-empty outbox waits before being sent.
///
/// The backend's stated cadence. Long enough that an impression and the click
/// that follows it usually travel together; short enough that a marketer watching
/// a test send does not think it failed.
const Duration defaultAnalyticsFlushInterval = Duration(seconds: 30);

/// Outbox size that triggers a send without waiting for the timer.
const int defaultAnalyticsBatchSize = 10;

/// Most events the backend accepts in one request.
///
/// Exceeding it is a documented rejection, so a larger outbox is sent in chunks
/// rather than in one oversized request that would be refused wholesale.
const int maxEventsPerRequest = 50;

/// Hard ceiling on the outbox.
///
/// Reached only when the network has been unavailable for a long time. Dropping
/// the oldest events is better than growing without bound, and it is logged.
const int maxBufferedAnalyticsEvents = 500;

/// What to do with a batch after attempting to send it.
enum GameballAnalyticsSendResult {
  /// The backend took it. Drop it.
  accepted,

  /// Transient — no network, a timeout, a 5xx, or throttling. Keep and retry.
  retry,

  /// The backend refused it and retrying cannot help: a malformed batch, a bad
  /// API key, a rejected session token.
  ///
  /// Distinct from [retry] because a poison batch retried forever sits at the
  /// front of the outbox and blocks every event logged after it, so one bad
  /// payload would take all analytics down until the ceiling rotated it out.
  /// Dropping it loses that batch and nothing else, and it is logged loudly.
  discard,
}

/// Sends a batch and reports what should happen to it.
typedef GameballAnalyticsSender = Future<GameballAnalyticsSendResult> Function(
  List<Map<String, dynamic>> events,
);

/// Buffers events, batches them, and survives the process dying.
///
/// Three properties matter, and none of them are optional for a metric anybody
/// makes decisions on:
///
/// * **Never blocks the caller.** [log] is synchronous and returns immediately;
///   an impression must not wait on a network round trip while a modal animates.
/// * **Batched.** One request per burst rather than per event, which is what
///   Braze does and what keeps this affordable under their kind of rate limiting.
/// * **Persistent.** The outbox is mirrored to disk after every change, so an
///   impression logged one second before the user force-quits still arrives. An
///   impression that is recorded and then lost is worse than one never recorded:
///   it silently understates the only number the feature is judged on.
class BatchedMessageAnalytics implements MessageAnalytics {
  BatchedMessageAnalytics({
    required this.send,
    this.flushInterval = defaultAnalyticsFlushInterval,
    this.batchSize = defaultAnalyticsBatchSize,
    this.maxBuffered = maxBufferedAnalyticsEvents,
    this.maxPerRequest = maxEventsPerRequest,
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final GameballAnalyticsSender send;
  final Duration flushInterval;
  final int batchSize;
  final int maxBuffered;
  final int maxPerRequest;

  final Future<SharedPreferences> Function() _preferences;

  static const String _outboxKey = 'gameball_iam_analytics_outbox';

  /// Serialised events, oldest first. Held as JSON rather than as
  /// [GameballMessageEvent] so persisting is one `jsonEncode` and restoring needs
  /// no parser that could reject its own past output after a field is added.
  final List<Map<String, dynamic>> _outbox = <Map<String, dynamic>>[];

  Timer? _timer;
  bool _sending = false;

  /// Whether scheduling is allowed.
  ///
  /// [dispose] clears it and [load] restores it, mirroring the service's own
  /// stop/start. Without this, a send that fails after logout re-arms in
  /// `flush`'s `finally` and the module never goes quiet.
  bool _active = true;

  /// Visible for tests.
  int get bufferedCount => _outbox.length;

  /// Visible for tests.
  bool get hasScheduledFlush => _timer != null;

  @override
  Future<void> load() async {
    _active = true;
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_outboxKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        iamLog('analytics: stored outbox is not a list; discarding it');
        await prefs.remove(_outboxKey);
        return;
      }
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) _outbox.add(entry);
      }
      if (_outbox.isNotEmpty) {
        iamLog('analytics: restored ${_outbox.length} unsent event(s)');
        _arm();
      }
    } catch (error) {
      // A corrupt outbox must not stop messaging from starting.
      iamLog('analytics: could not restore the outbox ($error)');
    }
  }

  @override
  void log(GameballMessageEvent event) {
    _outbox.add(event.toJson());

    final button = event.buttonId == null ? '' : ' button=${event.buttonId}';
    iamLog('${event.type.wireName}: campaign=${event.campaignId}$button');

    if (_outbox.length > maxBuffered) {
      final excess = _outbox.length - maxBuffered;
      _outbox.removeRange(0, excess);
      iamLog('analytics: outbox at capacity; dropped $excess oldest event(s)');
    }

    unawaited(_persist());

    if (_outbox.length >= batchSize) {
      unawaited(flush());
    } else {
      _arm();
    }
  }

  @override
  Future<void> flush() async {
    // A send already in flight will re-arm on completion, so dropping this call
    // loses nothing. Re-entering would double-send the same batch.
    if (_sending || _outbox.isEmpty) return;

    _sending = true;
    _timer?.cancel();
    _timer = null;

    // Snapshot by value, capped at what the backend accepts: `log` may append
    // while the request is in flight, and those events belong to the next batch.
    final batch = List<Map<String, dynamic>>.of(
      _outbox.take(maxPerRequest),
    );

    var drained = false;
    try {
      final result = await send(batch);
      switch (result) {
        case GameballAnalyticsSendResult.accepted:
          drained = true;
          // Removing from the front by count is safe precisely because anything
          // added during the await went to the back.
          _outbox.removeRange(0, batch.length);
          await _persist();
          iamLog('analytics: sent ${batch.length} event(s)');
        case GameballAnalyticsSendResult.discard:
          drained = true;
          _outbox.removeRange(0, batch.length);
          await _persist();
          iamLog('analytics: backend refused ${batch.length} event(s) and a '
              'retry cannot help; dropped so later events are not blocked');
        case GameballAnalyticsSendResult.retry:
          iamLog('analytics: send failed; '
              '${_outbox.length} event(s) still queued');
      }
    } catch (error) {
      iamLog('analytics: send failed ($error); '
          '${_outbox.length} event(s) still queued');
    } finally {
      _sending = false;
      if (_outbox.isNotEmpty) {
        if (drained) {
          // A backlog is chunked, so keep going rather than waiting a full
          // interval per 50 events — draining 500 would otherwise take minutes.
          unawaited(flush());
        } else {
          _arm();
        }
      }
    }
  }

  @override
  void dispose() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void _arm() {
    if (!_active) return;
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> _persist() async {
    try {
      final prefs = await _preferences();
      if (_outbox.isEmpty) {
        await prefs.remove(_outboxKey);
      } else {
        await prefs.setString(_outboxKey, jsonEncode(_outbox));
      }
    } catch (error) {
      // Losing persistence degrades durability; it must not break logging.
      iamLog('analytics: could not persist the outbox ($error)');
    }
  }
}
