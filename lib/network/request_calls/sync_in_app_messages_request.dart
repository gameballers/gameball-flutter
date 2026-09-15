import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/iam_log.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Fetches eligible in-app messages from `integrations/inapp-messages/sync`.
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
///   - `customerId`: the external customer id, sent in the body.
///   - `platform`: 1 for iOS, 2 for Android. Anything else returns no campaigns.
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
    final url = Uri.parse('$apiBaseUrl$inAppMessagesSyncPath');

    // An unrecognised platform is not an error to the backend: it answers 200
    // with an empty message list. getDevicePlatformCode() returns 0 on macOS,
    // web and every desktop target, so without this line the only symptom is a
    // feature that does nothing, on exactly the platforms a developer is most
    // likely to be testing on.
    if (platform != 1 && platform != 2) {
      iamLog('sync: platform is $platform, which the backend does not target '
          '(1 = iOS, 2 = Android). Expect an empty campaign list');
    }

    final response = await http.post(
      url,
      headers: getRequestHeaders(apiKey, locale, sessionToken: sessionToken),
      body: jsonEncode(<String, dynamic>{
        'customerId': customerId,
        'platform': platform,
        'locale': locale,
        'appVersion': appVersion,
        'sdkVersion': sdkVersion,
      }),
    );

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      // Two very different problems share this status. A 404 carrying an
      // ErrorResponse means the backend does not know this customer; a 404 with
      // no body at all is what an undeployed path returns, and is
      // indistinguishable from a wrong base URL unless we say so.
      if (status == 404) {
        iamLog(response.body.trim().isEmpty
            ? 'sync: HTTP 404 with no body — inapp-messages is not deployed on '
                '${url.origin}'
            : 'sync: HTTP 404 — the backend does not know customer "$customerId"');
      } else {
        iamLog('sync: HTTP $status');
      }
      return null;
    }

    return response.body;
  } catch (error) {
    iamLog('sync request failed ($error)');
    return null;
  }
}
