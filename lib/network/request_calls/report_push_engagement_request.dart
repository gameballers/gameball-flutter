import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../models/enums/push_engagement_type.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// The body of one push-engagement report.
///
/// [occurredAt] is milliseconds since the epoch and is sent as UTC ISO-8601
/// with milliseconds (`2026-11-09T18:00:00.000Z`). [eventUid] is new for each
/// event unless given, so the backend, which dedupes on it, never counts one
/// event twice.
Map<String, dynamic> pushEngagementBody({
  required String clickToken,
  required PushEngagementType type,
  required int occurredAt,
  String? eventUid,
}) =>
    {
      'clickToken': clickToken,
      'engagementType': type.value,
      'eventUid': eventUid ?? pushEngagementEventUid(),
      'occurredAt':
          DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true).toIso8601String(),
    };

/// Reports one engagement with a Gameball push (a tap or an influenced open) to
/// the push-engagement endpoint, with the same headers as every integrations
/// call. One attempt, no retry.
///
/// Arguments:
///   - `clickToken`: The click token carried in the push's data payload.
///   - `type`: What the customer did with the push.
///   - `occurredAt`: When it happened, in milliseconds since the epoch.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token for secure endpoints.
///   - `client`: Optional HTTP client, for tests.
///
/// Throws:
///   An `Exception` carrying the status code for any answer outside 2xx: the
///   backend answers 202 when it accepts the event.
Future<http.Response> reportPushEngagementRequest({
  required String clickToken,
  required PushEngagementType type,
  required int occurredAt,
  required String apiKey,
  required String lang,
  String? customApiPrefix,
  String? sessionToken,
  http.Client? client,
}) async {
  final url = Uri.parse('${customApiPrefix ?? baseUrl}$pushEngagementPath');
  final headers = getRequestHeaders(apiKey, lang, sessionToken: sessionToken);
  final body = jsonEncode(
      pushEngagementBody(clickToken: clickToken, type: type, occurredAt: occurredAt));

  final response = client != null
      ? await client.post(url, headers: headers, body: body)
      : await http.post(url, headers: headers, body: body);

  if (response.statusCode >= 200 && response.statusCode <= 299) {
    return response;
  }
  throw Exception(
      'Failed to report push engagement. Status code: ${response.statusCode}');
}

final Random _random = Random.secure();

/// A version-4 UUID from a secure random source, for `eventUid`.
///
/// Hand-rolled rather than adding a dependency: a v4 UUID is sixteen random
/// bytes with the version and variant bits set.
String pushEngagementEventUid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
