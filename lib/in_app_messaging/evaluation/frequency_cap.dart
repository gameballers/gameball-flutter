/// Minimum interval between **any** two message displays.
///
/// Global, not per-campaign — which is why [CapState] carries a single
/// [CapState.lastDisplayAt]. Matches Braze's default `triggerMinimumTimeInterval`.
const Duration minimumIntervalBetweenDisplays = Duration(seconds: 30);

/// An immutable view of display history, for the pure evaluator to read.
class CapState {
  const CapState({required this.shownCampaignIds, required this.lastDisplayAt});

  /// Campaigns already displayed and therefore not eligible again.
  final Set<String> shownCampaignIds;

  /// When the most recent message was displayed, or null if none has been.
  final DateTime? lastDisplayAt;
}

/// Tracks what has been shown, so the evaluator can enforce caps.
///
/// [load] runs once at start and the implementation keeps its state in memory
/// thereafter, so [snapshot] stays synchronous. That is what lets the evaluator
/// remain a pure function once a persisted implementation is added.
abstract class FrequencyCap {
  Future<void> load();

  CapState snapshot();

  /// Records that [campaignId] was displayed at [at].
  ///
  /// Called at impression, never at selection — a deferred or suppressed
  /// message must not burn its slot.
  void recordDisplay(String campaignId, DateTime at);

  void reset();
}

/// Caps that live for one app run. Nothing survives a restart.
class InMemoryFrequencyCap implements FrequencyCap {
  final Set<String> _shown = <String>{};
  DateTime? _lastDisplayAt;

  @override
  Future<void> load() async {
    // Nothing to load; state begins empty for every run.
  }

  @override
  CapState snapshot() => CapState(
        shownCampaignIds: Set<String>.unmodifiable(_shown),
        lastDisplayAt: _lastDisplayAt,
      );

  @override
  void recordDisplay(String campaignId, DateTime at) {
    _shown.add(campaignId);
    _lastDisplayAt = at;
  }

  @override
  void reset() {
    _shown.clear();
    _lastDisplayAt = null;
  }
}
