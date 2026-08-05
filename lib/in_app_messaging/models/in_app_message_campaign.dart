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
  });

  final String id;
  final GameballMessageTrigger trigger;

  /// Higher wins when several campaigns match one trigger.
  final int priority;

  final GameballInAppMessage message;
}
