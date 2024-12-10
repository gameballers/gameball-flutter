import 'dart:convert';

import '../../models/requests/event.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';
import 'package:http/http.dart' as http;

/// Sends an event request to the Gameball API asynchronously.
///
/// This function constructs the request URL, sets headers, encodes the event body,
/// and sends a POST request to the API. It then checks the response status code
/// and returns the response object or throws an exception on failure.
///
/// Arguments:
///   - `requestBody`: The `Event` object representing the event data to be sent.
///   - `apiKey`: The API key for authentication.
///
/// Returns:
///   A `Future<http.Response>` object containing the server response.
///   On success, the response code will be 200 and the body will contain
///   the JSON response from the API.
///
/// Throws:
///   An `Exception` with an error message if the request fails.
Future<http.Response> sendEventRequest(
    Event requestBody, String apiKey, String lang) async {
  const url = '$baseUrl$sendEventEndpoint';

  final response = await http.post(
    Uri.parse(url),
    headers: getRequestHeaders(apiKey, lang),
    body: jsonEncode(requestBody),
  );

  // Check for successful response
  // Send event returns an empty body
  if (response.statusCode >= 200 && response.statusCode <= 299) {
    return response;
  } else {
    // Handle error based on status code or throw an exception
    throw Exception(
        'Failed to send event. Status code: ${response.statusCode}');
  }
}
