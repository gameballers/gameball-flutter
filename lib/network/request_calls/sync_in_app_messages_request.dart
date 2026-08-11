import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/iam_log.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Fetches eligible in-app messages from `bots/inapp/sync`.
///
/// Returns the response body **unparsed**. Two reasons: the caller stores the raw
/// payload in its cache, so parsing here then re-serialising would be wasted; and
/// it keeps every rule about what a campaign means in one tested place.
///
/// Returns null when there is nothing usable to parse. The distinction between
/// "no campaigns" and "could not ask" matters to the caller — a failure keeps the
/// previous cache, while an empty success replaces it.
///
/// Arguments:
///   - `customerId`: the external customer id, sent as `playerUniqueId`.
///   - `platform`: 1 for iOS, 2 for Android.
///   - `locale`: resolved language code, which selects the translation.
///   - `appVersion`: the host app's version, for targeting.
///   - `sdkVersion`: this package's version.
///   - `apiKey`: The API key for authentication.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token, sent when the integration has one.
Future<String?> syncInAppMessagesRequest({
  required String customerId,
  required int platform,
  required String locale,
  required String appVersion,
  required String sdkVersion,
  required String apiKey,
  String? customApiPrefix,
  String? sessionToken,
}) async {
  try {
    final apiBaseUrl = customApiPrefix ?? baseUrl;
    final url = Uri.parse('$apiBaseUrl$botsInAppSyncPath').replace(
      queryParameters: <String, String>{'playerUniqueId': customerId},
    );

    final response = await http.post(
      url,
      headers: getRequestHeaders(apiKey, locale, sessionToken: sessionToken),
      body: jsonEncode(<String, dynamic>{
        'platform': platform,
        'locale': locale,
        'appVersion': appVersion,
        'sdkVersion': sdkVersion,
      }),
    );

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      // 404 is the shape this takes before the endpoint is deployed in a given
      // environment — worth naming, because it is otherwise indistinguishable
      // from a wrong base URL.
      iamLog(status == 404
          ? 'sync: HTTP 404 — bots/inapp/sync is not available on this '
              'environment (${url.origin})'
          : 'sync: HTTP $status');
      return null;
    }

    return response.body;
  } catch (error) {
    iamLog('sync request failed ($error)');
    return null;
  }
}
