import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/analytics/batched_message_analytics.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Posts a batch of in-app message analytics events.
///
/// Unlike [sendLogsRequest], this reports an outcome: the caller keeps a
/// persistent outbox and has to know whether a batch can be dropped, should be
/// retried, or is poison.
///
/// The status-code policy is the standard one, and it matters because the outbox
/// is FIFO — a batch retried forever blocks everything logged after it:
///
/// * **2xx** — accepted.
/// * **408, 429, 5xx, and any thrown error** — transient. Retry.
/// * **any other 4xx** — the request itself is wrong (malformed body, bad API
///   key, rejected session token). Retrying an unchanged request cannot fix that,
///   so the batch is dropped and logged.
///
/// Arguments:
///   - `body`: `{ "audience": {...}, "events": [...] }`.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token for secure endpoints.
Future<GameballAnalyticsSendResult> sendMessageEventsRequest(
  Map<String, dynamic> body,
  String apiKey,
  String lang, {
  String? customApiPrefix,
  String? sessionToken,
}) async {
  try {
    final apiBaseUrl = customApiPrefix ?? baseUrl;
    final url = '$apiBaseUrl$inAppMessageEventsPath';
    final response = await http.post(
      Uri.parse(url),
      headers: getRequestHeaders(apiKey, lang, sessionToken: sessionToken),
      body: jsonEncode(body),
    );

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return GameballAnalyticsSendResult.accepted;
    }
    if (status == 408 || status == 429 || status >= 500) {
      return GameballAnalyticsSendResult.retry;
    }
    return GameballAnalyticsSendResult.discard;
  } catch (_) {
    // No network, DNS failure, timeout — all worth retrying.
    return GameballAnalyticsSendResult.retry;
  }
}
