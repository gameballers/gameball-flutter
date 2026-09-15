import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/iam_log.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Fetches the customer's current personalisation values.
///
/// Returns an empty map on **any** failure. The caller's only correct response to
/// every documented error — 404, 422, 503, a timeout, no network — is to display
/// the text it already holds, so there is nothing here worth distinguishing.
///
/// Arguments:
///   - `customerId`: the external customer id, sent in the body.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token, sent when the integration has one.
Future<Map<String, String>> fetchMessageVariablesRequest({
  required String customerId,
  required String apiKey,
  required String lang,
  String? customApiPrefix,
  String? sessionToken,
}) async {
  try {
    final apiBaseUrl = customApiPrefix ?? baseUrl;
    final url = Uri.parse('$apiBaseUrl$inAppMessagesVariablesPath');

    final response = await http.post(
      url,
      headers: getRequestHeaders(apiKey, lang, sessionToken: sessionToken),
      body: jsonEncode(<String, dynamic>{'customerId': customerId}),
    );

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      iamLog('variables: HTTP $status — displaying the text already held');
      return const <String, String>{};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const <String, String>{};
    final values = decoded['variables'];
    if (values is! Map) return const <String, String>{};

    // Coerced rather than cast: the contract says the values are pre-formatted
    // strings, and a number arriving instead should personalise rather than
    // throw.
    return <String, String>{
      for (final entry in values.entries)
        if (entry.value != null) '${entry.key}': '${entry.value}',
    };
  } catch (error) {
    iamLog('variables request failed ($error)');
    return const <String, String>{};
  }
}
