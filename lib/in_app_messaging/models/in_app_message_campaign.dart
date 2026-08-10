import 'in_app_message.dart';
import 'message_trigger.dart';

/// A message plus the conditions under which it displays.
///
/// Internal: hosts never see campaigns, only the [GameballInAppMessage] inside.
class InAppMessageCampaign {
  const InAppMessageCampaign({
    required this.id,
    required this.trigger,
    required this.priority,
    required this.message,
    this.analyticsToken,
  });

  final String id;
  final GameballMessageTrigger trigger;

  /// Higher wins when several campaigns match one trigger.
  final int priority;

  final GameballInAppMessage message;

  /// Opaque token the backend minted for this campaign, echoed back verbatim on
  /// every analytics event.
  ///
  /// Braze's `trigger_id`, and the single most useful thing to copy from their
  /// model. The SDK never parses or interprets it — which is what lets the backend
  /// encode whatever it needs (campaign, variant, dispatch, user) without a wire
  /// change here. Without it, an impression can name a campaign but not the A/B
  /// arm that produced it, so variant reporting is impossible no matter what the
  /// backend does.
  ///
  /// Null when the campaign carried none; [id] then carries the correlation.
  final String? analyticsToken;
}
