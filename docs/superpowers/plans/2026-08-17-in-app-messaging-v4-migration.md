# In-App Messaging V4 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the in-app messaging module onto the backend's final V4 integrations API, fix the two payload gaps the live probe exposed, and add pre-display personalisation.

**Architecture:** A wire-and-parser change. The endpoints move to `/api/v4.0/integrations/inapp-messages/{sync,events,variables}`, the bots envelope is deleted rather than made optional, and `trigger.name` replaces `trigger.eventName`. `layout` now arrives explicitly, so the inference heuristic goes. `content.media` becomes an artwork source, which the one live fullscreen campaign needs. Personalisation adds a fifth injected seam and an async display path taken **only** by messages carrying a `{token}`.

**Tech Stack:** Dart 3.4.4+, Flutter, `http`, `shared_preferences`, `flutter_test`. No new dependencies.

**Spec:** [`docs/superpowers/specs/2026-08-17-in-app-messaging-v4-migration-design.md`](../specs/2026-08-17-in-app-messaging-v4-migration-design.md)

## Global Constraints

- **Branch:** `feature/in-app-messaging`. Local commits only — **do not push**.
- **Compatibility invariant:** a client who upgrades and never calls `startInAppMessaging` must observe no difference. No requests, no timers, no overlay, no stored state.
- **Every public type is prefixed `Gameball`.** Internal, non-exported types keep short names.
- **No new pub dependencies.**
- **Analyzer baseline is 13 pre-existing issues** (5 in `lib/gameball_sdk.dart`, 8 in `example/lib/main.dart`). `flutter analyze` must report **exactly 13** after every task, with **zero** in `lib/in_app_messaging/` or `lib/network/`.
- **Test baseline is 418 passing.** Every task ends green. Tests deleted must be justified by a contract that no longer exists.
- **Dart language version predates wildcard `_` parameters.** Use `(_, __)`, never `(_, _)`.
- **Alpha probing:** host `https://api.alpha.gameball.app`, customer `moaty-survey-7`. The API key is not in the repo; export it as `GB_ALPHA_KEY` when a step needs it.
- All commands run with `export PATH="$HOME/development/flutter/bin:$PATH"`.

## File Structure

| File | Change | Responsibility |
| --- | --- | --- |
| `lib/network/utils/constants.dart` | Modify | Replace the two `bots/inapp` paths with V4 integrations paths |
| `lib/network/request_calls/sync_in_app_messages_request.dart` | Modify | V4 path, `customerId` in body, 404 disambiguation, platform-0 warning, injectable client |
| `lib/network/request_calls/send_message_events_request.dart` | Modify | V4 path, `customerId`+`platform` in body, status-only outcome, injectable client |
| `lib/network/request_calls/fetch_message_variables_request.dart` | **Create** | POST variables, return the value map |
| `lib/in_app_messaging/source/message_parser.dart` | Modify | Drop envelope, read `name`, authoritative `layout`, `media` artwork, blank-URL normalisation |
| `lib/in_app_messaging/source/stub_message_source.dart` | Modify | Rewrite the offline fixture to the V4 shape |
| `lib/in_app_messaging/personalisation/variable_source.dart` | **Create** | `VariableSource` seam + HTTP implementation + 60s cache |
| `lib/in_app_messaging/personalisation/token_substitution.dart` | **Create** | Pure `{token}` substitution over a message |
| `lib/in_app_messaging/models/in_app_message.dart` | Modify | Narrow copy method for substituted text |
| `lib/in_app_messaging/in_app_messaging_service.dart` | Modify | Resolve-then-present path, in-flight guard, two new durations |
| `lib/gameball_sdk.dart` | Modify | Construct the variable source; `debugVariableSource` seam |
| `test/fixtures/v4-sync-response.json` | **Create** | Live payload captured from alpha |
| `test/fixtures/alpha-sync-response.json` | **Delete** | Bots-era, superseded |

---

## Task 1: Wire layer — endpoints, request bodies, status mapping

**Files:**
- Modify: `lib/network/utils/constants.dart:7-11`
- Modify: `lib/network/request_calls/sync_in_app_messages_request.dart`
- Modify: `lib/network/request_calls/send_message_events_request.dart`
- Test: `test/network/send_message_events_request_test.dart` (rewrite for V4), `test/network/sync_in_app_messages_request_test.dart` (create)

**Interfaces:**
- Consumes: `integrationsUrlV4_0` (`"/api/v4.0/integrations"`), `getRequestHeaders(apiKey, lang, {sessionToken})`, `GameballAnalyticsSendResult.{accepted,retry,discard}`.
- Produces: `inAppMessagesSyncPath`, `inAppMessagesEventsPath`. **Signatures otherwise unchanged.**

> **Corrected during execution.** The first draft added an `http.Client? client` parameter to both
> functions for testability. `test/network/send_message_events_request_test.dart` already exists and
> injects with `http.runWithClient`, a zone override that needs no production parameter at all.
> Test-only parameters on production signatures are exactly what that pattern avoids, so the tests
> below extend the existing file and add a sibling for sync, rather than introducing a second
> mechanism.

- [ ] **Step 1: Write the failing tests**

Rewrite `test/network/send_message_events_request_test.dart` for the V4 contract and add
`test/network/sync_in_app_messages_request_test.dart` beside it. Both use the `http.runWithClient`
helper and the hand-rolled `MockClient` the existing file already defines — copy that class into the
new file rather than exporting it, since a shared test utility across two files is more coupling
than two small classes.

Cover, for events: the v4 path; `customerId` in the body with an empty query; `platform` and
`events` at the top level; the standard headers; then one case per status — 202 accepted, 202 with
`rejected:1` still accepted, an unreadable 2xx accepted, 400/401/404/422 discarded, 408/429/500/503
retried, and a transport throw retried.

For sync: the v4 path; `customerId` in the body with an empty query; the full targeting body; the
headers; a 200 body returned verbatim; every non-2xx yielding null; a transport throw yielding null;
and two platform cases — that an unknown platform is sent unaltered rather than corrected, and that
an empty list from one is a success rather than a failure.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/network/`
Expected: FAIL — the paths are still `bots/inapp` and the body still has no `customerId`.

- [ ] **Step 3: Replace the endpoint constants**

In `lib/network/utils/constants.dart`, replace lines 7-11:

```dart
// In-app messaging lives on the V4 integrations surface, alongside the rest of
// this SDK. Pinned to v4.0 and deliberately *not* built with
// getIntegrationsUrl(): that helper switches to v4.1 when a session token is
// present, and the v4.1 variant of these paths answers 401 to APIKey auth — so
// routing through it would break in-app messaging for exactly the hosts that set
// a token. See docs/superpowers/specs/2026-08-17-in-app-messaging-v4-migration-design.md
const inAppMessagesSyncPath = "$integrationsUrlV4_0/inapp-messages/sync";
const inAppMessagesEventsPath = "$integrationsUrlV4_0/inapp-messages/events";
```

- [ ] **Step 4: Rewrite the sync request**

Replace the body of `lib/network/request_calls/sync_in_app_messages_request.dart` below the imports. Add `import 'package:http/http.dart' as http;` if not present, and update the doc comment's endpoint name:

```dart
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
```


- [ ] **Step 5: Rewrite the events request**

Replace `lib/network/request_calls/send_message_events_request.dart` entirely:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../in_app_messaging/analytics/batched_message_analytics.dart';
import '../../in_app_messaging/iam_log.dart';
import '../utils/constants.dart';
import '../utils/header_generator.dart';

/// Posts a batch of in-app message telemetry to `integrations/inapp-messages/events`.
///
/// Unlike [sendLogsRequest], this reports an outcome: the caller keeps a
/// persistent outbox and has to know whether a batch can be dropped, should be
/// retried, or is poison. The distinction matters because the outbox is FIFO — a
/// batch retried forever blocks everything logged after it.
///
/// V4 reports failure with the status code, not inside a 200, so the whole
/// envelope reader this function used to carry is gone.
///
/// Arguments:
///   - `events`: at most [maxEventsPerRequest], oldest first.
///   - `customerId`: the external customer id, sent in the body.
///   - `platform`: 1 for iOS, 2 for Android.
///   - `apiKey`: The API key for authentication.
///   - `lang`: The language code.
///   - `customApiPrefix`: Optional custom API base URL.
///   - `sessionToken`: Optional Session Token, sent when the integration has one.
Future<GameballAnalyticsSendResult> sendMessageEventsRequest(
  List<Map<String, dynamic>> events, {
  required String customerId,
  required int platform,
  required String apiKey,
  required String lang,
  String? customApiPrefix,
  String? sessionToken,
}) async {
  try {
    final apiBaseUrl = customApiPrefix ?? baseUrl;
    final url = Uri.parse('$apiBaseUrl$inAppMessagesEventsPath');

    final response = await http.post(
      url,
      headers: getRequestHeaders(apiKey, lang, sessionToken: sessionToken),
      body: jsonEncode(<String, dynamic>{
        'customerId': customerId,
        'platform': platform,
        'events': events,
      }),
    );

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      _logRejected(response.body, events.length);
      return GameballAnalyticsSendResult.accepted;
    }

    // 408 and 429 are the two 4xx worth retrying; 5xx includes the documented
    // 503. Everything else means the request itself is wrong, and an unchanged
    // retry cannot fix it.
    if (status == 408 || status == 429 || status >= 500) {
      iamLog('analytics: HTTP $status — will retry');
      return GameballAnalyticsSendResult.retry;
    }

    // 422 arrives for two unrelated reasons — a deactivated customer, and a
    // batch in which every event was malformed. Verified against alpha. Both are
    // permanent for this batch, so they share an outcome; do not read this as
    // "the customer is deactivated".
    iamLog('analytics: HTTP $status — dropping ${events.length} event(s), a '
        'retry cannot help');
    return GameballAnalyticsSendResult.discard;
  } catch (_) {
    // No network, DNS failure, timeout — all worth retrying.
    return GameballAnalyticsSendResult.retry;
  }
}

/// Logs individually-rejected events. Diagnostics only: the batch landed.
void _logRejected(String body, int sentCount) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    // The counts are diagnostics and the status already said the batch was
    // taken, so an unreadable body changes nothing.
    return;
  }
  if (decoded is! Map<String, dynamic>) return;

  final rejected = decoded['rejected'];
  if (rejected is int && rejected > 0) {
    // "Will never succeed", and the response does not say which. Since the
    // backend accepted the rest, dropping the whole batch is the only correct
    // reading.
    iamLog('analytics: backend rejected $rejected of $sentCount event(s) as '
        'malformed; they will not be retried');
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/network/`
Expected: PASS, 25 tests.

- [ ] **Step 7: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass; analyzer reports exactly 13 issues.

- [ ] **Step 8: Commit**

```bash
git add lib/network test/network
git commit -m "feat(iam)!: move the wire layer to the V4 integrations surface"
```

---

## Task 2: Live fixture and `trigger.name`

**Files:**
- Create: `test/fixtures/v4-sync-response.json`
- Delete: `test/fixtures/alpha-sync-response.json`
- Modify: `test/in_app_messaging/real_sync_response_test.dart`
- Modify: `lib/in_app_messaging/source/message_parser.dart` (`_parseTrigger`, `_parseFilters`)

**Interfaces:**
- Consumes: `parseSyncResponse(String) → GameballSyncResult` from Task 1's unchanged parser.
- Produces: no signature changes. `_parseTrigger` reads `json['name']`; `_parseFilters` reads `entry['name']`.

- [ ] **Step 1: Capture the live payload**

```bash
export GB_ALPHA_KEY=<the alpha key>
curl -s -X POST https://api.alpha.gameball.app/api/v4.0/integrations/inapp-messages/sync \
  -H 'Content-Type: application/json' -H "ApiKey: $GB_ALPHA_KEY" \
  -d '{"customerId":"moaty-survey-7","platform":2,"locale":"en",
       "appVersion":"3.3.0","sdkVersion":"3.3.0"}' \
  | python3 -m json.tool > test/fixtures/v4-sync-response.json
git rm test/fixtures/alpha-sync-response.json
```

Sanity-check it before continuing — `platform` is not optional in effect, and omitting it returns an empty list:

```bash
python3 -c "
import json; d=json.load(open('test/fixtures/v4-sync-response.json'))
print(len(d['messages']), 'campaigns;', sorted({m['messageType'] for m in d['messages']}))"
```
Expected: `8 campaigns; [1, 2, 3]`.

- [ ] **Step 2: Rewrite the live-payload test**

Replace `test/in_app_messaging/real_sync_response_test.dart` in full:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';

/// Parses a response captured from the live V4 endpoint, rather than one we
/// wrote to match our own reading of the contract.
///
/// Captured 2026-08-17 from
/// `POST api.alpha.gameball.app/api/v4.0/integrations/inapp-messages/sync`.
/// Every other parser test asserts against a fixture *we* authored, which proves
/// only that the parser agrees with our interpretation. This one proves it agrees
/// with the backend — and it is what caught `content.media` going unread.
void main() {
  final raw = File('test/fixtures/v4-sync-response.json').readAsStringSync();

  List<InAppMessageCampaign> parsed() => parseSyncResponse(raw).campaigns;

  InAppMessageCampaign byId(int id) =>
      parsed().firstWhere((c) => c.campaignId == id);

  test('every campaign in the live payload parses', () {
    expect(parsed(), hasLength(8),
        reason: 'a dropped campaign is a campaign the customer never sees');
  });

  test('the payload exercises all three rendered types', () {
    final types = parsed().map((c) => c.message.type).toSet();
    expect(types, containsAll(<GameballMessageType>[
      GameballMessageType.modal,
      GameballMessageType.slideup,
      GameballMessageType.fullscreen,
    ]));
  });

  test('the cooldown comes from the response, not the client default', () {
    expect(parseSyncResponse(raw).cooldown, const Duration(seconds: 30));
  });

  group('event triggers', () {
    test('an event trigger keeps the name the backend sent', () {
      final campaign = byId(2055);
      expect(
        campaign.trigger,
        isA<GameballCustomEventTrigger>()
            .having((t) => t.eventName, 'eventName', 'place_order'),
      );
    });

    test('the other event campaign is named too', () {
      expect(
        byId(2054).trigger,
        isA<GameballCustomEventTrigger>()
            .having((t) => t.eventName, 'eventName', 'view_product_page'),
      );
    });

    test('session_start campaigns carry no event name', () {
      expect(byId(2053).trigger, isA<GameballSessionStartTrigger>());
    });
  });

  test('repeatable campaigns keep their minimum interval', () {
    expect(byId(2055).repeatable, isTrue);
    expect(byId(2055).minInterval, const Duration(seconds: 300));
  });

  test('a modal keeps its button, paired with the translated label', () {
    final buttons = byId(2053).message.buttons;
    expect(buttons, hasLength(1));
    expect(buttons.single.id, 'cta');
    expect(buttons.single.text, 'Shop now');
    expect(buttons.single.action, isA<GameballOpenUrlAction>());
  });
}
```

- [ ] **Step 3: Run it to watch the trigger tests fail**

Run: `flutter test test/in_app_messaging/real_sync_response_test.dart`
Expected: FAIL. `hasLength(8)` reports 6, and the event-trigger tests fail — the parser reads `eventName`, which V4 does not send, so both event campaigns are dropped.

- [ ] **Step 4: Read `trigger.name`**

In `lib/in_app_messaging/source/message_parser.dart`, inside `_parseTrigger`, replace the `case 'event':` block's first statement and its log:

```dart
    case 'event':
    case 'custom_event':
      final eventName = _asString(json['name']);
      if (eventName == null || eventName.isEmpty) {
        // The backend keys triggers on a numeric eventId and sends the name
        // alongside it. Without the name there is nothing to match a locally
        // logged event against — the id is internal and meaningless here.
        iamLog('campaign $label dropped: event trigger has no "name" '
            '(eventId ${json['eventId']} cannot be resolved on the device)');
        return null;
      }
```

- [ ] **Step 5: Read the filter's `name`**

In `_parseFilters`, replace the three-spelling lookup:

```dart
    // V4 names both the trigger's event and each filter's property with `name`.
    // The older spellings are gone rather than tolerated: the v1 and v4 paths are
    // disjoint, so a v4 response always uses this one.
    final property = _asString(entry['name']);
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/in_app_messaging/real_sync_response_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 7: Fix the fixture-authored parser tests**

Locate them:

```bash
grep -rn '"eventName"\|"metadataKey"\|"metadataName"\|"property"' \
  test/in_app_messaging/ lib/in_app_messaging/source/stub_message_source.dart
```

Rename every one of those JSON keys to `"name"`. Do **not** re-add tolerance in the parser — the
point of the change is that there is one spelling. Then re-run:

```bash
flutter test test/in_app_messaging/message_parser_test.dart
```

Also update `lib/in_app_messaging/source/stub_message_source.dart`: rename `"eventName"` to `"name"` in each trigger and the metadata filter's key to `"name"`.

- [ ] **Step 8: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 analyzer issues.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(iam)!: read trigger.name, and test against a live V4 payload"
```

---

## Task 3: `layout` becomes authoritative

**Files:**
- Modify: `lib/in_app_messaging/source/message_parser.dart` (`_resolveLayout`, and its call site)
- Test: `test/in_app_messaging/message_parser_test.dart`

**Interfaces:**
- Consumes: `GameballMessageLayout.{textWithImage, imageOnly}`, `GameballMessageType`.
- Produces: `_resolveLayout(Map<String, dynamic> content, GameballMessageType type, String label)` — **the signature changes**: the `hasText`/`hasImage` booleans are gone and the message type is needed for the default.

- [ ] **Step 1: Write the failing tests**

Append to `test/in_app_messaging/message_parser_test.dart`, inside `void main()`:

```dart
  group('layout, which the backend now names explicitly', () {
    String campaignJson({
      required int messageType,
      String? layout,
      String header = 'Header',
      String message = 'Body',
    }) =>
        '''
{
  "cooldownSeconds": 30,
  "messages": [
    { "campaignId": 1, "messageType": $messageType,
      "trigger": {"type": "session_start"},
      "contentMode": "prerendered",
      "content": { "imageUrl": "https://example.com/a.png"
        ${layout == null ? '' : ', "layout": "$layout"'} },
      "locale": { "header": "$header", "message": "$message" } }
  ]
}
''';

    GameballInAppMessage parse(String raw) =>
        parseSyncResponse(raw).campaigns.single.message;

    test('a modal defaults to text with image', () {
      expect(parse(campaignJson(messageType: 2)).layout,
          GameballMessageLayout.textWithImage);
    });

    test('a modal honours image_only', () {
      expect(parse(campaignJson(messageType: 2, layout: 'image_only')).layout,
          GameballMessageLayout.imageOnly);
    });

    test('a fullscreen honours image_and_text', () {
      expect(
          parse(campaignJson(messageType: 3, layout: 'image_and_text')).layout,
          GameballMessageLayout.textWithImage);
    });

    test('a fullscreen honours image_only', () {
      expect(parse(campaignJson(messageType: 3, layout: 'image_only')).layout,
          GameballMessageLayout.imageOnly);
    });

    test('an unknown layout falls back to the default, keeping the message', () {
      final campaigns =
          parseSyncResponse(campaignJson(messageType: 2, layout: 'diagonal'))
              .campaigns;
      expect(campaigns, hasLength(1),
          reason: 'layout is a rendering hint, not a contract — an unknown '
              'value must never cost the customer the message');
      expect(campaigns.single.message.layout,
          GameballMessageLayout.textWithImage);
    });

    test('copy with no image is still text-with-image, not inferred away', () {
      const raw = '''
{
  "cooldownSeconds": 30,
  "messages": [
    { "campaignId": 1, "messageType": 2,
      "trigger": {"type": "session_start"},
      "contentMode": "prerendered",
      "content": { "imageUrl": "https://example.com/a.png" },
      "locale": { "header": null, "message": null } }
  ]
}
''';
      // Before V4 this was inferred as image-only because no copy arrived. The
      // backend now says what it means, so an absent layout means the default —
      // which is exactly the "Welcome !" failure O12 described.
      expect(parseSyncResponse(raw).campaigns.single.message.layout,
          GameballMessageLayout.textWithImage);
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/in_app_messaging/message_parser_test.dart --plain-name "layout, which the backend"`
Expected: FAIL — `image_and_text` is unrecognised, and the last test still infers `imageOnly`.

- [ ] **Step 3: Replace `_resolveLayout`**

In `lib/in_app_messaging/source/message_parser.dart`, replace the whole `_resolveLayout` function:

```dart
/// Reads how the image and copy are arranged.
///
/// The backend names this now — `layout` on `content`, following Braze's
/// image-style model. Until it did, this function inferred the layout from which
/// fields arrived, which could not tell a deliberately image-only campaign from
/// one whose personalised copy resolved to empty. That inference is gone, along
/// with the `imageStyle` alternate key and the Braze `graphic`/`top` spellings:
/// all three were hedges against a contract that had not been written.
///
/// An unknown value falls back to the type's default rather than skipping the
/// message. The contract is explicit that layout is a rendering hint, so a value
/// this SDK version does not know must never cost the customer the message.
GameballMessageLayout _resolveLayout(
  Map<String, dynamic> content,
  GameballMessageType type,
  String label,
) {
  final declared = _asString(content['layout']);
  switch (declared?.toLowerCase()) {
    case 'image_only':
      return GameballMessageLayout.imageOnly;
    // Modal and fullscreen spell their default differently; both mean "image
    // above the copy", which is the one layout this enum calls textWithImage.
    case 'text_with_image':
    case 'image_and_text':
      return GameballMessageLayout.textWithImage;
    case null:
      return GameballMessageLayout.textWithImage;
    default:
      iamLog('campaign $label: unknown layout "$declared", rendering the '
          'default for a ${type.name}');
      return GameballMessageLayout.textWithImage;
  }
}
```

- [ ] **Step 4: Update the call site**

In `_parseMessage`, replace the `layout:` argument:

```dart
    layout: _resolveLayout(content, type, label),
```

If `hasHeader`, `hasBody` or `hasImage` become unused as a result, leave them — they are still used by the validity checks above. Run the analyzer in Step 6 to confirm.

- [ ] **Step 5: Run the layout tests**

Run: `flutter test test/in_app_messaging/message_parser_test.dart --plain-name "layout, which the backend"`
Expected: PASS, 6 tests.

- [ ] **Step 6: Fix any parser tests that relied on inference**

Locate them:

```bash
grep -rn "imageOnly" test/in_app_messaging/ | grep -v token_substitution
```

Tests asserting that a copy-less campaign *became* `imageOnly` now fail: that inference is
deliberately gone. Rewrite each to declare `"layout": "image_only"` in its fixture. Keep one,
renamed, asserting the opposite — that absent copy no longer implies image-only — since that is the
O12 failure this change exists to prevent.

- [ ] **Step 7: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(iam): read the layout the backend now sends, and stop inferring it (O12)"
```

---

## Task 4: `content.media` as an artwork source

**Files:**
- Modify: `lib/in_app_messaging/source/message_parser.dart` (`_parseMessage`, new `_artworkUrl`, new `_asUrl`)
- Test: `test/in_app_messaging/message_parser_test.dart`, `test/in_app_messaging/real_sync_response_test.dart`

**Interfaces:**
- Consumes: `GameballMessageType`.
- Produces: `String? _artworkUrl(Map<String, dynamic> content, GameballMessageType type, String label)` and `String? _asUrl(Object? value)`.

- [ ] **Step 1: Write the failing tests**

Append to `test/in_app_messaging/message_parser_test.dart`:

```dart
  group('artwork, which fullscreen delivers as media', () {
    String withContent(String content, {int messageType = 3}) => '''
{
  "cooldownSeconds": 30,
  "messages": [
    { "campaignId": 1, "messageType": $messageType,
      "trigger": {"type": "session_start"},
      "contentMode": "prerendered",
      "content": $content,
      "locale": { "header": "H", "message": "B" } }
  ]
}
''';

    GameballInAppMessage parse(String raw) =>
        parseSyncResponse(raw).campaigns.single.message;

    test('a fullscreen takes its artwork from media when imageUrl is null', () {
      final message = parse(withContent(
          '{"imageUrl": null, "media": {"type":"image","url":"https://x/m.png"}}'));
      expect(message.imageUrl, 'https://x/m.png');
    });

    test('a fullscreen prefers media over imageUrl', () {
      final message = parse(withContent(
          '{"imageUrl":"https://x/i.png","media":{"type":"image","url":"https://x/m.png"}}'));
      expect(message.imageUrl, 'https://x/m.png',
          reason: 'the contract puts fullscreen artwork in media');
    });

    test('a modal prefers imageUrl over media', () {
      final message = parse(
        withContent(
            '{"imageUrl":"https://x/i.png","media":{"type":"image","url":"https://x/m.png"}}',
            messageType: 2),
      );
      expect(message.imageUrl, 'https://x/i.png');
    });

    test('a modal still falls back to media', () {
      final message = parse(
        withContent('{"media":{"type":"image","url":"https://x/m.png"}}',
            messageType: 2),
      );
      expect(message.imageUrl, 'https://x/m.png');
    });

    test('video media is ignored rather than rendered as a broken image', () {
      final message = parse(withContent(
          '{"imageUrl": null, "media": {"type":"video","url":"https://x/v.mp4"}}'));
      expect(message.imageUrl, isNull);
    });

    test('a blank url is treated as absent', () {
      final message =
          parse(withContent('{"imageUrl": "   ", "media": null}', messageType: 2));
      expect(message.imageUrl, isNull,
          reason: 'an empty url would make the prefetcher pass the whole '
              'campaign over, silently');
    });
  });
```

Append to `test/in_app_messaging/real_sync_response_test.dart`:

```dart
  test('the live fullscreen campaign gets its artwork from media', () {
    // Campaign 2055 carries imageUrl: null and its image only in content.media.
    // Before this was read, the one fullscreen campaign on alpha had no artwork
    // at all — and with the prefetcher in place it would have been passed over.
    final message = byId(2055).message;
    expect(message.type, GameballMessageType.fullscreen);
    expect(message.imageUrl, isNotNull);
    expect(message.imageUrl, contains('http'));
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/in_app_messaging/message_parser_test.dart --plain-name "artwork, which fullscreen"`
Expected: FAIL — `media` is never read, so `imageUrl` is null.

- [ ] **Step 3: Add the helpers**

At the bottom of `lib/in_app_messaging/source/message_parser.dart`, beside `_asString`:

```dart
/// A URL, or null when the value is absent or blank.
///
/// Blank is treated as absent deliberately. An empty image URL reaches the
/// artwork prefetcher, fails to load, and makes the whole campaign be passed over
/// with no way to tell it from a network failure — a severe, silent outcome for a
/// value that clearly means "none".
String? _asUrl(Object? value) {
  final text = _asString(value)?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// The image a message should render, from either field that can carry one.
///
/// Fullscreen puts its artwork in `content.media` and modals in
/// `content.imageUrl`, so precedence follows the type and each falls back to the
/// other. Both feed the same renderer, which is why they collapse into one field
/// on the model rather than two.
///
/// Video is parsed and ignored: this SDK renders no video, and treating a video
/// URL as an image would draw a broken frame.
String? _artworkUrl(
  Map<String, dynamic> content,
  GameballMessageType type,
  String label,
) {
  final direct = _asUrl(content['imageUrl']);

  String? fromMedia;
  final media = content['media'];
  if (media is Map<String, dynamic>) {
    final mediaType = _asString(media['type'])?.toLowerCase();
    if (mediaType == null || mediaType == 'image') {
      fromMedia = _asUrl(media['url']);
    } else {
      iamLog('campaign $label: ignoring "$mediaType" media — this SDK version '
          'renders images only');
    }
  }

  return type == GameballMessageType.fullscreen
      ? (fromMedia ?? direct)
      : (direct ?? fromMedia);
}
```

- [ ] **Step 4: Use it in `_parseMessage`**

Find where `imageUrl` is read in `_parseMessage` (near the `header`/`body` reads) and replace it:

```dart
  final imageUrl = _artworkUrl(content, type, label);
```

Leave the `hasImage` computation and the `imageUrl: hasImage ? imageUrl : null` argument as they are — they now operate on the resolved value. Also swap the `iconUrl` read to the new helper for consistency:

```dart
  final iconUrl = _asUrl(content['iconUrl']);
```

and simplify its argument to `iconUrl: iconUrl,` since `_asUrl` has already rejected blanks.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/in_app_messaging/message_parser_test.dart test/in_app_messaging/real_sync_response_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "fix(iam): read fullscreen artwork from content.media"
```

---

## Task 5: Delete the envelope

**Files:**
- Modify: `lib/in_app_messaging/source/message_parser.dart` (`parseSyncResponse`)
- Modify: `lib/in_app_messaging/source/stub_message_source.dart`
- Test: `test/in_app_messaging/message_parser_test.dart`

**Interfaces:**
- Consumes / Produces: `parseSyncResponse(String) → GameballSyncResult`, signature unchanged.

- [ ] **Step 1: Write the failing test**

Append to `test/in_app_messaging/message_parser_test.dart`:

```dart
  group('the V4 payload has no envelope', () {
    test('a plain payload parses', () {
      const raw = '''
{ "cooldownSeconds": 45, "messages": [] }
''';
      expect(parseSyncResponse(raw).cooldown, const Duration(seconds: 45));
    });

    test('a bots-style wrapper is no longer unwrapped', () {
      // The v1 and v4 paths are disjoint, so a wrapper can only arrive from a
      // misconfigured base URL. Reading it would hide that.
      const raw = '''
{ "success": true, "response": { "cooldownSeconds": 45, "messages": [] } }
''';
      final result = parseSyncResponse(raw);
      expect(result.campaigns, isEmpty);
      expect(result.cooldown, const Duration(seconds: 30),
          reason: 'the client default, because "messages" is not at the root');
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/in_app_messaging/message_parser_test.dart --plain-name "no envelope"`
Expected: FAIL on the second test — the parser still unwraps `response`.

- [ ] **Step 3: Simplify `parseSyncResponse`**

In `lib/in_app_messaging/source/message_parser.dart`, replace the doc comment and delete the `success` check and the `payload` indirection:

```dart
/// Parses an `integrations/inapp-messages/sync` response.
///
/// Never throws. The rule is: drop what can never work, keep-but-skip what a
/// future SDK version might support, and log every decision.
///
/// V4 returns a plain payload and reports failure with the status code, so the
/// bots envelope — and its ability to say `success:false` inside a 200 — is gone
/// rather than optional. A wrapper reaching this function now means a
/// misconfigured base URL, and failing to find `messages` says so.
GameballSyncResult parseSyncResponse(String rawJson) {
  Object? decoded;
  try {
    decoded = jsonDecode(rawJson);
  } catch (error) {
    iamLog('sync parse failed: payload is not valid JSON ($error)');
    return const GameballSyncResult.empty();
  }

  if (decoded is! Map<String, dynamic>) {
    iamLog('sync parse failed: payload root is not an object');
    return const GameballSyncResult.empty();
  }

  final messagesJson = decoded['messages'];
  if (messagesJson is! List) {
    iamLog('sync parse failed: "messages" is missing or not a list');
    return const GameballSyncResult.empty();
  }

  final cooldownSeconds = _asInt(decoded['cooldownSeconds']);
```

Leave the loop and the `return GameballSyncResult(...)` beneath it untouched, changing only `payload['messages']` / `payload['cooldownSeconds']` references as shown.

- [ ] **Step 4: Rewrite the stub fixture**

In `lib/in_app_messaging/source/stub_message_source.dart`, remove the enclosing `"success": true, "response": { ... }` wrapper so the fixture's root is `{"cooldownSeconds": …, "messages": [ … ]}`, and update the doc comment:

```dart
/// A stand-in `integrations/inapp-messages/sync` response, shaped exactly like
/// the real one.
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/in_app_messaging/message_parser_test.dart test/in_app_messaging/stub_message_source_test.dart`
Expected: PASS. Delete any remaining test that asserted `success:false` handling — that shape cannot arrive from a v4 path.

- [ ] **Step 6: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(iam)!: drop the bots envelope, which V4 does not send"
```

---

## Task 6: Variable source and its HTTP client

**Files:**
- Create: `lib/network/request_calls/fetch_message_variables_request.dart`
- Create: `lib/in_app_messaging/personalisation/variable_source.dart`
- Modify: `lib/network/utils/constants.dart`
- Test: `test/in_app_messaging/variable_source_test.dart` (create)

**Interfaces:**
- Produces:
  - `const inAppMessagesVariablesPath`
  - `Future<Map<String, String>> fetchMessageVariablesRequest({required String customerId, required String apiKey, required String lang, String? customApiPrefix, String? sessionToken})` — injected in tests with `http.runWithClient`, like its siblings
  - `abstract interface class VariableSource { Future<Map<String, String>> fetch(String customerId); }`
  - `class CachingVariableSource implements VariableSource` — constructor `CachingVariableSource({required Future<Map<String, String>> Function(String) fetcher, Duration ttl = defaultVariableCacheTtl, DateTime Function()? clock})`, plus `void clear()`
  - `const Duration defaultVariableCacheTtl = Duration(seconds: 60);`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/variable_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/personalisation/variable_source.dart';

void main() {
  group('CachingVariableSource', () {
    test('fetches once and serves the cache inside the ttl', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 8, 17, 12);
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          return <String, String>{'points_balance': '1,250'};
        },
        ttl: const Duration(seconds: 60),
        clock: () => now,
      );

      expect(await source.fetch('c1'), {'points_balance': '1,250'});
      now = now.add(const Duration(seconds: 30));
      expect(await source.fetch('c1'), {'points_balance': '1,250'});

      expect(calls, 1, reason: 'several messages in one burst share one fetch');
    });

    test('refetches once the ttl has passed', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 8, 17, 12);
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          return <String, String>{'n': '$calls'};
        },
        ttl: const Duration(seconds: 60),
        clock: () => now,
      );

      await source.fetch('c1');
      now = now.add(const Duration(seconds: 61));
      expect(await source.fetch('c1'), {'n': '2'});
      expect(calls, 2);
    });

    test('a different customer never reads the previous one cache', () async {
      var now = DateTime.utc(2026, 8, 17, 12);
      final source = CachingVariableSource(
        fetcher: (id) async => <String, String>{'who': id},
        clock: () => now,
      );

      expect(await source.fetch('c1'), {'who': 'c1'});
      expect(await source.fetch('c2'), {'who': 'c2'});
    });

    test('clear() drops the cache', () async {
      var calls = 0;
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          return <String, String>{};
        },
      );

      await source.fetch('c1');
      source.clear();
      await source.fetch('c1');
      expect(calls, 2);
    });

    test('a failing fetch yields an empty map rather than throwing', () async {
      final source = CachingVariableSource(
        fetcher: (_) async => throw StateError('offline'),
      );

      expect(await source.fetch('c1'), isEmpty,
          reason: 'the only correct response to every documented failure is '
              '"use the text you already hold"');
    });

    test('a failure is not cached', () async {
      var calls = 0;
      final source = CachingVariableSource(
        fetcher: (_) async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return <String, String>{'ok': 'yes'};
        },
      );

      expect(await source.fetch('c1'), isEmpty);
      expect(await source.fetch('c1'), {'ok': 'yes'});
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/in_app_messaging/variable_source_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Add the endpoint constant**

In `lib/network/utils/constants.dart`, beneath the other two:

```dart
const inAppMessagesVariablesPath = "$integrationsUrlV4_0/inapp-messages/variables";
```

- [ ] **Step 4: Write the HTTP request**

Create `lib/network/request_calls/fetch_message_variables_request.dart`:

```dart
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
```

- [ ] **Step 5: Write the seam and the cache**

Create `lib/in_app_messaging/personalisation/variable_source.dart`:

```dart
import '../iam_log.dart';

/// How long a fetched variable map stays usable.
///
/// Several messages can display in quick succession — a session-start message
/// dismissed, then an event-triggered one — and refetching for each would put
/// avoidable latency on the display path for values that cannot have moved.
const Duration defaultVariableCacheTtl = Duration(seconds: 60);

/// Current personalisation values for a customer.
///
/// Internal: not exported to hosts. A seam like the source, presenter, frequency
/// cap, analytics and prefetcher, so the service can be tested without a network.
abstract interface class VariableSource {
  /// Current values for [customerId]. **Empty when unavailable** — never throws,
  /// because the caller's only response to a failure is to use the text it has.
  Future<Map<String, String>> fetch(String customerId);
}

/// Wraps a fetcher in a short per-customer cache.
class CachingVariableSource implements VariableSource {
  CachingVariableSource({
    required Future<Map<String, String>> Function(String customerId) fetcher,
    this.ttl = defaultVariableCacheTtl,
    DateTime Function()? clock,
  })  : _fetch = fetcher,
        _clock = clock ?? DateTime.now;

  final Future<Map<String, String>> Function(String customerId) _fetch;
  final DateTime Function() _clock;
  final Duration ttl;

  String? _customerId;
  Map<String, String>? _values;
  DateTime? _fetchedAt;

  @override
  Future<Map<String, String>> fetch(String customerId) async {
    final at = _fetchedAt;
    if (_customerId == customerId &&
        _values != null &&
        at != null &&
        _clock().difference(at) < ttl) {
      return _values!;
    }

    Map<String, String> values;
    try {
      values = await _fetch(customerId);
    } catch (error) {
      // Not cached: a failure is a moment, not a value. Caching it would extend
      // one dead request into a minute of stale text.
      iamLog('variables unavailable ($error)');
      return const <String, String>{};
    }

    _customerId = customerId;
    _values = values;
    _fetchedAt = _clock();
    return values;
  }

  /// Forgets everything. Called when the customer changes and on stop.
  void clear() {
    _customerId = null;
    _values = null;
    _fetchedAt = null;
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/in_app_messaging/variable_source_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 7: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(iam): add the personalisation variable source and its cache"
```

---

## Task 7: Token substitution

**Files:**
- Create: `lib/in_app_messaging/personalisation/token_substitution.dart`
- Modify: `lib/in_app_messaging/models/in_app_message.dart`
- Test: `test/in_app_messaging/token_substitution_test.dart` (create)

**Interfaces:**
- Produces:
  - `bool messageHasTokens(GameballInAppMessage message)`
  - `String substituteTokens(String text, Map<String, String> values)`
  - `GameballInAppMessage substituteInto(GameballInAppMessage message, Map<String, String> values)`
  - `GameballInAppMessage.withText({String? header, String? body, List<GameballMessageButton>? buttons})` and `GameballMessageButton.withText(String text)`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/token_substitution_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/personalisation/token_substitution.dart';

GameballInAppMessage message({
  String? header,
  String? body,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
}) =>
    GameballInAppMessage(
      id: 'm',
      type: GameballMessageType.modal,
      header: header,
      body: body,
      buttons: buttons,
    );

GameballMessageButton button(String text) => GameballMessageButton(
      id: 'b',
      text: text,
      action: const GameballDismissAction(),
    );

void main() {
  group('substituteTokens', () {
    const values = <String, String>{
      'first_name': 'Ahmed',
      'points_balance': '1,250',
    };

    test('replaces a known token', () {
      expect(substituteTokens('Hi {first_name}!', values), 'Hi Ahmed!');
    });

    test('replaces every occurrence', () {
      expect(substituteTokens('{first_name} {first_name}', values),
          'Ahmed Ahmed');
    });

    test('inserts pre-formatted values verbatim', () {
      expect(substituteTokens('You have {points_balance}', values),
          'You have 1,250');
    });

    test('leaves an unknown token exactly as written', () {
      expect(substituteTokens('Hi {nickname}!', values), 'Hi {nickname}!',
          reason: 'a newer server may know tokens this SDK does not; blanking '
              'them would silently delete copy');
    });

    test('leaves malformed braces alone', () {
      expect(substituteTokens('a { b } {2} {', values), 'a { b } {2} {');
    });

    test('an empty map changes nothing', () {
      expect(substituteTokens('Hi {first_name}', const <String, String>{}),
          'Hi {first_name}');
    });
  });

  group('messageHasTokens', () {
    test('is false for plain copy', () {
      expect(messageHasTokens(message(header: 'Hi', body: 'there')), isFalse);
    });

    test('finds a token in the header', () {
      expect(messageHasTokens(message(header: 'Hi {first_name}')), isTrue);
    });

    test('finds a token in the body', () {
      expect(messageHasTokens(message(body: '{points_balance} points')), isTrue);
    });

    test('finds a token in a button label', () {
      expect(messageHasTokens(message(buttons: [button('Spend {points_balance}')])),
          isTrue);
    });

    test('a bare brace with no token name does not count', () {
      expect(messageHasTokens(message(body: 'a { b')), isFalse);
    });
  });

  group('substituteInto', () {
    test('rewrites header, body and button labels together', () {
      final result = substituteInto(
        message(
          header: 'Hi {first_name}',
          body: 'You have {points_balance}',
          buttons: [button('Spend {points_balance}')],
        ),
        const <String, String>{'first_name': 'Ahmed', 'points_balance': '1,250'},
      );

      expect(result.header, 'Hi Ahmed');
      expect(result.body, 'You have 1,250');
      expect(result.buttons.single.text, 'Spend 1,250');
    });

    test('leaves everything else identical', () {
      final original = message(header: 'Hi {first_name}');
      final result =
          substituteInto(original, const <String, String>{'first_name': 'A'});

      expect(result.id, original.id);
      expect(result.type, original.type);
      expect(result.layout, original.layout);
      expect(result.showCloseButton, original.showCloseButton);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/in_app_messaging/token_substitution_test.dart`
Expected: FAIL — the library does not exist.

- [ ] **Step 3: Add the narrow copy methods**

In `lib/in_app_messaging/models/in_app_message.dart`, inside `GameballMessageButton`, after the fields:

```dart
  /// The same button with different label text.
  ///
  /// Exists for personalisation, which rewrites labels just before display.
  GameballMessageButton withText(String newText) => GameballMessageButton(
        id: id,
        text: newText,
        action: action,
        style: style,
      );
```

Inside `GameballInAppMessage`, after the fields:

```dart
  /// The same message with different text.
  ///
  /// Deliberately narrow rather than a general `copyWith`: personalisation is the
  /// only thing that rewrites a parsed message, and it has no business changing
  /// the layout, the action or the styling. A full copyWith would invite exactly
  /// that.
  GameballInAppMessage withText({
    String? header,
    String? body,
    List<GameballMessageButton>? buttons,
  }) =>
      GameballInAppMessage(
        id: id,
        type: type,
        body: body ?? this.body,
        header: header ?? this.header,
        imageUrl: imageUrl,
        clickAction: clickAction,
        showCloseButton: showCloseButton,
        dismissOnScrimTap: dismissOnScrimTap,
        autoDismissAfter: autoDismissAfter,
        layout: layout,
        orientation: orientation,
        slidePosition: slidePosition,
        iconUrl: iconUrl,
        buttons: buttons ?? this.buttons,
        extras: extras,
        style: style,
      );
```

- [ ] **Step 4: Write the substitution library**

Create `lib/in_app_messaging/personalisation/token_substitution.dart`:

```dart
import '../models/in_app_message.dart';

/// Matches `{token_name}` — a single brace pair around a bare identifier.
///
/// Deliberately strict. `{ spaced }`, `{2}` and a lone `{` are not tokens, and
/// treating them as such would let ordinary copy be mangled by a value map.
final RegExp _token = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Whether [message] carries anything worth fetching variables for.
///
/// Checked before the network call, so a message with no tokens — which today is
/// every message the backend serves — costs nothing.
bool messageHasTokens(GameballInAppMessage message) {
  return _hasToken(message.header) ||
      _hasToken(message.body) ||
      message.buttons.any((b) => _hasToken(b.text));
}

bool _hasToken(String? text) =>
    text != null && text.contains('{') && _token.hasMatch(text);

/// Replaces every `{token}` in [text] that [values] knows.
///
/// A token with no matching key is **left exactly as written**. A newer server
/// may know tokens this SDK's map does not, and blanking them would silently
/// delete copy a marketer wrote.
String substituteTokens(String text, Map<String, String> values) {
  if (values.isEmpty || !text.contains('{')) return text;
  return text.replaceAllMapped(_token, (match) {
    final name = match.group(1)!;
    return values[name] ?? match.group(0)!;
  });
}

/// [message] with its text personalised.
///
/// Applies to the header, the body and every button label. `html` and the
/// EmailCapture strings are skipped because those message types are not
/// rendered; when they are, this is the function they use.
GameballInAppMessage substituteInto(
  GameballInAppMessage message,
  Map<String, String> values,
) {
  if (values.isEmpty) return message;

  return message.withText(
    header: message.header == null
        ? null
        : substituteTokens(message.header!, values),
    body: message.body == null ? null : substituteTokens(message.body!, values),
    buttons: message.buttons
        .map((b) => b.withText(substituteTokens(b.text, values)))
        .toList(growable: false),
  );
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/in_app_messaging/token_substitution_test.dart`
Expected: PASS, 13 tests.

- [ ] **Step 6: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(iam): substitute personalisation tokens into a message"
```

---

## Task 8: Resolve variables before display

**Files:**
- Modify: `lib/in_app_messaging/in_app_messaging_service.dart`
- Modify: `lib/gameball_sdk.dart`
- Test: `test/in_app_messaging/in_app_messaging_service_test.dart`

**Interfaces:**
- Consumes: `VariableSource`, `CachingVariableSource`, `messageHasTokens`, `substituteInto`, `fetchMessageVariablesRequest`.
- Produces: `InAppMessagingService` gains `required VariableSource variables` and `Duration variableTimeout = defaultVariableTimeout`; `const Duration defaultVariableTimeout = Duration(seconds: 2)`; `GameballApp.debugVariableSource`.

- [ ] **Step 1: Write the failing test**

Add a fake to `test/in_app_messaging/in_app_messaging_service_test.dart`, beside `FakeArtworkPrefetcher`:

```dart
class FakeVariableSource implements VariableSource {
  Map<String, String> values = const <String, String>{};
  bool hang = false;
  int fetches = 0;

  @override
  Future<Map<String, String>> fetch(String customerId) {
    fetches++;
    if (hang) return Completer<Map<String, String>>().future;
    return Future<Map<String, String>>.value(values);
  }
}
```

Add `variables` to the builder's record type, construct it, pass it to the service along with `variableTimeout: variableTimeout ?? defaultVariableTimeout`, add the `Duration? variableTimeout` parameter to `build({...})`, and return it in the record — mirroring exactly how `prefetcher` and `prefetchTimeout` are already wired.

Then add a campaign helper that carries a token, and the group:

```dart
  group('personalisation', () {
    InAppMessageCampaign tokenCampaign(String label) => InAppMessageCampaign(
          campaignId: idFor(label),
          trigger: const GameballSessionStartTrigger(),
          message: GameballInAppMessage(
            id: 'msg_$label',
            type: GameballMessageType.modal,
            header: 'Hi {first_name}',
            body: 'You have {points_balance}',
          ),
        );

    test('a message with no token never asks for variables', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, ['msg_a']);
      expect(h.variables.fetches, 0,
          reason: 'the scan is what keeps this inert until tokens exist');
    });

    test('a token-bearing message is displayed with values substituted',
        () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{
        'first_name': 'Ahmed',
        'points_balance': '1,250',
      };

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.variables.fetches, 1);
      expect(h.presenter.shownHeaders, ['Hi Ahmed']);
      expect(h.presenter.shownBodies, ['You have 1,250']);
    });

    test('a failed fetch displays the text already held', () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{};

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.presenter.shownHeaders, ['Hi {first_name}'],
          reason: 'never block or drop a display on this call');
    });

    test('a hung fetch is bounded and the message still displays', () async {
      final h = build(
        campaigns: [tokenCampaign('promo')],
        variableTimeout: const Duration(milliseconds: 50),
      );
      h.variables.hang = true;

      await h.service.start(customerId: 'c1');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(h.presenter.shownHeaders, ['Hi {first_name}']);
    });

    test('the impression is still logged once, at display', () async {
      final h = build(campaigns: [tokenCampaign('promo')]);
      h.variables.values = const <String, String>{'first_name': 'Ahmed'};

      await h.service.start(customerId: 'c1');
      await pumpEventQueue();

      expect(h.analytics.impressions, ['promo']);
    });

    test('a trigger during the fetch does not stack a second message',
        () async {
      final h = build(campaigns: [tokenCampaign('promo'), campaign('other')]);
      h.variables.hang = true;

      await h.service.start(customerId: 'c1');
      h.service.onCustomEvent('anything');
      await pumpEventQueue();

      expect(h.presenter.shownMessageIds, isEmpty,
          reason: 'one is still resolving; the other must not jump the queue');
    });
  });
```

`FakePresenter` needs to record what it was shown. Add beside `shownMessageIds`:

```dart
  final List<String?> shownHeaders = <String?>[];
  final List<String?> shownBodies = <String?>[];
```

and inside `present`, next to `shownMessageIds.add(message.id);`:

```dart
    shownHeaders.add(message.header);
    shownBodies.add(message.body);
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/in_app_messaging/in_app_messaging_service_test.dart`
Expected: FAIL — `VariableSource` is not imported and the service has no `variables` parameter.

- [ ] **Step 3: Add the constant, the field and the constructor parameter**

In `lib/in_app_messaging/in_app_messaging_service.dart`, add the import:

```dart
import 'personalisation/token_substitution.dart';
import 'personalisation/variable_source.dart';
```

Beneath `defaultArtworkPrefetchTimeout`:

```dart
/// How long to wait for current personalisation values before displaying.
///
/// The document's figure. Bounded because a message must never be blocked or
/// dropped by this call — on timeout the sync-time text is displayed, which is
/// the same text the customer would have seen with no personalisation at all.
const Duration defaultVariableTimeout = Duration(seconds: 2);
```

Add `required VariableSource variables,` to the constructor beside `prefetcher`, `this.variableTimeout = defaultVariableTimeout,` beside `prefetchTimeout`, `_variables = variables,` to the initialiser list, and the field:

```dart
  final VariableSource _variables;
```

plus:

```dart
  /// How long to wait for personalisation values before displaying anyway.
  final Duration variableTimeout;

  /// Guards the window between deciding to display and actually displaying.
  ///
  /// Only a token-bearing message opens that window, by awaiting its variables.
  /// Without this, a trigger firing during the await would present a second
  /// message on top of the first.
  bool _presentationInFlight = false;
```

- [ ] **Step 4: Split the display path**

Replace the guard block at the top of `_tryPresent` and route token-bearing messages through the async path:

```dart
  void _tryPresent(InAppMessageCampaign campaign) {
    if (_isHostWidgetOpen()) {
      _defer(campaign, 'the Gameball widget is open');
      return;
    }
    if (_presenter.isShowing) {
      _defer(campaign, 'another message is showing');
      return;
    }
    if (_presentationInFlight) {
      _defer(campaign, 'another message is resolving its personalisation');
      return;
    }

    // The common path, and today the only one: no tokens means nothing to fetch,
    // so display stays synchronous and byte-identical to before personalisation
    // existed.
    if (!messageHasTokens(campaign.message)) {
      _present(campaign, campaign.message);
      return;
    }

    _presentationInFlight = true;
    unawaited(_resolveThenPresent(campaign));
  }

  /// Fetches current values, then displays — bounded, and never at the cost of
  /// the display itself.
  Future<void> _resolveThenPresent(InAppMessageCampaign campaign) async {
    final audience = _audience;
    var message = campaign.message;

    try {
      if (audience is CustomerAudience) {
        final values = await _variables
            .fetch(audience.customerId)
            .timeout(variableTimeout);
        message = substituteInto(message, values);
      }
    } on TimeoutException {
      iamLog('personalisation for campaign "${campaign.campaignId}" did not '
          'arrive within ${variableTimeout.inMilliseconds}ms; displaying the '
          'text from the last sync');
    } catch (error) {
      iamLog('personalisation for campaign "${campaign.campaignId}" failed '
          '($error); displaying the text from the last sync');
    } finally {
      _presentationInFlight = false;
    }

    // Re-checked rather than trusted: the screen can change during the await.
    if (!isStarted) return;
    if (_isHostWidgetOpen() || _presenter.isShowing) {
      _defer(campaign, 'the screen was taken while personalisation resolved');
      return;
    }

    _present(campaign, message);
  }
```

- [ ] **Step 5: Extract `_present`**

Rename the remainder of the old `_tryPresent` — everything from `var shown = false;` to the closing brace — into a new method, taking the message to display:

```dart
  /// Draws [message] for [campaign], and wires its callbacks.
  ///
  /// Takes the message separately from the campaign because personalisation
  /// displays a substituted copy while every piece of bookkeeping — caps,
  /// impressions, the pending slot — still keys on the campaign.
  void _present(InAppMessageCampaign campaign, GameballInAppMessage message) {
```

Inside it, change the presenter call's first argument to `message: message,` and leave every `campaign.` reference untouched. The `if (!presented)` block at the end stays exactly as it is.

- [ ] **Step 6: Clear the cache on customer change and stop**

In `_resetFor`, beside `_artworkReady = const <int>{};`:

```dart
    _presentationInFlight = false;
```

In `stop()`, beside the same line, add both:

```dart
    _presentationInFlight = false;
```

and, since `VariableSource` has no `clear()` on the interface, cast defensively where the cache lives — in `stop()`:

```dart
    final variables = _variables;
    if (variables is CachingVariableSource) variables.clear();
```

Do the same in `onCustomerChanged` before the refetch, so one customer's values can never personalise another's message.

- [ ] **Step 7: Construct it in the SDK**

In `lib/gameball_sdk.dart`, add the imports:

```dart
import 'in_app_messaging/personalisation/variable_source.dart';
import 'package:gameball_sdk/network/request_calls/fetch_message_variables_request.dart';
```

Add the debug seam beside `debugArtworkPrefetcher`:

```dart
  /// Replaces the personalisation source. Tests only — never set this in an app.
  @visibleForTesting
  static VariableSource? debugVariableSource;
```

Add to the service construction, beside `prefetcher:`:

```dart
      // Personalisation values, fetched just before display and cached briefly.
      // Inert until the backend sends text that still contains {tokens}.
      variables: debugVariableSource ??
          CachingVariableSource(fetcher: _fetchMessageVariables),
```

And add the sender beside `_sendInAppMessageEvents`:

```dart
  static Future<Map<String, String>> _fetchMessageVariables(
    String customerId,
  ) async {
    if (isNullOrEmpty(_apiKey)) return const <String, String>{};
    return fetchMessageVariablesRequest(
      customerId: customerId,
      apiKey: _apiKey,
      lang: handleLanguage(_lang, _customerPreferredLanguage),
      customApiPrefix: _apiPrefix,
      sessionToken: _sessionToken,
    );
  }
```

- [ ] **Step 8: Run the service tests**

Run: `flutter test test/in_app_messaging/in_app_messaging_service_test.dart`
Expected: PASS, 82 tests.

- [ ] **Step 9: Fix the end-to-end suite**

Run: `flutter test test/in_app_messaging/end_to_end_test.dart`

This should pass untouched: the stub fixture carries no `{tokens}`, so `messageHasTokens` is false
and the real source is never called. Add the double anyway — it makes the suite's independence from
the network explicit rather than incidental, and it is one line to set. Beside `_ReadyArtwork`:

```dart
class _NoVariables implements VariableSource {
  @override
  Future<Map<String, String>> fetch(String customerId) async =>
      const <String, String>{};
}
```

- [ ] **Step 10: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat(iam): resolve personalisation variables before display"
```

---

## Task 9: Documentation

**Files:**
- Replace: `docs/reference/backend-sdk-endpoints-reference.md`
- Modify: `docs/superpowers/specs/2026-08-10-in-app-messaging-backend-integration-design.md`
- Modify: `docs/integration/in-app-message-analytics-backend-handoff.md:176-183`
- Modify: `CHANGELOG.md`, `RELEASE_NOTES.md`, `README.md`, `MIGRATION.md`

- [ ] **Step 1: Replace the vendored reference**

```bash
cp "/Users/mostafamoaty/Downloads/sdk-endpoints-reference (2).md" \
   docs/reference/backend-sdk-endpoints-reference.md
```

- [ ] **Step 2: Annotate the superseded spec**

At the top of `docs/superpowers/specs/2026-08-10-in-app-messaging-backend-integration-design.md`, beneath the title:

```markdown
> **Superseded for anything wire-shaped** by
> [`2026-08-17-in-app-messaging-v4-migration-design.md`](2026-08-17-in-app-messaging-v4-migration-design.md).
> The endpoints, the envelope, the identity model and the trigger field names all
> changed with the V4 integrations release. The behavioural design here — triggers,
> caps, deferral, analytics semantics — still holds.
```

In its Open items table, strike through O1, O2, O7, O8, O10 and O12, each pointing at the new spec.

- [ ] **Step 3: Correct the analytics handoff document**

In `docs/integration/in-app-message-analytics-backend-handoff.md`, replace the cadence row:

```markdown
| **Cadence** | A non-empty buffer is sent after **30 seconds**, or immediately once **10 events** accumulate |
```

and the batch-size row:

```markdown
| **Batch size** | 1 to 50 events per request. The outbox holds up to 500 and flushes in chunks of 50 |
```

Both were stale — the code has flushed at 30s/10 events for some time, and chunks at 50. This document was written for the backend team, so a wrong number here describes behaviour they may have built against.

- [ ] **Step 4: Update the release documentation**

3.3.0 is unreleased, so amend rather than add a version. In `CHANGELOG.md`, under the existing `[3.3.0]` **Added** section, append:

```markdown
- 🔤 **Personalisation**: message text is refreshed with the customer's current values just before display, so points and names are not a snapshot from session start. Bounded and non-blocking — on any failure the message displays with the text it already had
```

and under **Notes**, replace the endpoint sentence:

```markdown
- In-app messaging needs the `integrations/inapp-messages` endpoints enabled for your account. Where they are not, the SDK logs the 404 and stays silent — no errors surface to the host
```

Apply the same endpoint-name correction in `RELEASE_NOTES.md` (the Availability section) and `README.md` (the In-App Messaging note). `MIGRATION.md` needs the same one-line change in its availability paragraph.

- [ ] **Step 5: Verify every documented endpoint name is current**

Run: `grep -rn "bots/inapp" --include=*.md . | grep -v docs/superpowers/specs/2026-08-10`
Expected: no results outside the superseded spec and the research references, which describe history and should keep their original wording.

- [ ] **Step 6: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze`
Expected: all pass; exactly 13 issues.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs(iam): update every document to the V4 integrations contract"
```

---

## Final verification

- [ ] **Run everything**

```bash
flutter test && flutter analyze
```

Expected: all tests pass (418 baseline plus roughly 45 new), exactly 13 analyzer issues, zero in `lib/in_app_messaging/` or `lib/network/`.

- [ ] **Re-probe alpha and confirm the fixture still matches**

```bash
export GB_ALPHA_KEY=<the alpha key>
curl -s -X POST https://api.alpha.gameball.app/api/v4.0/integrations/inapp-messages/sync \
  -H 'Content-Type: application/json' -H "ApiKey: $GB_ALPHA_KEY" \
  -d '{"customerId":"moaty-survey-7","platform":2,"locale":"en",
       "appVersion":"3.3.0","sdkVersion":"3.3.0"}' | python3 -m json.tool \
  | diff - test/fixtures/v4-sync-response.json && echo "fixture still matches live"
```

A difference is not a failure — campaigns change on alpha — but it should be understood before shipping.

- [ ] **Confirm the compatibility invariant**

Run: `flutter test test/in_app_messaging/compatibility_test.dart`
Expected: PASS. A host that never calls `startInAppMessaging` must still make no requests and store nothing.
