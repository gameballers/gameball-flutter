import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/analytics/batched_message_analytics.dart';
import '../../in_app_messaging/iam_log.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Posts a batch of in-app message telemetry to `bots/inapp/events`.
///
/// Unlike [sendLogsRequest], this reports an outcome: the caller keeps a
/// persistent outbox and has to know whether a batch can be dropped, should be
/// retried, or is poison. The distinction matters because the outbox is FIFO — a
/// batch retried forever blocks everything logged after it.
///
/// Two layers decide the outcome, and the second is the one that is easy to get
/// wrong: **this endpoint reports failure inside an HTTP 200.** Treating any 2xx
/// as success would silently discard events the backend explicitly refused.
///
/// Arguments:
///   - `events`: at most 50, oldest first.
///   - `customerId`: the external customer id, sent as `playerUniqueId`.
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
    final url = Uri.parse('$apiBaseUrl$botsInAppEventsPath').replace(
      queryParameters: <String, String>{'playerUniqueId': customerId},
    );

    final response = await http.post(
      url,
      headers: getRequestHeaders(apiKey, lang, sessionToken: sessionToken),
      body: jsonEncode(<String, dynamic>{
        'platform': platform,
        'events': events,
      }),
    );

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      // 408 and 429 are the two 4xx worth retrying; everything else in that range
      // means the request itself is wrong, and an unchanged retry cannot fix it.
      if (status == 408 || status == 429 || status >= 500) {
        iamLog('analytics: HTTP $status — will retry');
        return GameballAnalyticsSendResult.retry;
      }
      iamLog('analytics: HTTP $status — dropping ${events.length} event(s), a '
          'retry cannot help');
      return GameballAnalyticsSendResult.discard;
    }

    return _readEnvelope(response.body, events.length);
  } catch (_) {
    // No network, DNS failure, timeout — all worth retrying.
    return GameballAnalyticsSendResult.retry;
  }
}

/// Reads the bots envelope, which reports failure at HTTP 200.
GameballAnalyticsSendResult _readEnvelope(String body, int sentCount) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    // A 200 we cannot read is more likely a proxy or an error page than the
    // backend, so it is worth another attempt.
    iamLog('analytics: unreadable 200 response — will retry');
    return GameballAnalyticsSendResult.retry;
  }

  if (decoded is! Map<String, dynamic>) {
    return GameballAnalyticsSendResult.retry;
  }

  if (decoded['success'] == false) {
    // Every documented `success:false` case is permanent for that batch: over 50
    // events, an empty batch, or every event malformed. The first two cannot
    // happen — the outbox chunks to 50 and never flushes empty — so in practice
    // this means the backend rejected the contents, and retrying is pointless.
    // Logged loudly because a new transient case would otherwise look like data
    // loss with no explanation.
    iamLog('analytics: backend refused the batch — '
        '${decoded['errorMsg'] ?? 'no message'} '
        '(errorCode ${decoded['errorCode']}); dropping $sentCount event(s)');
    return GameballAnalyticsSendResult.discard;
  }

  final payload = decoded['response'];
  if (payload is Map<String, dynamic>) {
    final rejected = payload['rejected'];
    if (rejected is int && rejected > 0) {
      // Individually malformed events, which "will never succeed". The response
      // does not say which, so the whole batch is dropped — and since the backend
      // accepted the rest, that is the only correct reading.
      iamLog('analytics: backend rejected $rejected of $sentCount event(s) as '
          'malformed; they will not be retried');
    }
  }

  return GameballAnalyticsSendResult.accepted;
}
