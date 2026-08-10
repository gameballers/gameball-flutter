import '../models/gameball_audience.dart';
import '../models/in_app_message_campaign.dart';

/// Fallback gap between any two displayed messages.
///
/// Used when a sync response omits `cooldownSeconds`. The backend currently sends
/// 30, matching Braze's own default, and the value is server-driven precisely so
/// it can be tuned without a client release.
const Duration defaultDisplayCooldown = Duration(seconds: 30);

/// One sync response: the eligible campaigns plus the settings that came with
/// them.
///
/// A record rather than a bare list because the cooldown is delivered alongside
/// the campaigns and applies to all of them — returning only the list would leave
/// the caller guessing at a value the server is entitled to change.
class GameballSyncResult {
  const GameballSyncResult({
    required this.campaigns,
    this.cooldown = defaultDisplayCooldown,
  });

  const GameballSyncResult.empty()
      : campaigns = const <InAppMessageCampaign>[],
        cooldown = defaultDisplayCooldown;

  final List<InAppMessageCampaign> campaigns;

  /// Minimum gap between any two displays, from any campaign.
  final Duration cooldown;
}

/// Where campaigns come from.
///
/// Internal: not exported to hosts. `StubMessageSource` is the offline fixture
/// implementation; an HTTP one replaces only the transport, reusing
/// `parseSyncResponse`.
abstract class GameballMessageSource {
  /// Syncs every campaign currently eligible for [audience].
  ///
  /// Implementations may throw; the caller treats a failure as "keep whatever was
  /// cached", never as "no campaigns".
  Future<GameballSyncResult> fetch(GameballAudience audience);
}
