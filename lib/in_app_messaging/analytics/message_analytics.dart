import '../iam_log.dart';
import '../models/in_app_message.dart';

/// Where impression and click events go.
///
/// Called only from the display path inside the SDK. Hosts have no way to log
/// these, by design — Braze exposes logging methods to app code, which makes
/// double-counting easy when the SDK is already logging the same events.
abstract class MessageAnalytics {
  void logImpression(GameballInAppMessage message, {required String campaignId});

  /// A click on the message surface itself, with no button involved.
  ///
  /// Separate from [logButtonClick] so the two are distinguishable downstream —
  /// Braze models the same distinction as one call with a null button id.
  void logClick(GameballInAppMessage message, {required String campaignId});

  void logButtonClick(
    GameballInAppMessage message, {
    required String campaignId,
    required int buttonId,
  });
}

/// Writes analytics to the local diagnostic log.
///
/// The MVP has no impression/click endpoint; this makes the events observable
/// now and is replaced by an HTTP implementation behind the same interface.
class LoggingMessageAnalytics implements MessageAnalytics {
  @override
  void logImpression(GameballInAppMessage message, {required String campaignId}) {
    iamLog('impression: campaign="$campaignId" message="${message.id}"'
        '${message.isTestSend ? ' (test send)' : ''}');
  }

  @override
  void logClick(GameballInAppMessage message, {required String campaignId}) {
    iamLog('click: campaign="$campaignId" message="${message.id}" (message body)');
  }

  @override
  void logButtonClick(
    GameballInAppMessage message, {
    required String campaignId,
    required int buttonId,
  }) {
    iamLog('click: campaign="$campaignId" message="${message.id}" button=$buttonId');
  }
}
