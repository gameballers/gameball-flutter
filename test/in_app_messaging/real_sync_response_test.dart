import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';

/// Parses a response captured from the live alpha endpoint, rather than one we
/// wrote to match our own reading of the contract.
///
/// Captured 2026-08-11 from
/// `POST api.alpha.gameball.app/api/v1.0/bots/inapp/sync?playerUniqueId=…`.
/// Every other parser test asserts against a fixture *we* authored, which proves
/// only that the parser agrees with our interpretation. This one proves it agrees
/// with the backend.
void main() {
  final raw =
      File('test/fixtures/alpha-sync-response.json').readAsStringSync();

  test('the real response parses without loss or error', () {
    final result = parseSyncResponse(raw);

    expect(result.campaigns, hasLength(6),
        reason: 'every campaign in the response is understood — none dropped '
            'for a shape we did not anticipate');
    expect(result.cooldown, const Duration(seconds: 30),
        reason: 'taken from the payload, not the fallback');
  });

  test('campaign identity comes through', () {
    final campaign = parseSyncResponse(raw).campaigns.first;

    expect(campaign.campaignId, 2041);
    expect(campaign.variationId, 4);
    expect(campaign.dispatchId, 'c88ca3f1-2c3c-4d3c-87f7-bf054298e654');
    expect(campaign.name, 'frozen but renameable');
    expect(campaign.priority, 9);
    expect(campaign.isTest, isFalse);
    expect(campaign.repeatable, isFalse);
    expect(campaign.trigger, isA<GameballSessionStartTrigger>());
  });

  test('every campaign carries a dispatchId, so telemetry can attribute', () {
    for (final campaign in parseSyncResponse(raw).campaigns) {
      expect(campaign.dispatchId, isNotNull,
          reason: 'campaign ${campaign.label} could not be attributed');
      expect(campaign.variationId, isNotNull);
    }
  });

  test('slideups are kept as unsupported rather than dropped', () {
    final campaigns = parseSyncResponse(raw).campaigns;

    expect(
      campaigns.every((c) => c.message.type == GameballMessageType.unsupported),
      isTrue,
      reason: 'this response is all messageType 1. Keeping them lets the '
          'evaluator skip them so a usable lower-priority campaign can still '
          'win, rather than the whole sync looking empty',
    );
  });

  test('a content block of explicit nulls does not break styling', () {
    // Every field in the real `content` is present and null — not absent, which
    // is the shape our own fixtures used. A parser that only handled missing keys
    // would throw here.
    final message = parseSyncResponse(raw).campaigns.first.message;

    expect(message.style.backgroundColor, isNull);
    expect(message.style.headerAlign, isNull);
    expect(message.buttons, isEmpty);
    expect(message.extras, isEmpty);
    expect(message.autoDismissAfter, isNull);
    expect(message.clickAction, isNull);
  });

  test('a null closeBehaviour still leaves the message dismissable', () {
    final message = parseSyncResponse(raw).campaigns.first.message;

    expect(message.showCloseButton, isTrue);
    expect(message.dismissOnScrimTap, isTrue,
        reason: 'the live payload sends null here, and a message with no way out '
            'would trap the user in the app');
  });

  test('body text is read from locale.message', () {
    expect(parseSyncResponse(raw).campaigns.first.message.body, 'New slideup A');
  });

  test('success is read from a payload with no errorMsg key at all', () {
    // The live response omits `errorMsg` on success rather than sending null.
    expect(raw.contains('errorMsg'), isFalse);
    expect(parseSyncResponse(raw).campaigns, isNotEmpty);
  });
}
