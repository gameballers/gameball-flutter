import 'package:platform_info/platform_info.dart';

import '../../utils/gameball_utils.dart';
import 'constants.dart';

/// Creates a map of request headers for API calls.
///
/// Includes essential headers like content type, API key, and user-agent information.
///
/// Arguments:
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `sessionToken`: Optional Session Token for secure endpoints.
///
/// Returns:
///   A map of request headers.
Map<String, String> getRequestHeaders(String apiKey, String lang, {String? sessionToken}) {
  final headers = <String, String>{
    'Content-Type': 'application/json; charset=UTF-8',
    'ApiKey': apiKey,
    'Lang': lang,
    'x-gb-agent':
        'Flutter/${getSdkVersion()}/${Platform.I.operatingSystem}/${Platform.I.version}'
  };

  // Add Session Token header if present
  if (sessionToken != null && sessionToken.isNotEmpty) {
    headers['X-GB-TOKEN'] = sessionToken;
  }

  return headers;
}

/// Determines the integrations URL based on Session Token presence.
///
/// Returns v4.1 URL if sessionToken is provided, otherwise v4.0.
///
/// Arguments:
///   - `sessionToken`: Optional Session Token.
///
/// Returns:
///   The appropriate integrations URL path.
String getIntegrationsUrl(String? sessionToken) {
  return (sessionToken != null && sessionToken.isNotEmpty)
      ? integrationsUrlV4_1
      : integrationsUrlV4_0;
}
