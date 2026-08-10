import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../iam_log.dart';

/// An immutable view of display history, for the pure evaluator to read.
class CapState {
  const CapState({
    this.lastDisplayByCampaign = const <int, DateTime>{},
    this.lastDisplayAt,
  });

  /// When each campaign was last displayed.
  ///
  /// Per-campaign rather than a bare set of ids, because the backend expresses
  /// three different rules against it: a non-repeatable campaign may never show
  /// again, a repeatable one may show after its own `minIntervalSeconds`, and the
  /// global cooldown applies between any two messages from any campaign. A set
  /// can only answer the first.
  final Map<int, DateTime> lastDisplayByCampaign;

  /// When the most recent message from any campaign was displayed.
  final DateTime? lastDisplayAt;

  /// Campaigns displayed at least once.
  Iterable<int> get shownCampaignIds => lastDisplayByCampaign.keys;
}

/// Tracks what has been shown, so the evaluator can enforce repeat rules.
///
/// [load] runs at start and the implementation keeps its state in memory
/// thereafter, so [snapshot] stays synchronous. That is what lets the evaluator
/// remain a pure function while the history itself is persisted.
abstract class FrequencyCap {
  /// Restores history for [customerId], discarding anything belonging to someone
  /// else.
  Future<void> load(String customerId);

  CapState snapshot();

  /// Records that [campaignId] was displayed at [at].
  ///
  /// Called at impression, never at selection — a deferred or suppressed message
  /// must not burn its slot.
  void recordDisplay(int campaignId, DateTime at);

}

/// History that lives for one app run. Nothing survives a restart.
///
/// Kept for tests and for a host that wants no local storage. [StoredFrequencyCap]
/// is what ships — with this one, a campaign the backend marked "once ever" comes
/// back on every cold start.
class InMemoryFrequencyCap implements FrequencyCap {
  final Map<int, DateTime> _history = <int, DateTime>{};
  DateTime? _lastDisplayAt;

  @override
  Future<void> load(String customerId) async {
    // Nothing is persisted, so there is nothing to restore.
  }

  @override
  CapState snapshot() => CapState(
        lastDisplayByCampaign: Map<int, DateTime>.unmodifiable(_history),
        lastDisplayAt: _lastDisplayAt,
      );

  @override
  void recordDisplay(int campaignId, DateTime at) {
    _history[campaignId] = at;
    _lastDisplayAt = at;
  }
}

/// History that survives restarts, scoped to one customer.
///
/// Required rather than nice: the backend's contract says a non-repeatable
/// campaign, once displayed, must never display again — *"locally too, don't wait
/// for the server"*. An in-memory history satisfies that only until the app is
/// killed, which is to say not at all.
///
/// Scoped by customer and **discarded on mismatch**. That is the guard that makes
/// account switching safe: showing one user's once-ever campaign to another is a
/// bug, but attributing their display history to each other is a worse one.
class StoredFrequencyCap implements FrequencyCap {
  StoredFrequencyCap({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  static const String _key = 'gameball_iam_display_history';

  final Map<int, DateTime> _history = <int, DateTime>{};
  DateTime? _lastDisplayAt;
  String? _customerId;

  @override
  Future<void> load(String customerId) async {
    _history.clear();
    _lastDisplayAt = null;
    _customerId = customerId;

    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_key);
        return;
      }

      if (decoded['customerId'] != customerId) {
        iamLog('display history belonged to another customer; discarded');
        await prefs.remove(_key);
        return;
      }

      final campaigns = decoded['campaigns'];
      if (campaigns is! Map) return;
      campaigns.forEach((key, value) {
        final id = int.tryParse('$key');
        final at = value is String ? DateTime.tryParse(value) : null;
        if (id == null || at == null) return;
        final utc = at.toUtc();
        _history[id] = utc;
        if (_lastDisplayAt == null || utc.isAfter(_lastDisplayAt!)) {
          _lastDisplayAt = utc;
        }
      });
      iamLog('restored display history for ${_history.length} campaign(s)');
    } catch (error) {
      // Corrupt history must not stop messaging from starting. Losing it shows a
      // message twice; throwing here shows none at all.
      iamLog('could not restore display history ($error)');
    }
  }

  @override
  CapState snapshot() => CapState(
        lastDisplayByCampaign: Map<int, DateTime>.unmodifiable(_history),
        lastDisplayAt: _lastDisplayAt,
      );

  @override
  void recordDisplay(int campaignId, DateTime at) {
    final utc = at.toUtc();
    _history[campaignId] = utc;
    _lastDisplayAt = utc;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    final customerId = _customerId;
    if (customerId == null) return;
    try {
      final prefs = await _preferences();
      if (_history.isEmpty) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(
        _key,
        jsonEncode(<String, dynamic>{
          'customerId': customerId,
          'campaigns': <String, String>{
            for (final entry in _history.entries)
              '${entry.key}': entry.value.toIso8601String(),
          },
        }),
      );
    } catch (error) {
      iamLog('could not persist display history ($error)');
    }
  }
}
