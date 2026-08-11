import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_modal.dart';
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

  /// The one modal in the live payload, and the only campaign this SDK renders.
  InAppMessageCampaign theModal() => parseSyncResponse(raw)
      .campaigns
      .firstWhere((c) => c.message.type == GameballMessageType.modal);

  test('the real response parses without loss or error', () {
    final result = parseSyncResponse(raw);

    expect(result.campaigns, hasLength(7),
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
    final unsupported = parseSyncResponse(raw)
        .campaigns
        .where((c) => c.message.type == GameballMessageType.unsupported);

    expect(unsupported, hasLength(6),
        reason: 'six messageType 1 campaigns. Keeping them lets the evaluator '
            'skip them so the one usable campaign still wins, rather than the '
            'whole sync looking empty');
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

  group('the live modal campaign', () {
    test('its model is assembled from both halves of the payload', () {
      final campaign = theModal();

      expect(campaign.campaignId, 2051);
      expect(campaign.variationId, 16);
      expect(campaign.name, 'Welcome popup on session start');
      expect(campaign.priority, 5);
      expect(campaign.trigger, isA<GameballSessionStartTrigger>());
      expect(campaign.repeatable, isFalse);

      final message = campaign.message;
      expect(message.header, 'Welcome !');
      expect(message.body, 'Great to see you back - check what is new today.');
      expect(message.imageUrl, isNotNull);
      // Text and styling arrive in separate blocks and are joined here.
      expect(message.style.backgroundColor, const Color(0xFFFFFFFF));
      expect(message.style.headerColor, const Color(0xFF111827));
      expect(message.style.bodyColor, const Color(0xFF1F2937));
      expect(message.style.closeButtonColor, isNull,
          reason: 'sent as null, so the host theme decides');
    });

    test('the button is paired across content and locale by id', () {
      final button = theModal().message.buttons.single;

      expect(button.id, 'cta');
      expect(button.text, 'Got it',
          reason: 'the label lives in locale.buttons and the action in '
              'content.buttons — neither half is usable alone');
      expect(button.action, isA<GameballDismissAction>());
    });

    test('closeBehaviour "button" offers the close glyph but not the scrim', () {
      final message = theModal().message;

      expect(message.showCloseButton, isTrue);
      expect(message.dismissOnScrimTap, isFalse,
          reason: 'the live payload says "button", so a tap outside must not '
              'dismiss — the first real campaign to exercise this');
    });

    testWidgets('it renders, and a dead image URL does not stop it',
        (tester) async {
      final message = theModal().message;
      final tapped = <String>[];

      await tester.pumpWidget(MaterialApp(
        home: GameballInAppMessageModal(
          message: message,
          onButtonPressed: (b) => tapped.add(b.id),
          onClosePressed: () {},
          onMessagePressed: () {},
        ),
      ));
      await tester.pump();

      // The campaign image is a placeholder that answers 403, and the test
      // binding fails every image load anyway. Both collapse to nothing, and the
      // message still has to be readable and actionable.
      expect(find.text('Welcome !'), findsOneWidget);
      expect(find.text('Great to see you back - check what is new today.'),
          findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      expect(tapped, ['cta']);
    });
  });

  test('success is read from a payload with no errorMsg key at all', () {
    // The live response omits `errorMsg` on success rather than sending null.
    expect(raw.contains('errorMsg'), isFalse);
    expect(parseSyncResponse(raw).campaigns, isNotEmpty);
  });
}
