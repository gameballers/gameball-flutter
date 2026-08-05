import '../models/gameball_audience.dart';
import '../models/in_app_message_campaign.dart';

/// Where campaigns come from.
///
/// Internal: not exported to hosts. The MVP ships `StubMessageSource`; an HTTP
/// implementation replaces only the transport, reusing `parseCampaignsJson`.
abstract class GameballMessageSource {
  /// Fetches every campaign currently eligible for [audience].
  ///
  /// Implementations may throw; the caller treats a failure as "no campaigns".
  Future<List<InAppMessageCampaign>> fetch(GameballAudience audience);
}
