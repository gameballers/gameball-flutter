import '../iam_log.dart';
import 'message_event.dart';

/// Where impression, click and dismissal events go.
///
/// Called only from the display path inside the SDK. Hosts have no way to log
/// these, by design — Braze exposes logging methods to app code, and because
/// their native layer logs the same events for any message it displayed, calling
/// them double-counts. Their own example app ships that call site behind a
/// `_automaticallyInteractIam = false` flag to avoid it. One owner, enforced by
/// the API shape, removes the hazard instead of documenting it.
abstract class MessageAnalytics {
  /// Restores anything left unsent by a previous run. Called once at start.
  Future<void> load();

  /// Records [event]. Must not throw, and must not block the caller on I/O.
  void log(GameballMessageEvent event);

  /// Sends whatever is buffered now.
  ///
  /// Called when the app leaves the foreground and when messaging stops — the two
  /// moments where the process might not get another chance.
  Future<void> flush();

  /// Stops any scheduled work, leaving buffered events for the next [load].
  ///
  /// Called from `stop()`, so a stopped module holds no timers. Retry after this
  /// point is the next [load]'s job, not a timer's — which is also what keeps a
  /// failed send from re-arming forever after logout.
  void dispose();
}

/// Writes analytics to the local diagnostic log and nowhere else.
///
/// Kept for tests and for a host that wants the module with no analytics traffic
/// at all. [BatchedMessageAnalytics] is what ships.
class LoggingMessageAnalytics implements MessageAnalytics {
  @override
  Future<void> load() async {
    // Nothing is persisted, so there is nothing to restore.
  }

  @override
  void log(GameballMessageEvent event) {
    final button = event.buttonId == null ? '' : ' button=${event.buttonId}';
    iamLog('${event.type.wireName}: campaign="${event.campaignId}" '
        'message="${event.messageId}"$button'
        '${event.isTestSend ? ' (test send)' : ''}');
  }

  @override
  Future<void> flush() async {
    // Nothing is buffered.
  }

  @override
  void dispose() {
    // No timers to cancel.
  }
}
