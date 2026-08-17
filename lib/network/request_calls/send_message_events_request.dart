import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/analytics/batched_message_analytics.dart';
import '../../in_app_messaging/iam_log.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Posts a batch of in-app message telemetry to `integrations/inapp-messages/events`.
///
/// Unlike [sendLogsRequest], this reports an outcome: the caller keeps a
/// persistent outbox and has to know whether a batch can be dropped, should be
/// retried, or is poison. The distinction matters because the outbox is FIFO — a
/// batch retried forever blocks everything logged after it.
///
/// V4 reports failure with the status code, not inside a 200, so the whole
/// envelope reader this function used to carry is gone.
///
/// Arguments:
///   - `events`: at most [maxEventsPerRequest], oldest first.
///   - `customerId`: the external customer id, sent in the body.
///   - `platform`: 1 for iOS, 2 for Android.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token, sent when the integration has one.
Future<GameballAnalyticsSendResult> sendMessageEventsRequest(
  List<Map<String, dynamic>> events, {
  required String customerId,
  required int platform,
  required String apiKey,
  required String lang,
  String? customApiPrefix,
  String? sessionToken,
}) async {
  try {
    final apiBaseUrl = customApiPrefix ?? baseUrl;
    final url = Uri.parse('$apiBaseUrl$inAppMessagesEventsPath');

    final response = await http.post(
      url,
      headers: getRequestHeaders(apiKey, lang, sessionToken: sessionToken),
      body: jsonEncode(<String, dynamic>{
        'customerId': customerId,
        'platform': platform,
        'events': events,
      }),
    );

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      _logRejected(response.body, events.length);
      return GameballAnalyticsSendResult.accepted;
    }

    // 408 and 429 are the two 4xx worth retrying; 5xx includes the documented
    // 503. Everything else means the request itself is wrong, and an unchanged
    // retry cannot fix it.
    if (status == 408 || status == 429 || status >= 500) {
      iamLog('analytics: HTTP $status — will retry');
      return GameballAnalyticsSendResult.retry;
    }

    // 422 arrives for two unrelated reasons — a deactivated customer, and a
    // batch in which every event was malformed. Verified against alpha. Both are
    // permanent for this batch, so they share an outcome; do not read this as
    // "the customer is deactivated".
    iamLog('analytics: HTTP $status — dropping ${events.length} event(s), a '
        'retry cannot help');
    return GameballAnalyticsSendResult.discard;
  } catch (_) {
    // No network, DNS failure, timeout — all worth retrying.
    return GameballAnalyticsSendResult.retry;
  }
}

/// Logs individually-rejected events. Diagnostics only: the batch landed.
void _logRejected(String body, int sentCount) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    // The counts are diagnostics and the status already said the batch was
    // taken, so an unreadable body changes nothing.
    return;
  }
  if (decoded is! Map<String, dynamic>) return;

  final rejected = decoded['rejected'];
  if (rejected is int && rejected > 0) {
    // "Will never succeed", and the response does not say which. Since the
    // backend accepted the rest, dropping the whole batch is the only correct
    // reading.
    iamLog('analytics: backend rejected $rejected of $sentCount event(s) as '
        'malformed; they will not be retried');
  }
}
