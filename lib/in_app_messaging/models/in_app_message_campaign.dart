import 'in_app_message.dart';
import 'message_trigger.dart';

/// A message plus the conditions under which it displays.
///
/// Internal: hosts never see campaigns, only the [GameballInAppMessage] inside.
class InAppMessageCampaign {
  const InAppMessageCampaign({
    required this.campaignId,
    required this.trigger,
    required this.priority,
    required this.message,
    this.variationId,
    this.dispatchId,
    this.name,
    this.expiresAt,
    this.isTest = false,
    this.repeatable = false,
    this.minInterval,
  });

  /// The backend's campaign key.
  ///
  /// Everything customer-scoped keys on this and not on [variationId]:
  /// repeatability is a property of the campaign, while the variation is which
  /// arm *this user* was assigned.
  final int campaignId;

  /// Which A/B arm this user got, when the campaign has more than one.
  final int? variationId;

  /// Opaque identifier for this exact send, echoed verbatim on every telemetry
  /// event.
  ///
  /// The SDK never parses or interprets it — which is what lets the backend
  /// encode whatever it needs (campaign, variation, dispatch, user) without a
  /// wire change here. Null when the campaign carried none; [campaignId] then
  /// carries the correlation, which is enough for counting but not for
  /// attributing a variation.
  final String? dispatchId;

  /// The marketer's name for this campaign. Diagnostic only.
  ///
  /// Worth carrying because every log line, the debug screen and the status chip
  /// otherwise show an opaque number.
  final String? name;

  final GameballMessageTrigger trigger;

  /// Higher wins when several campaigns match one trigger occurrence.
  final int priority;

  final GameballInAppMessage message;

  /// Never display at or after this moment. Null means no expiry.
  ///
  /// Enforced on the device, not just at fetch: campaigns are cached for the
  /// session and across launches, so a campaign fetched at 23:58 would otherwise
  /// keep firing all night.
  final DateTime? expiresAt;

  /// True when this was delivered as a dashboard test send.
  ///
  /// Displays normally and reports **no** telemetry, so a marketer's testing
  /// never appears in campaign statistics.
  final bool isTest;

  /// Whether the campaign may display more than once for this user.
  ///
  /// False — the default — means once ever, enforced locally and persisted, so a
  /// restart cannot resurrect it.
  final bool repeatable;

  /// When [repeatable], the minimum gap since *this* campaign's last display.
  ///
  /// Null or zero means every matching occurrence may display. Distinct from the
  /// global cooldown, which applies between any two messages from any campaign.
  final Duration? minInterval;

  /// Whether this campaign may display at [now].
  bool hasExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !now.isBefore(expiry);
  }

  /// What to call this campaign in a log line.
  String get label => name == null ? '$campaignId' : '$campaignId ($name)';
}
