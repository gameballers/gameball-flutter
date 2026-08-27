import 'dart:convert';

import '../utils/constants.dart';
import '../utils/header_generator.dart';
import 'package:http/http.dart' as http;

/// Reports a push notification tap to the Gameball API so the campaign's click
/// stats are incremented.
///
/// Arguments:
///   - `clickToken`: The opaque click token carried in the notification's data payload.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token for secure endpoints.
///
/// Returns:
///   A `Future<http.Response>` object containing the server response.
///
/// Throws:
///   An `Exception` with an error message if the request fails.
Future<http.Response> reportPushClickRequest(
    String clickToken, String apiKey, String lang, {String? customApiPrefix, String? sessionToken}) async {
  final apiBaseUrl = customApiPrefix ?? baseUrl;
  final integrationsUrl = getIntegrationsUrl(sessionToken);
  final url = '$apiBaseUrl$integrationsUrl$pushClickEndpoint';

  final response = await http.post(
    Uri.parse(url),
    headers: getRequestHeaders(apiKey, lang, sessionToken: sessionToken),
    body: jsonEncode({'clickToken': clickToken}),
  );

  if (response.statusCode >= 200 && response.statusCode <= 299) {
    return response;
  } else {
    throw Exception(
        'Failed to report push click. Status code: ${response.statusCode}');
  }
}
