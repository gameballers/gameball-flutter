import 'dart:convert';

import '../../models/requests/initialize_customer_request.dart';
import '../../models/responses/initialize_customer_response.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';
import 'package:http/http.dart' as http;

/// Sends a customer registration request to the Gameball API asynchronously.
///
/// This function constructs the request URL, sets headers, encodes the
/// `InitializeCustomerRequest` object, and sends a POST request to the API. It
/// then checks the response status code and returns a `InitializeCustomerResponse`
/// object on success or throws an exception on failure.
///
/// Arguments:
///   - `requestBody`: The `InitializeCustomerRequest` object containing customer data.
///   - `apiKey`: The API key for authentication.
///
/// Returns:
///   A `Future<InitializeCustomerResponse>` object containing the server response.
///   On success, the response code will be 200 and the returned object
///   will be a `InitializeCustomerResponse` parsed from the JSON response body.
///
/// Throws:
///   An `Exception` with an error message if the request fails.
Future<InitializeCustomerResponse> registerCustomerRequest(
    InitializeCustomerRequest requestBody, String apiKey, String lang) async {
  const url = '$baseUrl$initializeCustomerEndpoint';

  final response = await http.post(
    Uri.parse(url),
    headers: getRequestHeaders(apiKey, lang),
    body: jsonEncode(requestBody),
  );

  // Check for successful response
  if (response.statusCode >= 200 && response.statusCode <= 299) {
    // Parse the JSON response and return a InitializeCustomerResponse object
    final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
    return InitializeCustomerResponse.fromJson(jsonMap);
  } else {
    // Handle error based on status code or throw an exception
    throw Exception(
        'Failed to create customer. Status code: ${response.statusCode}');
  }
}
