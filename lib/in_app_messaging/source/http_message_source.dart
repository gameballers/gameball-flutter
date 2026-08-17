import '../models/gameball_audience.dart';
import 'message_parser.dart';
import 'message_source.dart';

/// Performs the sync request. Returns the raw response body, or null on failure.
///
/// A function rather than a class so the source owns no credentials: everything
/// the request needs — api key, prefix, session token, locale — lives on
/// `GameballApp` and is read at call time, which is what keeps a later
/// `initializeCustomer` for a different customer from being sent under the old
/// identity.
typedef GameballSyncSender = Future<String?> Function(String customerId);

/// Fetches campaigns from `integrations/inapp-messages/sync`.
///
/// Thin on purpose: it turns an audience into a customer id, delegates the request,
/// and hands the body to the parser. Every rule about what a campaign means lives
/// in [parseSyncResponse], which is tested against a payload captured from the live
/// endpoint.
class HttpMessageSource implements GameballMessageSource {
  HttpMessageSource(this.send);

  final GameballSyncSender send;

  @override
  Future<GameballSyncResult> fetch(GameballAudience audience) async {
    // Switched rather than type-tested: [GameballAudience] is sealed, so adding a
    // device-scoped variant makes this fail to compile instead of silently
    // syncing under a customer-shaped identity it does not have.
    final customerId = switch (audience) {
      CustomerAudience(customerId: final id) => id,
    };

    final body = await send(customerId);
    if (body == null) {
      // Thrown rather than returned empty, because the caller distinguishes the
      // two: a failure keeps the previous cache, an empty success replaces it.
      throw const GameballSyncFailure();
    }

    return parseSyncResponse(body);
  }
}

/// Signals that a sync could not be performed, as opposed to returning nothing.
class GameballSyncFailure implements Exception {
  const GameballSyncFailure();

  @override
  String toString() => 'the sync request did not return a usable response';
}
