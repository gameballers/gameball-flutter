import 'dart:convert';

import '../utils/constants.dart';
import '../utils/header_generator.dart';
import 'package:http/http.dart' as http;

/// Sends a batch of SDK telemetry logs to the Gameball backend (forwarded to Datadog).
///
/// Fire-and-forget: the body is sent as-is and any failure is swallowed so telemetry
/// never affects the host app.
///
/// Arguments:
///   - `body`: The full log payload (`context` + `logs`), forwarded as-is.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
Future<void> sendLogsRequest(
    Map<String, dynamic> body, String apiKey, String lang, {String? customApiPrefix}) async {
  try {
    final apiBaseUrl = customApiPrefix ?? baseUrl;
    final url = '$apiBaseUrl$mobileLogsPath';
    await http.post(
      Uri.parse(url),
      headers: getRequestHeaders(apiKey, lang),
      body: jsonEncode(body),
    );
  } catch (_) {
    // Telemetry must never affect the host app.
  }
}
