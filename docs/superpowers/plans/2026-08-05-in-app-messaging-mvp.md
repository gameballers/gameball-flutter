# In-App Messaging MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in in-app messaging module to the Gameball Flutter SDK that displays one message type (modal) triggered by session start and custom events, fed from a stubbed source, without changing behaviour for any existing client.

**Architecture:** A new `lib/in_app_messaging/` module behind four interfaces (source, presenter, frequency cap, analytics). A pure evaluator function does all trigger matching, cap enforcement and priority ordering with no I/O, async, UI or clock. An `OverlayEntry`-based presenter draws above all routes. Three existing SDK files gain small additive, guarded hooks that no-op until `startInAppMessaging()` is called.

**Tech Stack:** Dart 3.4+ (sealed classes, records, pattern matching), Flutter 3.44.8, `flutter_test`, existing deps only (`url_launcher`, `shared_preferences`, `webview_flutter`, `http`). No `json_serializable` for the new models — parsing rules are custom and lenient, which code generation cannot express.

**Spec:** [`docs/superpowers/specs/2026-08-05-gameball-in-app-messaging-mvp-design.md`](../specs/2026-08-05-gameball-in-app-messaging-mvp-design.md)
**Research reference:** [`docs/research/braze-in-app-messaging-reference.md`](../../research/braze-in-app-messaging-reference.md) — §n citations below point into it.

## Global Constraints

- **Branch:** `feature/in-app-messaging` in `/Users/mostafamoaty/Desktop/Gameball/gameball-flutter`. Local commits only — **do not push**.
- **Compatibility invariant:** a client who upgrades and changes nothing must observe no difference. No requests, no timers, no overlay, no state before `startInAppMessaging()`.
- **Every public type is prefixed `Gameball`** (collision safety — `gameball_sdk.dart` gains an `export`, injecting names into every existing importer's namespace). Internal, non-exported types keep short names.
- **`GameballConfig` is not modified.** No new fields.
- **No new pub dependencies.**
- **Hooks in existing methods** are wrapped in their own try/catch that logs and swallows, and are placed *outside* the existing `.then()` chains — `sendEvent` and `initializeCustomer` attach `.then()` with no `catchError`, so anything thrown inside those chains escapes as an unhandled async error.
- **Only three existing files change:** `lib/gameball_sdk.dart`, `pubspec.yaml`, `lib/utils/gameball_utils.dart`.
- **Version 3.2.0 → 3.3.0**, bumped in both `pubspec.yaml:3` and the hardcoded `getSdkVersion()` at `lib/utils/gameball_utils.dart:26`.
- **Analyzer baseline is 13 pre-existing issues** (5 in `lib/gameball_sdk.dart`, 8 in `example/lib/main.dart`). `flutter analyze` must report **exactly 13** after every task, with **zero** in `lib/in_app_messaging/`. Do not "fix" the pre-existing ones — out of scope.
- **Test baseline is zero tests.** `test/gameball_sdk_test.dart` contains only `void main() {}`.
- All commands run with `export PATH="$HOME/development/flutter/bin:$PATH"`.

## Execution log — what implementation changed (all tasks complete)

Recorded after the fact. Six things the plan did not anticipate:

1. **A real bug in `startInAppMessaging` (Task 8, found by the Task 9 tests).**
   `_inAppMessaging ??=` bound the service and its `OverlayPresenter` to the
   *first* navigator key forever. A later call with a different key — exactly
   what a hot restart does — left the presenter pointing at a dead key and
   messages silently never appeared. The presenter is now rebuilt when the key
   changes. Worst-possible failure mode for the SDK-development workflow this
   module exists to serve.
2. **A second real bug: the post-frame retry re-armed every frame (Task 7).**
   A message deferred for want of a navigator scheduled a retry which, on
   failing, scheduled another — spinning once per frame while no surface
   existed. Now guarded by `_postFrameRetryScheduled`.
3. **Two Task 7 tests were wrong, not the implementation.** Deferral is for
   blocked *display*, not cap violations: a trigger firing inside the 30-second
   floor is dropped at selection and never enters the pending slot, matching
   Braze. The floor re-validation on retry therefore guards a narrower case —
   an intervening display moving the floor while a message waits — which the
   rewritten test now builds explicitly.
4. **`(_, _)` does not compile in this package.** `pubspec.yaml` pins
   `sdk: ">=3.4.4"`, so the language version predates wildcard `_` parameters,
   even though the same syntax compiles in the sample app. Use `(_, __)`.
5. **The pre-existing missing `catchError` makes `sendEvent` untestable
   normally.** Its request failure escapes as an unhandled async error and fails
   any test that calls it. Two tests capture it in a `runZonedGuarded` and assert
   on it, documenting the defect rather than hiding it. Both carry a note to
   delete the zone if the defect is ever fixed.
6. **An extra test file: `test/in_app_messaging/end_to_end_test.dart`.** The
   plan's manual walkthrough was the only proof that the units wire together.
   This drives the whole module through its real collaborators via the public
   API, which makes stage 1 automated rather than tap-dependent — and it is what
   found deviation 1.

Also: `startInAppMessaging` requires a non-empty API key, so the sample app
needs *some* `GB_API_KEY` to demo. A placeholder is enough — MVP messages come
from the stub, so no network call is involved in in-app messaging.

## Deviations from the spec (decided while planning)

1. **A 15th file, `lib/in_app_messaging/iam_log.dart`.** The spec says diagnostics are "logged" but never says where. `GameballLogger` posts telemetry to a backend endpoint, which is wrong for per-parse diagnostics. This adds a local `iamLog()` using `dart:developer`.
2. **The evaluator skips `unsupported` message types.** The spec says such a message is "kept but skipped at display", which is ambiguous: does a lower-priority *supported* campaign then win? Resolved as **yes** — the evaluator filters unsupported out, so a usable campaign still shows. Better behaviour, and it still never burns a cap.
3. **`BackButtonListener` is wrapped conditionally.** It `assert`s when no `Router` ancestor exists, which would crash a plain `MaterialApp` in debug. It is only inserted when `Router.maybeOf(context) != null`.
4. **`Dart`'s `List.sort` is not stable**, so "ties break on response order" needs an explicit index tiebreak. See Task 4.

## File structure

| File | Responsibility |
| --- | --- |
| `lib/in_app_messaging/iam_log.dart` | Local diagnostic logging, separate from backend telemetry |
| `lib/in_app_messaging/models/in_app_message.dart` | `GameballInAppMessage`, `GameballMessageButton`, `GameballClickAction`, `GameballMessageType`, styles, `maxModalButtons` |
| `lib/in_app_messaging/models/message_trigger.dart` | `GameballMessageTrigger` sealed hierarchy + `triggerMatches` |
| `lib/in_app_messaging/models/in_app_message_campaign.dart` | `InAppMessageCampaign` (internal) |
| `lib/in_app_messaging/models/gameball_audience.dart` | `GameballAudience` sealed hierarchy |
| `lib/in_app_messaging/source/message_parser.dart` | JSON → campaigns, all lenient parsing rules |
| `lib/in_app_messaging/source/message_source.dart` | `GameballMessageSource` interface |
| `lib/in_app_messaging/source/stub_message_source.dart` | Fixture-backed source |
| `lib/in_app_messaging/evaluation/frequency_cap.dart` | `CapState`, `FrequencyCap`, `InMemoryFrequencyCap`, the 30s constant |
| `lib/in_app_messaging/evaluation/trigger_evaluator.dart` | Pure `selectCampaign` + `isWithinFloor` |
| `lib/in_app_messaging/presentation/in_app_message_modal.dart` | The modal widget |
| `lib/in_app_messaging/presentation/message_presenter.dart` | `GameballMessagePresenter` interface |
| `lib/in_app_messaging/presentation/overlay_presenter.dart` | `OverlayEntry` implementation, scrim, auto-dismiss timer |
| `lib/in_app_messaging/analytics/message_analytics.dart` | `MessageAnalytics` + `LoggingMessageAnalytics` |
| `lib/in_app_messaging/in_app_messaging_service.dart` | Orchestrator; `GameballDisplayDecision`, `GameballBeforeDisplay` |
| `lib/in_app_messaging/in_app_messaging.dart` | Barrel — public exports only |

---

## Task 1: Models, local logger, and JSON parser

**Files:**
- Create: `lib/in_app_messaging/iam_log.dart`
- Create: `lib/in_app_messaging/models/in_app_message.dart`
- Create: `lib/in_app_messaging/models/message_trigger.dart`
- Create: `lib/in_app_messaging/models/in_app_message_campaign.dart`
- Create: `lib/in_app_messaging/models/gameball_audience.dart`
- Create: `lib/in_app_messaging/source/message_parser.dart`
- Test: `test/in_app_messaging/message_parser_test.dart`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `iamLog(String)`; `GameballInAppMessage`, `GameballMessageButton`, `GameballButtonStyle`, `GameballMessageStyle`, `GameballMessageType`, `GameballClickAction`/`GameballDismissAction`/`GameballOpenUrlAction`, `maxModalButtons`; `GameballMessageTrigger`/`GameballSessionStartTrigger`/`GameballCustomEventTrigger`, `triggerMatches(campaignTrigger, occurred) -> bool`; `InAppMessageCampaign({id, trigger, priority, message})`; `GameballAudience`/`CustomerAudience(customerId)` with `toJson()`; `parseCampaignsJson(String) -> List<InAppMessageCampaign>`, `parseColor(Object?) -> Color?`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/message_parser_test.dart`:

```dart
import 'dart:ui' show Color, TextAlign;

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_parser.dart';

/// Builds a payload with one campaign, letting each test override just the
/// fields it cares about.
String payload({String campaigns = _oneModalCampaign}) => '{"campaigns":[$campaigns]}';

const _oneModalCampaign = '''
{
  "id": "cmp_a",
  "priority": 10,
  "trigger": { "type": "session_start" },
  "message": { "id": "msg_a", "type": "modal", "body": "hello" }
}
''';

void main() {
  group('parseCampaignsJson — happy path', () {
    test('parses a minimal modal campaign', () {
      final campaigns = parseCampaignsJson(payload());

      expect(campaigns, hasLength(1));
      final c = campaigns.single;
      expect(c.id, 'cmp_a');
      expect(c.priority, 10);
      expect(c.trigger, isA<GameballSessionStartTrigger>());
      expect(c.message.id, 'msg_a');
      expect(c.message.type, GameballMessageType.modal);
      expect(c.message.body, 'hello');
      expect(c.message.showCloseButton, isTrue);
      expect(c.message.autoDismissAfter, isNull);
      expect(c.message.isTestSend, isFalse);
      expect(c.message.buttons, isEmpty);
    });

    test('parses a fully populated campaign', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        {
          "id": "cmp_full",
          "priority": 100,
          "trigger": { "type": "custom_event", "eventName": "add_to_cart" },
          "message": {
            "id": "msg_full",
            "type": "modal",
            "header": "Welcome",
            "body": "You have points",
            "imageUrl": "https://cdn.example.com/a.png",
            "showCloseButton": false,
            "autoDismissAfterMs": 4000,
            "isTestSend": true,
            "buttons": [
              { "id": 7, "text": "Go", "action": { "type": "open_url", "url": "app://x", "external": true },
                "style": { "backgroundColor": "#6C4DF6", "textColor": "#FFFFFF", "borderColor": "#000000" } }
            ],
            "style": { "backgroundColor": "#FFFFFF", "headerColor": "#111111",
                       "bodyColor": "#444444", "scrimColor": "#99000000",
                       "headerAlign": "center", "bodyAlign": "start" },
            "extras": { "source": "q3" }
          }
        }
      '''));

      final m = campaigns.single.message;
      expect(campaigns.single.trigger,
          isA<GameballCustomEventTrigger>().having((t) => t.eventName, 'eventName', 'add_to_cart'));
      expect(m.header, 'Welcome');
      expect(m.imageUrl, 'https://cdn.example.com/a.png');
      expect(m.showCloseButton, isFalse);
      expect(m.autoDismissAfter, const Duration(milliseconds: 4000));
      expect(m.isTestSend, isTrue);
      expect(m.extras, {'source': 'q3'});
      expect(m.style.backgroundColor, const Color(0xFFFFFFFF));
      expect(m.style.scrimColor, const Color(0x99000000));
      expect(m.style.headerAlign, TextAlign.center);
      expect(m.style.bodyAlign, TextAlign.start);

      final b = m.buttons.single;
      expect(b.id, 7);
      expect(b.text, 'Go');
      expect(b.style.backgroundColor, const Color(0xFF6C4DF6));
      final action = b.action;
      expect(action, isA<GameballOpenUrlAction>());
      action as GameballOpenUrlAction;
      expect(action.url, 'app://x');
      expect(action.external, isTrue);
    });
  });

  group('parseCampaignsJson — leniency', () {
    test('matches enum-ish values case-insensitively', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "SESSION_START" },
          "message": { "id": "m", "type": "MODAL", "body": "b",
                       "buttons": [ { "text": "x", "action": { "type": "DISMISS" } } ] } }
      '''));

      expect(campaigns.single.message.type, GameballMessageType.modal);
      expect(campaigns.single.trigger, isA<GameballSessionStartTrigger>());
      expect(campaigns.single.message.buttons.single.action, isA<GameballDismissAction>());
    });

    test('accepts a colour as a packed ARGB int', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "style": { "backgroundColor": 4294967295 } } }
      '''));

      expect(campaigns.single.message.style.backgroundColor, const Color(0xFFFFFFFF));
    });

    test('coerces non-string extras rather than dropping them', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "extras": { "n": 42, "b": true, "s": "x" } } }
      '''));

      expect(campaigns.single.message.extras, {'n': '42', 'b': 'true', 's': 'x'});
    });

    test('keeps the first two buttons when more are provided', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "one", "action": { "type": "dismiss" } },
            { "text": "two", "action": { "type": "dismiss" } },
            { "text": "three", "action": { "type": "dismiss" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.map((b) => b.text), ['one', 'two']);
    });

    test('defaults a button id to its position when absent', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "one", "action": { "type": "dismiss" } },
            { "text": "two", "action": { "type": "dismiss" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.map((b) => b.id), [0, 1]);
    });

    test('degrades an unknown action type to dismiss', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "x", "action": { "type": "send_telepathy" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.single.action, isA<GameballDismissAction>());
    });

    test('degrades open_url with no url to dismiss', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "buttons": [
            { "text": "x", "action": { "type": "open_url" } } ] } }
      '''));

      expect(campaigns.single.message.buttons.single.action, isA<GameballDismissAction>());
    });

    test('ignores a malformed colour and leaves the field null', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b",
                       "style": { "backgroundColor": "not-a-colour" } } }
      '''));

      expect(campaigns.single.message.style.backgroundColor, isNull);
    });

    test('treats a non-positive autoDismissAfterMs as no auto-dismiss', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b", "autoDismissAfterMs": 0 } }
      '''));

      expect(campaigns.single.message.autoDismissAfter, isNull);
    });
  });

  group('parseCampaignsJson — keep but skip', () {
    test('keeps an unknown message type as unsupported', () {
      final campaigns = parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "hologram", "body": "b" } }
      '''));

      expect(campaigns, hasLength(1));
      expect(campaigns.single.message.type, GameballMessageType.unsupported);
    });
  });

  group('parseCampaignsJson — drop what can never work', () {
    test('drops a campaign with an unknown trigger type', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "any_purchase" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('drops a custom_event trigger with no eventName', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "custom_event" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('drops a campaign with no id', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('drops a message with no body', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "id": "m", "type": "modal" } }
      ''')), isEmpty);
    });

    test('drops a message with no id', () {
      expect(parseCampaignsJson(payload(campaigns: '''
        { "id": "c", "trigger": { "type": "session_start" },
          "message": { "type": "modal", "body": "b" } }
      ''')), isEmpty);
    });

    test('keeps valid campaigns alongside dropped ones', () {
      final campaigns = parseCampaignsJson(
        '{"campaigns":[$_oneModalCampaign,'
        '{"id":"bad","trigger":{"type":"any_purchase"},'
        '"message":{"id":"m","type":"modal","body":"b"}}]}',
      );

      expect(campaigns.map((c) => c.id), ['cmp_a']);
    });
  });

  group('parseCampaignsJson — never throws', () {
    test('returns empty for invalid JSON', () {
      expect(parseCampaignsJson('not json at all'), isEmpty);
    });

    test('returns empty when the root is not an object', () {
      expect(parseCampaignsJson('[1,2,3]'), isEmpty);
    });

    test('returns empty when campaigns is missing', () {
      expect(parseCampaignsJson('{}'), isEmpty);
    });

    test('returns empty when campaigns is not a list', () {
      expect(parseCampaignsJson('{"campaigns": 5}'), isEmpty);
    });

    test('skips non-object entries in campaigns', () {
      expect(parseCampaignsJson('{"campaigns": [1, "two", null]}'), isEmpty);
    });
  });

  group('parseColor', () {
    test('parses 6-digit hex as fully opaque', () {
      expect(parseColor('#6C4DF6'), const Color(0xFF6C4DF6));
    });

    test('parses 8-digit hex with alpha', () {
      expect(parseColor('#8000FF00'), const Color(0x8000FF00));
    });

    test('parses hex without a leading hash', () {
      expect(parseColor('FFFFFF'), const Color(0xFFFFFFFF));
    });

    test('parses a packed ARGB int', () {
      expect(parseColor(4278190080), const Color(0xFF000000));
    });

    test('returns null for junk', () {
      expect(parseColor('zzz'), isNull);
      expect(parseColor('#12345'), isNull);
      expect(parseColor(null), isNull);
      expect(parseColor(true), isNull);
    });
  });

  group('triggerMatches', () {
    test('matches session start to session start', () {
      expect(
        triggerMatches(const GameballSessionStartTrigger(), const GameballSessionStartTrigger()),
        isTrue,
      );
    });

    test('matches custom events with the same name', () {
      expect(
        triggerMatches(
          const GameballCustomEventTrigger('a'),
          const GameballCustomEventTrigger('a'),
        ),
        isTrue,
      );
    });

    test('does not match custom events with different names', () {
      expect(
        triggerMatches(
          const GameballCustomEventTrigger('a'),
          const GameballCustomEventTrigger('b'),
        ),
        isFalse,
      );
    });

    test('does not match across trigger types', () {
      expect(
        triggerMatches(
          const GameballSessionStartTrigger(),
          const GameballCustomEventTrigger('a'),
        ),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/message_parser_test.dart
```

Expected: FAIL — compile errors, `Target of URI doesn't exist: 'package:gameball_sdk/in_app_messaging/...'`.

- [ ] **Step 3: Create the local logger**

`lib/in_app_messaging/iam_log.dart`:

```dart
import 'dart:developer' as developer;

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from [GameballLogger], which posts telemetry to the
/// Gameball backend. Parse and evaluation diagnostics belong in the
/// integrator's console, not in a network request.
void iamLog(String message) {
  developer.log(message, name: 'GameballIAM');
}
```

- [ ] **Step 4: Create the message models**

`lib/in_app_messaging/models/in_app_message.dart`:

```dart
import 'dart:ui' show Color, TextAlign;

/// Maximum buttons a modal renders. Extra buttons in the payload are dropped.
const int maxModalButtons = 2;

/// Supported in-app message layouts.
///
/// An unrecognised wire value parses to [unsupported] rather than defaulting to
/// a real layout. Braze's closed enum with a silent `slideup` fallback shipped
/// wrong message types twice — prefer an explicit unknown over a default that
/// lies.
enum GameballMessageType { modal, unsupported }

/// What a button does when tapped.
sealed class GameballClickAction {
  const GameballClickAction();
}

/// Closes the message and does nothing else.
final class GameballDismissAction extends GameballClickAction {
  const GameballDismissAction();
}

/// Opens [url], then closes the message.
final class GameballOpenUrlAction extends GameballClickAction {
  const GameballOpenUrlAction(this.url, {this.external = false});

  final String url;

  /// Whether to force an external browser rather than the platform default.
  final bool external;
}

/// Per-button colours. A null field means "use the host's theme".
class GameballButtonStyle {
  const GameballButtonStyle({this.backgroundColor, this.textColor, this.borderColor});

  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;
}

class GameballMessageButton {
  const GameballMessageButton({
    required this.id,
    required this.text,
    required this.action,
    this.style = const GameballButtonStyle(),
  });

  /// Stable identifier used for click analytics.
  final int id;
  final String text;
  final GameballClickAction action;
  final GameballButtonStyle style;
}

/// Message-level colours and alignment. A null field means "use the host's theme".
class GameballMessageStyle {
  const GameballMessageStyle({
    this.backgroundColor,
    this.headerColor,
    this.bodyColor,
    this.scrimColor,
    this.headerAlign,
    this.bodyAlign,
  });

  final Color? backgroundColor;
  final Color? headerColor;
  final Color? bodyColor;
  final Color? scrimColor;
  final TextAlign? headerAlign;
  final TextAlign? bodyAlign;
}

/// A single in-app message, ready to render.
class GameballInAppMessage {
  const GameballInAppMessage({
    required this.id,
    required this.type,
    required this.body,
    this.header,
    this.imageUrl,
    this.showCloseButton = true,
    this.autoDismissAfter,
    this.isTestSend = false,
    this.buttons = const <GameballMessageButton>[],
    this.extras = const <String, String>{},
    this.style = const GameballMessageStyle(),
  });

  final String id;
  final GameballMessageType type;
  final String body;
  final String? header;
  final String? imageUrl;
  final bool showCloseButton;

  /// Null means the message stays until the user dismisses it.
  final Duration? autoDismissAfter;

  /// True when this was delivered as a marketer's test send.
  final bool isTestSend;

  final List<GameballMessageButton> buttons;

  /// Arbitrary key-values from the campaign, for driving app behaviour without
  /// a client release.
  final Map<String, String> extras;

  final GameballMessageStyle style;
}
```

- [ ] **Step 5: Create the trigger models**

`lib/in_app_messaging/models/message_trigger.dart`:

```dart
/// What causes a campaign to display.
///
/// Sealed so that adding a trigger type makes the compiler list every site that
/// must handle it.
sealed class GameballMessageTrigger {
  const GameballMessageTrigger();
}

/// Fires once when in-app messaging starts for a customer.
final class GameballSessionStartTrigger extends GameballMessageTrigger {
  const GameballSessionStartTrigger();
}

/// Fires when an event with this exact name is logged.
final class GameballCustomEventTrigger extends GameballMessageTrigger {
  const GameballCustomEventTrigger(this.eventName);

  final String eventName;
}

/// Whether [occurred] satisfies the [campaignTrigger] a campaign declares.
bool triggerMatches(
  GameballMessageTrigger campaignTrigger,
  GameballMessageTrigger occurred,
) {
  return switch ((campaignTrigger, occurred)) {
    (GameballSessionStartTrigger(), GameballSessionStartTrigger()) => true,
    (
      GameballCustomEventTrigger(eventName: final declared),
      GameballCustomEventTrigger(eventName: final fired),
    ) =>
      declared == fired,
    _ => false,
  };
}
```

- [ ] **Step 6: Create the campaign and audience models**

`lib/in_app_messaging/models/in_app_message_campaign.dart`:

```dart
import 'in_app_message.dart';
import 'message_trigger.dart';

/// A message plus the conditions under which it displays.
///
/// Internal: hosts never see campaigns, only the [GameballInAppMessage] inside.
class InAppMessageCampaign {
  const InAppMessageCampaign({
    required this.id,
    required this.trigger,
    required this.priority,
    required this.message,
  });

  final String id;
  final GameballMessageTrigger trigger;

  /// Higher wins when several campaigns match one trigger.
  final int priority;

  final GameballInAppMessage message;
}
```

`lib/in_app_messaging/models/gameball_audience.dart`:

```dart
/// Who messages are fetched for.
///
/// Sealed and tagged on the wire so a device-scoped variant can be added
/// without changing the request contract or any existing signature.
sealed class GameballAudience {
  const GameballAudience();

  Map<String, dynamic> toJson();
}

/// An identified customer.
final class CustomerAudience extends GameballAudience {
  const CustomerAudience(this.customerId);

  final String customerId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'customer',
        'customerId': customerId,
      };
}
```

- [ ] **Step 7: Create the parser**

`lib/in_app_messaging/source/message_parser.dart`:

```dart
import 'dart:convert';
import 'dart:ui' show Color, TextAlign;

import '../iam_log.dart';
import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';

/// Parses a message-source payload into campaigns.
///
/// Never throws. The rule is: drop what can never work, keep-but-skip what a
/// future SDK version might support, and log every decision.
List<InAppMessageCampaign> parseCampaignsJson(String rawJson) {
  Object? decoded;
  try {
    decoded = jsonDecode(rawJson);
  } catch (error) {
    iamLog('parse failed: payload is not valid JSON ($error)');
    return const <InAppMessageCampaign>[];
  }

  if (decoded is! Map<String, dynamic>) {
    iamLog('parse failed: payload root is not an object');
    return const <InAppMessageCampaign>[];
  }

  final campaignsJson = decoded['campaigns'];
  if (campaignsJson is! List) {
    iamLog('parse failed: "campaigns" is missing or not a list');
    return const <InAppMessageCampaign>[];
  }

  final campaigns = <InAppMessageCampaign>[];
  for (final entry in campaignsJson) {
    if (entry is! Map<String, dynamic>) {
      iamLog('campaign skipped: entry is not an object');
      continue;
    }
    final campaign = _parseCampaign(entry);
    if (campaign != null) {
      campaigns.add(campaign);
    }
  }
  return campaigns;
}

InAppMessageCampaign? _parseCampaign(Map<String, dynamic> json) {
  final id = _asString(json['id']);
  if (id == null || id.isEmpty) {
    iamLog('campaign dropped: missing "id"');
    return null;
  }

  final trigger = _parseTrigger(json['trigger'], id);
  if (trigger == null) {
    return null; // already logged
  }

  final messageJson = json['message'];
  if (messageJson is! Map<String, dynamic>) {
    iamLog('campaign "$id" dropped: "message" is missing or not an object');
    return null;
  }

  final message = _parseMessage(messageJson, id);
  if (message == null) {
    return null; // already logged
  }

  return InAppMessageCampaign(
    id: id,
    trigger: trigger,
    priority: _asInt(json['priority']) ?? 0,
    message: message,
  );
}

GameballMessageTrigger? _parseTrigger(Object? json, String campaignId) {
  if (json is! Map<String, dynamic>) {
    iamLog('campaign "$campaignId" dropped: "trigger" is missing or not an object');
    return null;
  }

  final type = _asString(json['type'])?.toLowerCase();
  switch (type) {
    case 'session_start':
      return const GameballSessionStartTrigger();
    case 'custom_event':
      final eventName = _asString(json['eventName']);
      if (eventName == null || eventName.isEmpty) {
        iamLog('campaign "$campaignId" dropped: custom_event trigger has no "eventName"');
        return null;
      }
      return GameballCustomEventTrigger(eventName);
    default:
      // Expected steady state, not an edge case: the backend supports more
      // trigger types than this SDK version. Name both so "why didn't my
      // campaign fire" is answerable from the log alone.
      iamLog('campaign "$campaignId" dropped: unsupported trigger type "$type" '
          '(this SDK supports session_start, custom_event)');
      return null;
  }
}

GameballInAppMessage? _parseMessage(Map<String, dynamic> json, String campaignId) {
  final id = _asString(json['id']);
  if (id == null || id.isEmpty) {
    iamLog('campaign "$campaignId" dropped: message has no "id"');
    return null;
  }

  final body = _asString(json['body']);
  if (body == null || body.isEmpty) {
    iamLog('campaign "$campaignId" dropped: message "$id" has no "body"');
    return null;
  }

  final typeName = _asString(json['type'])?.toLowerCase();
  final type = switch (typeName) {
    'modal' => GameballMessageType.modal,
    _ => GameballMessageType.unsupported,
  };
  if (type == GameballMessageType.unsupported) {
    iamLog('message "$id" has unsupported type "$typeName" — kept, but this SDK '
        'version will not display it');
  }

  final autoMs = _asInt(json['autoDismissAfterMs']);

  return GameballInAppMessage(
    id: id,
    type: type,
    body: body,
    header: _asString(json['header']),
    imageUrl: _asString(json['imageUrl']),
    showCloseButton: _asBool(json['showCloseButton']) ?? true,
    autoDismissAfter:
        (autoMs != null && autoMs > 0) ? Duration(milliseconds: autoMs) : null,
    isTestSend: _asBool(json['isTestSend']) ?? false,
    buttons: _parseButtons(json['buttons'], id),
    extras: _parseExtras(json['extras']),
    style: _parseMessageStyle(json['style']),
  );
}

List<GameballMessageButton> _parseButtons(Object? json, String messageId) {
  if (json is! List) {
    return const <GameballMessageButton>[];
  }

  final buttons = <GameballMessageButton>[];
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) {
      iamLog('message "$messageId": button skipped, entry is not an object');
      continue;
    }
    final text = _asString(entry['text']);
    if (text == null || text.isEmpty) {
      iamLog('message "$messageId": button dropped, missing "text"');
      continue;
    }
    buttons.add(GameballMessageButton(
      // Default to position so analytics still distinguishes buttons.
      id: _asInt(entry['id']) ?? buttons.length,
      text: text,
      action: _parseAction(entry['action'], messageId),
      style: _parseButtonStyle(entry['style']),
    ));
  }

  if (buttons.length > maxModalButtons) {
    iamLog('message "$messageId": ${buttons.length} buttons provided, keeping '
        'the first $maxModalButtons');
    return buttons.sublist(0, maxModalButtons);
  }
  return buttons;
}

GameballClickAction _parseAction(Object? json, String messageId) {
  if (json is! Map<String, dynamic>) {
    return const GameballDismissAction();
  }

  final type = _asString(json['type'])?.toLowerCase();
  switch (type) {
    case 'dismiss':
      return const GameballDismissAction();
    case 'open_url':
      final url = _asString(json['url']);
      if (url == null || url.isEmpty) {
        iamLog('message "$messageId": open_url action has no "url", using dismiss');
        return const GameballDismissAction();
      }
      return GameballOpenUrlAction(url, external: _asBool(json['external']) ?? false);
    default:
      // A working close beats a dead button.
      iamLog('message "$messageId": unsupported action type "$type", using dismiss');
      return const GameballDismissAction();
  }
}

GameballButtonStyle _parseButtonStyle(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const GameballButtonStyle();
  }
  return GameballButtonStyle(
    backgroundColor: parseColor(json['backgroundColor']),
    textColor: parseColor(json['textColor']),
    borderColor: parseColor(json['borderColor']),
  );
}

GameballMessageStyle _parseMessageStyle(Object? json) {
  if (json is! Map<String, dynamic>) {
    return const GameballMessageStyle();
  }
  return GameballMessageStyle(
    backgroundColor: parseColor(json['backgroundColor']),
    headerColor: parseColor(json['headerColor']),
    bodyColor: parseColor(json['bodyColor']),
    scrimColor: parseColor(json['scrimColor']),
    headerAlign: _parseAlign(json['headerAlign']),
    bodyAlign: _parseAlign(json['bodyAlign']),
  );
}

Map<String, String> _parseExtras(Object? json) {
  if (json is! Map) {
    return const <String, String>{};
  }
  final extras = <String, String>{};
  json.forEach((key, value) {
    if (key is String && value != null) {
      // Coerced rather than dropped. Braze silently discards non-string extras,
      // which loses campaign data with no diagnostic.
      extras[key] = value is String ? value : value.toString();
    }
  });
  return extras;
}

/// Parses a colour from a hex string (`#RRGGBB` or `#AARRGGBB`, hash optional)
/// or from a packed ARGB integer.
///
/// The integer form exists so a Braze-shaped payload still renders correctly —
/// Braze encodes colours as packed ARGB ints, and the backend may follow suit.
Color? parseColor(Object? value) {
  if (value is int) {
    return Color(value);
  }
  if (value is! String) {
    return null;
  }

  var hex = value.trim();
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  if (hex.length != 8) {
    iamLog('ignoring malformed colour "$value"');
    return null;
  }

  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    iamLog('ignoring malformed colour "$value"');
    return null;
  }
  return Color(parsed);
}

TextAlign? _parseAlign(Object? value) {
  return switch (_asString(value)?.toLowerCase()) {
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    'center' => TextAlign.center,
    'start' => TextAlign.start,
    'end' => TextAlign.end,
    _ => null,
  };
}

String? _asString(Object? value) => value is String ? value : null;

bool? _asBool(Object? value) => value is bool ? value : null;

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/message_parser_test.dart
```

Expected: PASS, all tests.

- [ ] **Step 9: Verify the analyzer baseline is unchanged**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter analyze 2>&1 | tail -3
flutter analyze 2>&1 | grep -c 'in_app_messaging' || echo "0 issues in the new module"
```

Expected: `13 issues found.` and zero mentioning `in_app_messaging`.

- [ ] **Step 10: Commit**

```bash
git add lib/in_app_messaging test/in_app_messaging
git commit -m "Add in-app message models and a lenient JSON parser

Models are sealed where a variant will be added later (trigger, click action,
audience) so the compiler flags every site that must handle a new case.

The parser never throws. It drops campaigns that can never work (unknown
trigger type, missing id or body), keeps unknown message types as unsupported
so a newer SDK can display them, and degrades rather than discards where a
degraded result is still useful: an unknown action becomes dismiss, extras are
coerced to strings instead of dropped, and colours parse from either a hex
string or a packed ARGB int so a Braze-shaped payload still renders."
```

---

## Task 2: Message source and stub fixture

**Files:**
- Create: `lib/in_app_messaging/source/message_source.dart`
- Create: `lib/in_app_messaging/source/stub_message_source.dart`
- Test: `test/in_app_messaging/stub_message_source_test.dart`

**Interfaces:**
- Consumes: `parseCampaignsJson(String) -> List<InAppMessageCampaign>`, `GameballAudience`, `InAppMessageCampaign`, `GameballCustomEventTrigger`, `GameballSessionStartTrigger`
- Produces: `abstract class GameballMessageSource { Future<List<InAppMessageCampaign>> fetch(GameballAudience audience); }`; `StubMessageSource({String? json})`; `const String stubCampaignsJson`; `const String stubCartEventName = 'add_to_cart'`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/stub_message_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/source/stub_message_source.dart';

void main() {
  const audience = CustomerAudience('customer-1');

  test('the built-in fixture parses into two usable campaigns', () async {
    final campaigns = await StubMessageSource().fetch(audience);

    expect(campaigns, hasLength(2));
    for (final c in campaigns) {
      expect(c.message.type, GameballMessageType.modal,
          reason: 'the fixture must only contain displayable messages');
    }
  });

  test('the fixture covers both supported trigger types', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final triggers = campaigns.map((c) => c.trigger);

    expect(triggers.whereType<GameballSessionStartTrigger>(), hasLength(1));
    expect(
      triggers.whereType<GameballCustomEventTrigger>().single.eventName,
      stubCartEventName,
    );
  });

  test('the session-start campaign exercises header, image and two buttons', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final sessionStart = campaigns
        .firstWhere((c) => c.trigger is GameballSessionStartTrigger)
        .message;

    expect(sessionStart.header, isNotNull);
    expect(sessionStart.imageUrl, isNotNull);
    expect(sessionStart.buttons, hasLength(2));
    expect(sessionStart.buttons.map((b) => b.action).whereType<GameballOpenUrlAction>(),
        hasLength(1));
    expect(sessionStart.buttons.map((b) => b.action).whereType<GameballDismissAction>(),
        hasLength(1));
  });

  test('priorities are distinct so ordering is observable', () async {
    final campaigns = await StubMessageSource().fetch(audience);
    final priorities = campaigns.map((c) => c.priority).toSet();

    expect(priorities, hasLength(campaigns.length));
  });

  test('an injected payload replaces the fixture', () async {
    final source = StubMessageSource(json: '''
      {"campaigns":[{"id":"only","priority":1,"trigger":{"type":"session_start"},
        "message":{"id":"m","type":"modal","body":"b"}}]}
    ''');

    final campaigns = await source.fetch(audience);

    expect(campaigns.single.id, 'only');
  });

  test('an unparseable injected payload yields no campaigns', () async {
    final campaigns = await StubMessageSource(json: 'garbage').fetch(audience);

    expect(campaigns, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/stub_message_source_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../source/stub_message_source.dart'`.

- [ ] **Step 3: Create the source interface**

`lib/in_app_messaging/source/message_source.dart`:

```dart
import '../models/gameball_audience.dart';
import '../models/in_app_message_campaign.dart';

/// Where campaigns come from.
///
/// Internal: not exported to hosts. The MVP ships [StubMessageSource]; an HTTP
/// implementation replaces only the transport, reusing `parseCampaignsJson`.
abstract class GameballMessageSource {
  /// Fetches every campaign currently eligible for [audience].
  ///
  /// Implementations may throw; the caller treats a failure as "no campaigns".
  Future<List<InAppMessageCampaign>> fetch(GameballAudience audience);
}
```

- [ ] **Step 4: Create the stub source and fixture**

`lib/in_app_messaging/source/stub_message_source.dart`:

```dart
import '../models/gameball_audience.dart';
import '../models/in_app_message_campaign.dart';
import 'message_parser.dart';
import 'message_source.dart';

/// The custom event the stub's cart campaign listens for. The sample app
/// already logs this event from its product details screen.
const String stubCartEventName = 'add_to_cart';

/// A stand-in payload shaped exactly like the response the backend will return.
///
/// Held as a raw JSON string, not as constructed objects, so the real parsing
/// rules are exercised from day one. When the endpoint lands, only the
/// transport changes — the parser and its tests are untouched.
const String stubCampaignsJson = '''
{
  "campaigns": [
    {
      "id": "cmp_welcome_modal",
      "priority": 100,
      "trigger": { "type": "session_start" },
      "message": {
        "id": "msg_welcome_v1",
        "type": "modal",
        "header": "Welcome back!",
        "body": "You have 1,250 points ready to redeem.",
        "imageUrl": "https://cdn.gameball.co/campaigns/hero.png",
        "showCloseButton": true,
        "autoDismissAfterMs": null,
        "isTestSend": false,
        "buttons": [
          {
            "id": 0,
            "text": "Later",
            "action": { "type": "dismiss" },
            "style": {
              "backgroundColor": "#EEEEEE",
              "textColor": "#111111",
              "borderColor": "#DDDDDD"
            }
          },
          {
            "id": 1,
            "text": "Redeem",
            "action": { "type": "open_url", "url": "https://gameball.co", "external": false },
            "style": {
              "backgroundColor": "#6C4DF6",
              "textColor": "#FFFFFF",
              "borderColor": "#6C4DF6"
            }
          }
        ],
        "style": {
          "backgroundColor": "#FFFFFF",
          "headerColor": "#111111",
          "bodyColor": "#444444",
          "scrimColor": "#99000000",
          "headerAlign": "center",
          "bodyAlign": "start"
        },
        "extras": { "campaignSource": "loyalty-q3" }
      }
    },
    {
      "id": "cmp_cart_nudge",
      "priority": 50,
      "trigger": { "type": "custom_event", "eventName": "$stubCartEventName" },
      "message": {
        "id": "msg_cart_v1",
        "type": "modal",
        "body": "Add one more item for 2x points.",
        "showCloseButton": true,
        "buttons": []
      }
    }
  ]
}
''';

/// Serves campaigns from a fixture instead of the network.
///
/// Used until the backend endpoint exists. Tests inject [json] to control the
/// payload.
class StubMessageSource implements GameballMessageSource {
  StubMessageSource({String? json}) : _json = json ?? stubCampaignsJson;

  final String _json;

  @override
  Future<List<InAppMessageCampaign>> fetch(GameballAudience audience) async {
    return parseCampaignsJson(_json);
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/
```

Expected: PASS, both test files.

- [ ] **Step 6: Verify the analyzer baseline is unchanged**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter analyze 2>&1 | tail -3
```

Expected: `13 issues found.`

- [ ] **Step 7: Commit**

```bash
git add lib/in_app_messaging/source test/in_app_messaging/stub_message_source_test.dart
git commit -m "Add message source interface and fixture-backed stub

The fixture is a raw JSON string rather than constructed objects, so the real
parsing rules are exercised from day one and swapping in an HTTP source later
changes only the transport.

It deliberately covers both supported trigger types, distinct priorities, and a
message with header, image and two buttons of differing action types, so the
evaluator and presenter have something meaningful to work against."
```

---

## Task 3: Frequency cap

**Files:**
- Create: `lib/in_app_messaging/evaluation/frequency_cap.dart`
- Test: `test/in_app_messaging/frequency_cap_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `const Duration minimumIntervalBetweenDisplays = Duration(seconds: 30)`; `class CapState({required Set<String> shownCampaignIds, required DateTime? lastDisplayAt})`; `abstract class FrequencyCap { Future<void> load(); CapState snapshot(); void recordDisplay(String campaignId, DateTime at); void reset(); }`; `class InMemoryFrequencyCap implements FrequencyCap`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/frequency_cap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 5, 12);

  test('the documented floor is 30 seconds', () {
    expect(minimumIntervalBetweenDisplays, const Duration(seconds: 30));
  });

  test('a fresh cap has shown nothing and no last display', () {
    final snapshot = InMemoryFrequencyCap().snapshot();

    expect(snapshot.shownCampaignIds, isEmpty);
    expect(snapshot.lastDisplayAt, isNull);
  });

  test('load completes for the in-memory implementation', () async {
    await expectLater(InMemoryFrequencyCap().load(), completes);
  });

  test('recording a display makes it visible in the next snapshot', () {
    final cap = InMemoryFrequencyCap()..recordDisplay('cmp_a', t0);

    final snapshot = cap.snapshot();
    expect(snapshot.shownCampaignIds, {'cmp_a'});
    expect(snapshot.lastDisplayAt, t0);
  });

  test('lastDisplayAt tracks the most recent display across campaigns', () {
    final cap = InMemoryFrequencyCap()
      ..recordDisplay('cmp_a', t0)
      ..recordDisplay('cmp_b', t0.add(const Duration(minutes: 5)));

    final snapshot = cap.snapshot();
    expect(snapshot.shownCampaignIds, {'cmp_a', 'cmp_b'});
    expect(snapshot.lastDisplayAt, t0.add(const Duration(minutes: 5)),
        reason: 'the floor is global, so only the latest display matters');
  });

  test('reset clears both shown ids and the last display', () {
    final cap = InMemoryFrequencyCap()
      ..recordDisplay('cmp_a', t0)
      ..reset();

    final snapshot = cap.snapshot();
    expect(snapshot.shownCampaignIds, isEmpty);
    expect(snapshot.lastDisplayAt, isNull);
  });

  test('a snapshot does not change when the cap is mutated afterwards', () {
    final cap = InMemoryFrequencyCap()..recordDisplay('cmp_a', t0);
    final snapshot = cap.snapshot();

    cap.recordDisplay('cmp_b', t0.add(const Duration(seconds: 1)));

    expect(snapshot.shownCampaignIds, {'cmp_a'},
        reason: 'the evaluator must see a stable view of cap state');
  });

  test('a snapshot cannot be mutated by its holder', () {
    final snapshot = (InMemoryFrequencyCap()..recordDisplay('cmp_a', t0)).snapshot();

    expect(() => snapshot.shownCampaignIds.add('cmp_b'), throwsUnsupportedError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/frequency_cap_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../evaluation/frequency_cap.dart'`.

- [ ] **Step 3: Write the implementation**

`lib/in_app_messaging/evaluation/frequency_cap.dart`:

```dart
/// Minimum interval between **any** two message displays.
///
/// Global, not per-campaign — which is why [CapState] carries a single
/// [CapState.lastDisplayAt]. Matches Braze's default `triggerMinimumTimeInterval`.
const Duration minimumIntervalBetweenDisplays = Duration(seconds: 30);

/// An immutable view of display history, for the pure evaluator to read.
class CapState {
  const CapState({required this.shownCampaignIds, required this.lastDisplayAt});

  /// Campaigns already displayed and therefore not eligible again.
  final Set<String> shownCampaignIds;

  /// When the most recent message was displayed, or null if none has been.
  final DateTime? lastDisplayAt;
}

/// Tracks what has been shown, so the evaluator can enforce caps.
///
/// [load] runs once at start and the implementation keeps its state in memory
/// thereafter, so [snapshot] stays synchronous. That is what lets the evaluator
/// remain a pure function once a persisted implementation is added.
abstract class FrequencyCap {
  Future<void> load();

  CapState snapshot();

  /// Records that [campaignId] was displayed at [at].
  ///
  /// Called at impression, never at selection — a deferred or suppressed
  /// message must not burn its slot.
  void recordDisplay(String campaignId, DateTime at);

  void reset();
}

/// Caps that live for one app run. Nothing survives a restart.
class InMemoryFrequencyCap implements FrequencyCap {
  final Set<String> _shown = <String>{};
  DateTime? _lastDisplayAt;

  @override
  Future<void> load() async {
    // Nothing to load; state begins empty for every run.
  }

  @override
  CapState snapshot() => CapState(
        shownCampaignIds: Set<String>.unmodifiable(_shown),
        lastDisplayAt: _lastDisplayAt,
      );

  @override
  void recordDisplay(String campaignId, DateTime at) {
    _shown.add(campaignId);
    _lastDisplayAt = at;
  }

  @override
  void reset() {
    _shown.clear();
    _lastDisplayAt = null;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/frequency_cap_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/in_app_messaging/evaluation test/in_app_messaging/frequency_cap_test.dart
git commit -m "Add frequency cap with a synchronous snapshot

The 30-second floor is global rather than per-campaign, so CapState carries a
single lastDisplayAt. Snapshots are unmodifiable and stable: the evaluator sees
a fixed view even if the cap is mutated afterwards.

load() exists so a future SharedPreferences-backed implementation can read its
state once at start while snapshot() stays synchronous, which is what keeps the
evaluator a pure function."
```

---

## Task 4: Pure trigger evaluator

**Files:**
- Create: `lib/in_app_messaging/evaluation/trigger_evaluator.dart`
- Test: `test/in_app_messaging/trigger_evaluator_test.dart`

**Interfaces:**
- Consumes: `InAppMessageCampaign`, `GameballInAppMessage`, `GameballMessageType`, `GameballMessageTrigger` + variants, `triggerMatches`, `CapState`, `minimumIntervalBetweenDisplays`
- Produces: `InAppMessageCampaign? selectCampaign({required GameballMessageTrigger trigger, required List<InAppMessageCampaign> campaigns, required CapState capState, required DateTime now})`; `bool isWithinFloor({required CapState capState, required DateTime now})`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/trigger_evaluator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/trigger_evaluator.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';

final DateTime t0 = DateTime.utc(2026, 8, 5, 12);

InAppMessageCampaign campaign(
  String id, {
  GameballMessageTrigger trigger = const GameballSessionStartTrigger(),
  int priority = 0,
  GameballMessageType type = GameballMessageType.modal,
}) {
  return InAppMessageCampaign(
    id: id,
    trigger: trigger,
    priority: priority,
    message: GameballInAppMessage(id: 'msg_$id', type: type, body: 'body'),
  );
}

const CapState emptyCaps =
    CapState(shownCampaignIds: <String>{}, lastDisplayAt: null);

void main() {
  group('selectCampaign — matching', () {
    test('returns null when there are no campaigns', () {
      expect(
        selectCampaign(
          trigger: const GameballSessionStartTrigger(),
          campaigns: const <InAppMessageCampaign>[],
          capState: emptyCaps,
          now: t0,
        ),
        isNull,
      );
    });

    test('selects a campaign whose trigger matches', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('a')],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.id, 'a');
    });

    test('ignores campaigns triggered by a different type', () {
      final result = selectCampaign(
        trigger: const GameballCustomEventTrigger('add_to_cart'),
        campaigns: [campaign('a')],
        capState: emptyCaps,
        now: t0,
      );

      expect(result, isNull);
    });

    test('matches a custom event only on an exact name', () {
      final campaigns = [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ];

      expect(
        selectCampaign(
          trigger: const GameballCustomEventTrigger('add_to_cart'),
          campaigns: campaigns,
          capState: emptyCaps,
          now: t0,
        )?.id,
        'cart',
      );
      expect(
        selectCampaign(
          trigger: const GameballCustomEventTrigger('checkout'),
          campaigns: campaigns,
          capState: emptyCaps,
          now: t0,
        ),
        isNull,
      );
    });
  });

  group('selectCampaign — priority', () {
    test('higher priority wins', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('low', priority: 1), campaign('high', priority: 99)],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.id, 'high');
    });

    test('ties break on response order, not sort order', () {
      // Dart's List.sort is NOT stable, so this must hold for a list long
      // enough to trip the unstable path.
      final campaigns = [
        for (var i = 0; i < 40; i++) campaign('c$i', priority: 5),
      ];

      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: campaigns,
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.id, 'c0');
    });

    test('the winner is the first of the top priority in response order', () {
      final campaigns = [
        campaign('mid', priority: 5),
        campaign('first_top', priority: 10),
        campaign('second_top', priority: 10),
      ];

      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: campaigns,
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.id, 'first_top');
    });
  });

  group('selectCampaign — caps', () {
    test('skips a campaign that has already been shown', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('a')],
        capState: const CapState(shownCampaignIds: {'a'}, lastDisplayAt: null),
        now: t0,
      );

      expect(result, isNull);
    });

    test('falls through to a lower-priority campaign when the top is spent', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('high', priority: 99), campaign('low', priority: 1)],
        capState: const CapState(shownCampaignIds: {'high'}, lastDisplayAt: null),
        now: t0,
      );

      expect(result?.id, 'low');
    });

    test('returns null just inside the floor', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('a')],
        capState: CapState(
          shownCampaignIds: const <String>{},
          lastDisplayAt: t0.subtract(const Duration(milliseconds: 29900)),
        ),
        now: t0,
      );

      expect(result, isNull);
    });

    test('returns a campaign just outside the floor', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('a')],
        capState: CapState(
          shownCampaignIds: const <String>{},
          lastDisplayAt: t0.subtract(const Duration(milliseconds: 30100)),
        ),
        now: t0,
      );

      expect(result?.id, 'a');
    });
  });

  group('selectCampaign — unsupported types', () {
    test('never selects an unsupported message type', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [campaign('a', type: GameballMessageType.unsupported)],
        capState: emptyCaps,
        now: t0,
      );

      expect(result, isNull);
    });

    test('a supported lower-priority campaign wins over an unsupported top one', () {
      final result = selectCampaign(
        trigger: const GameballSessionStartTrigger(),
        campaigns: [
          campaign('top', priority: 99, type: GameballMessageType.unsupported),
          campaign('usable', priority: 1),
        ],
        capState: emptyCaps,
        now: t0,
      );

      expect(result?.id, 'usable');
    });
  });

  group('isWithinFloor', () {
    test('is false when nothing has been displayed', () {
      expect(isWithinFloor(capState: emptyCaps, now: t0), isFalse);
    });

    test('is true immediately after a display', () {
      expect(
        isWithinFloor(
          capState: CapState(shownCampaignIds: const <String>{}, lastDisplayAt: t0),
          now: t0,
        ),
        isTrue,
      );
    });

    test('is false once the floor has elapsed exactly', () {
      expect(
        isWithinFloor(
          capState: CapState(
            shownCampaignIds: const <String>{},
            lastDisplayAt: t0.subtract(minimumIntervalBetweenDisplays),
          ),
          now: t0,
        ),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/trigger_evaluator_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../evaluation/trigger_evaluator.dart'`.

- [ ] **Step 3: Write the implementation**

`lib/in_app_messaging/evaluation/trigger_evaluator.dart`:

```dart
import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';
import 'frequency_cap.dart';

/// Chooses which campaign, if any, should display for an occurred [trigger].
///
/// Pure: no I/O, no async, no `BuildContext`, and no clock — [now] is passed in
/// so the 30-second floor is testable without waiting. All display policy lives
/// here, which is why this is the most heavily tested unit in the module.
///
/// Order: filter by trigger match, drop already-shown, drop layouts this SDK
/// cannot render, enforce the floor, then take the highest priority breaking
/// ties on response order.
InAppMessageCampaign? selectCampaign({
  required GameballMessageTrigger trigger,
  required List<InAppMessageCampaign> campaigns,
  required CapState capState,
  required DateTime now,
}) {
  final eligible = <InAppMessageCampaign>[];
  for (final candidate in campaigns) {
    if (!triggerMatches(candidate.trigger, trigger)) continue;
    if (capState.shownCampaignIds.contains(candidate.id)) continue;
    // An unsupported layout is filtered here rather than refused at display
    // time, so a usable lower-priority campaign can still win.
    if (candidate.message.type == GameballMessageType.unsupported) continue;
    eligible.add(candidate);
  }

  if (eligible.isEmpty) return null;
  if (isWithinFloor(capState: capState, now: now)) return null;

  // Dart's List.sort is not stable, so ordering by priority alone would make
  // tie-breaks arbitrary. Carrying the original index keeps "ties break on
  // response order" true regardless of list length.
  final indexed = <(int, InAppMessageCampaign)>[
    for (var i = 0; i < eligible.length; i++) (i, eligible[i]),
  ];
  indexed.sort((a, b) {
    final byPriority = b.$2.priority.compareTo(a.$2.priority);
    return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
  });

  return indexed.first.$2;
}

/// Whether too little time has passed since the last display.
bool isWithinFloor({required CapState capState, required DateTime now}) {
  final last = capState.lastDisplayAt;
  if (last == null) return false;
  return now.difference(last) < minimumIntervalBetweenDisplays;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/trigger_evaluator_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the whole suite and the analyzer**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test
flutter analyze 2>&1 | tail -3
```

Expected: all tests PASS; `13 issues found.`

- [ ] **Step 6: Commit**

```bash
git add lib/in_app_messaging/evaluation/trigger_evaluator.dart test/in_app_messaging/trigger_evaluator_test.dart
git commit -m "Add pure trigger evaluator

All display policy lives in one pure function: trigger matching, already-shown
suppression, the global 30-second floor, and priority ordering. It takes 'now'
as a parameter rather than reading the clock, so the floor is tested at 29.9s
and 30.1s without waiting.

Two decisions worth noting. Dart's List.sort is not stable, so the original
index is carried through the sort to keep 'ties break on response order' true
for any list length. And an unsupported message type is filtered here rather
than refused at display time, so a usable lower-priority campaign still wins
instead of nothing showing."
```

---

## Task 5: Modal widget

**Files:**
- Create: `lib/in_app_messaging/presentation/in_app_message_modal.dart`
- Test: `test/in_app_messaging/in_app_message_modal_test.dart`

**Interfaces:**
- Consumes: `GameballInAppMessage`, `GameballMessageButton`, `GameballMessageStyle`, `GameballButtonStyle`
- Produces: `class GameballInAppMessageModal extends StatelessWidget` with `({Key? key, required GameballInAppMessage message, required void Function(GameballMessageButton) onButtonPressed, required VoidCallback onClosePressed})`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/in_app_message_modal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/in_app_message_modal.dart';

GameballInAppMessage message({
  String body = 'body text',
  String? header,
  String? imageUrl,
  bool showCloseButton = true,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
  GameballMessageStyle style = const GameballMessageStyle(),
}) {
  return GameballInAppMessage(
    id: 'msg',
    type: GameballMessageType.modal,
    body: body,
    header: header,
    imageUrl: imageUrl,
    showCloseButton: showCloseButton,
    buttons: buttons,
    style: style,
  );
}

Future<void> pump(
  WidgetTester tester,
  GameballInAppMessage m, {
  void Function(GameballMessageButton)? onButtonPressed,
  VoidCallback? onClosePressed,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameballInAppMessageModal(
        message: m,
        onButtonPressed: onButtonPressed ?? (_) {},
        onClosePressed: onClosePressed ?? () {},
      ),
    ),
  ));
}

void main() {
  testWidgets('renders the body', (tester) async {
    await pump(tester, message(body: 'hello there'));

    expect(find.text('hello there'), findsOneWidget);
  });

  testWidgets('renders the header when present', (tester) async {
    await pump(tester, message(header: 'Welcome'));

    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('omits the header when absent', (tester) async {
    await pump(tester, message());

    expect(find.byKey(const Key('gb_iam_header')), findsNothing);
  });

  testWidgets('shows a close button when requested', (tester) async {
    await pump(tester, message(showCloseButton: true));

    expect(find.byKey(const Key('gb_iam_close')), findsOneWidget);
  });

  testWidgets('hides the close button when not requested', (tester) async {
    await pump(tester, message(showCloseButton: false));

    expect(find.byKey(const Key('gb_iam_close')), findsNothing);
  });

  testWidgets('invokes onClosePressed when the close button is tapped', (tester) async {
    var closed = 0;
    await pump(tester, message(), onClosePressed: () => closed++);

    await tester.tap(find.byKey(const Key('gb_iam_close')));
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('renders each button and reports which was tapped', (tester) async {
    final tapped = <int>[];
    await pump(
      tester,
      message(buttons: const [
        GameballMessageButton(id: 0, text: 'Later', action: GameballDismissAction()),
        GameballMessageButton(id: 1, text: 'Redeem', action: GameballDismissAction()),
      ]),
      onButtonPressed: (b) => tapped.add(b.id),
    );

    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Redeem'), findsOneWidget);

    await tester.tap(find.text('Redeem'));
    await tester.pump();

    expect(tapped, [1]);
  });

  testWidgets('renders no button row when there are no buttons', (tester) async {
    await pump(tester, message());

    expect(find.byKey(const Key('gb_iam_buttons')), findsNothing);
  });

  testWidgets('applies the background colour from style', (tester) async {
    await pump(
      tester,
      message(style: const GameballMessageStyle(backgroundColor: Color(0xFF00FF00))),
    );

    final card = tester.widget<Material>(find.byKey(const Key('gb_iam_surface')));
    expect(card.color, const Color(0xFF00FF00));
  });

  testWidgets('renders an image slot when imageUrl is present', (tester) async {
    await pump(tester, message(imageUrl: 'https://example.com/a.png'));

    expect(find.byKey(const Key('gb_iam_image')), findsOneWidget);
  });

  testWidgets('omits the image slot when imageUrl is absent', (tester) async {
    await pump(tester, message());

    expect(find.byKey(const Key('gb_iam_image')), findsNothing);
  });

  testWidgets('a failing image does not prevent the message rendering', (tester) async {
    // The test HTTP client returns a 400 for every request, so the network
    // image always fails — which is exactly the case being asserted.
    await pump(tester, message(body: 'still here', imageUrl: 'https://example.com/nope.png'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('still here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/in_app_message_modal_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../presentation/in_app_message_modal.dart'`.

- [ ] **Step 3: Write the implementation**

`lib/in_app_messaging/presentation/in_app_message_modal.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/in_app_message.dart';

/// The modal layout: optional image, optional header, body, and up to two
/// buttons.
///
/// Draws only what the message provides, and falls back to the host's theme for
/// every colour the campaign leaves unset. Knows nothing about overlays,
/// analytics or dismissal policy — it reports taps and lets the presenter
/// decide.
class GameballInAppMessageModal extends StatelessWidget {
  const GameballInAppMessageModal({
    super.key,
    required this.message,
    required this.onButtonPressed,
    required this.onClosePressed,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = message.style;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            key: const Key('gb_iam_surface'),
            color: style.backgroundColor ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message.imageUrl != null) _image(message.imageUrl!),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (message.header != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                message.header!,
                                key: const Key('gb_iam_header'),
                                textAlign: style.headerAlign ?? TextAlign.start,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: style.headerColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Text(
                            message.body,
                            key: const Key('gb_iam_body'),
                            textAlign: style.bodyAlign ?? TextAlign.start,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: style.bodyColor),
                          ),
                          if (message.buttons.isNotEmpty) _buttons(context),
                        ],
                      ),
                    ),
                  ],
                ),
                if (message.showCloseButton)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      key: const Key('gb_iam_close'),
                      icon: const Icon(Icons.close),
                      color: style.headerColor,
                      tooltip: 'Close',
                      onPressed: onClosePressed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(String url) {
    return Image.network(
      url,
      key: const Key('gb_iam_image'),
      height: 160,
      fit: BoxFit.cover,
      // A campaign image that fails to load must never block the message.
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buttons(BuildContext context) {
    return Padding(
      key: const Key('gb_iam_buttons'),
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final button in message.buttons)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _button(context, button),
            ),
        ],
      ),
    );
  }

  Widget _button(BuildContext context, GameballMessageButton button) {
    final style = button.style;
    return TextButton(
      onPressed: () => onButtonPressed(button),
      style: TextButton.styleFrom(
        backgroundColor: style.backgroundColor,
        foregroundColor: style.textColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: style.borderColor != null
              ? BorderSide(color: style.borderColor!)
              : BorderSide.none,
        ),
      ),
      child: Text(button.text),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/in_app_message_modal_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/in_app_messaging/presentation test/in_app_messaging/in_app_message_modal_test.dart
git commit -m "Add the in-app message modal widget

Draws only what the campaign provides and falls back to the host's theme for
every unset colour, so a minimal message still looks right. A campaign image
that fails to load collapses to nothing rather than breaking the message.

The widget reports taps and knows nothing about overlays, analytics or
dismissal policy, which keeps it testable in isolation and lets the presenter
own timing."
```

---

## Task 6: Analytics and the overlay presenter

**Files:**
- Create: `lib/in_app_messaging/analytics/message_analytics.dart`
- Create: `lib/in_app_messaging/presentation/message_presenter.dart`
- Create: `lib/in_app_messaging/presentation/overlay_presenter.dart`
- Test: `test/in_app_messaging/overlay_presenter_test.dart`

**Interfaces:**
- Consumes: `GameballInAppMessage`, `GameballMessageButton`, `GameballInAppMessageModal`, `iamLog`
- Produces: `abstract class MessageAnalytics { void logImpression(GameballInAppMessage, {required String campaignId}); void logButtonClick(GameballInAppMessage, {required String campaignId, required int buttonId}); }`; `class LoggingMessageAnalytics implements MessageAnalytics`; `abstract class GameballMessagePresenter { bool get isShowing; bool present({required GameballInAppMessage message, required VoidCallback onShown, required void Function(GameballMessageButton) onButtonPressed, required VoidCallback onDismissed}); void dismiss(); }`; `class OverlayPresenter implements GameballMessagePresenter` with `OverlayPresenter(GlobalKey<NavigatorState> navigatorKey)`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/overlay_presenter_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/overlay_presenter.dart';

GameballInAppMessage message({
  Duration? autoDismissAfter,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
}) {
  return GameballInAppMessage(
    id: 'msg',
    type: GameballMessageType.modal,
    body: 'body text',
    autoDismissAfter: autoDismissAfter,
    buttons: buttons,
  );
}

/// Pumps an app with a navigator key the presenter can draw into.
Future<GlobalKey<NavigatorState>> pumpHost(WidgetTester tester) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: key,
    home: const Scaffold(body: Text('host screen')),
  ));
  return key;
}

void main() {
  testWidgets('present inserts the modal and reports shown', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var shown = 0;

    final inserted = presenter.present(
      message: message(),
      onShown: () => shown++,
      onButtonPressed: (_) {},
      onDismissed: () {},
    );
    await tester.pump();

    expect(inserted, isTrue);
    expect(shown, 1);
    expect(presenter.isShowing, isTrue);
    expect(find.text('body text'), findsOneWidget);
    expect(find.text('host screen'), findsOneWidget,
        reason: 'the overlay draws above the host without replacing it');
  });

  testWidgets('present returns false when there is no navigator', (tester) async {
    final presenter = OverlayPresenter(GlobalKey<NavigatorState>());

    final inserted = presenter.present(
      message: message(),
      onShown: () => fail('must not report shown'),
      onButtonPressed: (_) {},
      onDismissed: () => fail('must not report dismissed'),
    );

    expect(inserted, isFalse);
    expect(presenter.isShowing, isFalse);
  });

  testWidgets('present refuses to stack a second message', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () {},
    );
    await tester.pump();

    final second = presenter.present(
      message: message(),
      onShown: () => fail('must not show a second message'),
      onButtonPressed: (_) {},
      onDismissed: () {},
    );

    expect(second, isFalse);
  });

  testWidgets('dismiss removes the overlay and reports dismissed once', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    presenter.dismiss();
    presenter.dismiss(); // second call must be a no-op
    await tester.pump();

    expect(dismissed, 1);
    expect(presenter.isShowing, isFalse);
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('tapping the scrim dismisses', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(dismissed, 1);
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('tapping a button reports it without dismissing', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    final tapped = <int>[];

    presenter.present(
      message: message(buttons: const [
        GameballMessageButton(id: 3, text: 'Go', action: GameballDismissAction()),
      ]),
      onShown: () {},
      onButtonPressed: (b) => tapped.add(b.id),
      onDismissed: () {},
    );
    await tester.pump();

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(tapped, [3],
        reason: 'the service decides what a tap means; the presenter only reports it');
  });

  testWidgets('auto-dismiss fires after the configured delay', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(autoDismissAfter: const Duration(seconds: 3)),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    expect(dismissed, 0);
    await tester.pump(const Duration(seconds: 3));

    expect(dismissed, 1);
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('a manual dismiss cancels the auto-dismiss timer', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);
    var dismissed = 0;

    presenter.present(
      message: message(autoDismissAfter: const Duration(seconds: 3)),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () => dismissed++,
    );
    await tester.pump();

    presenter.dismiss();
    await tester.pump(const Duration(seconds: 5));

    expect(dismissed, 1, reason: 'the pending timer must not fire a second dismissal');
  });

  testWidgets('a message can be presented again after dismissal', (tester) async {
    final key = await pumpHost(tester);
    final presenter = OverlayPresenter(key);

    presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () {},
    );
    await tester.pump();
    presenter.dismiss();
    await tester.pump();

    final again = presenter.present(
      message: message(),
      onShown: () {},
      onButtonPressed: (_) {},
      onDismissed: () {},
    );
    await tester.pump();

    expect(again, isTrue);
    expect(find.text('body text'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/overlay_presenter_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../presentation/overlay_presenter.dart'`.

- [ ] **Step 3: Create the analytics interface**

`lib/in_app_messaging/analytics/message_analytics.dart`:

```dart
import '../iam_log.dart';
import '../models/in_app_message.dart';

/// Where impression and click events go.
///
/// Called only from the display path inside the SDK. Hosts have no way to log
/// these, by design — Braze exposes logging methods to app code, which makes
/// double-counting easy when the SDK is already logging the same events.
abstract class MessageAnalytics {
  void logImpression(GameballInAppMessage message, {required String campaignId});

  void logButtonClick(
    GameballInAppMessage message, {
    required String campaignId,
    required int buttonId,
  });
}

/// Writes analytics to the local diagnostic log.
///
/// The MVP has no impression/click endpoint; this makes the events observable
/// now and is replaced by an HTTP implementation behind the same interface.
class LoggingMessageAnalytics implements MessageAnalytics {
  @override
  void logImpression(GameballInAppMessage message, {required String campaignId}) {
    iamLog('impression: campaign="$campaignId" message="${message.id}"'
        '${message.isTestSend ? ' (test send)' : ''}');
  }

  @override
  void logButtonClick(
    GameballInAppMessage message, {
    required String campaignId,
    required int buttonId,
  }) {
    iamLog('click: campaign="$campaignId" message="${message.id}" button=$buttonId');
  }
}
```

- [ ] **Step 4: Create the presenter interface**

`lib/in_app_messaging/presentation/message_presenter.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../models/in_app_message.dart';

/// Draws a message somewhere the user can see it.
///
/// Internal: not exported to hosts. Deliberately knows nothing about analytics
/// or frequency caps — it reports what happened and the service decides what it
/// means. That is what keeps a second implementation (slideup, banner) cheap.
abstract class GameballMessagePresenter {
  /// Whether a message is on screen right now.
  bool get isShowing;

  /// Puts [message] on screen.
  ///
  /// Returns false without invoking any callback if there is no surface to draw
  /// on, or if a message is already showing.
  ///
  /// [onShown] fires once, when the message becomes visible. [onButtonPressed]
  /// fires per tap and does **not** dismiss — the caller decides. [onDismissed]
  /// fires exactly once, after the message leaves the screen, however it left.
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onDismissed,
  });

  /// Removes the current message, if any. Safe to call repeatedly.
  void dismiss();
}
```

- [ ] **Step 5: Create the overlay presenter**

`lib/in_app_messaging/presentation/overlay_presenter.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../iam_log.dart';
import '../models/in_app_message.dart';
import 'in_app_message_modal.dart';
import 'message_presenter.dart';

/// Presents messages in an [OverlayEntry] above every route.
///
/// An overlay entry is not a route, so host navigation can neither cover the
/// message nor pop it — which is the point. Braze iOS achieves the same by
/// presenting into its own `UIWindow`; Braze Android draws into the host's view
/// hierarchy only because Android offers nothing better without permissions.
class OverlayPresenter implements GameballMessagePresenter {
  OverlayPresenter(this.navigatorKey);

  /// Supplies the overlay. The host assigns this to `MaterialApp.navigatorKey`.
  final GlobalKey<NavigatorState> navigatorKey;

  OverlayEntry? _entry;
  Timer? _autoDismissTimer;
  VoidCallback? _onDismissed;

  @override
  bool get isShowing => _entry != null;

  @override
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onDismissed,
  }) {
    if (_entry != null) {
      iamLog('presenter busy: a message is already showing');
      return false;
    }

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      iamLog('no overlay available yet — is navigatorKey wired to MaterialApp?');
      return false;
    }

    _onDismissed = onDismissed;
    final entry = OverlayEntry(
      builder: (context) => _MessageLayer(
        message: message,
        onButtonPressed: onButtonPressed,
        onDismiss: dismiss,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    onShown();

    final autoDismissAfter = message.autoDismissAfter;
    if (autoDismissAfter != null) {
      _autoDismissTimer = Timer(autoDismissAfter, dismiss);
    }
    return true;
  }

  @override
  void dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;

    final entry = _entry;
    if (entry == null) {
      return; // already gone; makes dismissal idempotent
    }
    // Cleared before removing so a re-entrant call cannot double-remove.
    _entry = null;
    entry.remove();

    final onDismissed = _onDismissed;
    _onDismissed = null;
    onDismissed?.call();
  }
}

/// The scrim plus the modal, with back-button handling where it is available.
class _MessageLayer extends StatelessWidget {
  const _MessageLayer({
    required this.message,
    required this.onButtonPressed,
    required this.onDismiss,
  });

  final GameballInAppMessage message;
  final void Function(GameballMessageButton button) onButtonPressed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final layer = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(
              color: message.style.scrimColor ?? const Color(0x99000000),
            ),
          ),
        ),
        GameballInAppMessageModal(
          message: message,
          onButtonPressed: onButtonPressed,
          onClosePressed: onDismiss,
        ),
      ],
    );

    // BackButtonListener asserts when there is no Router ancestor, which a
    // plain MaterialApp does not provide. Only attach it where it works; the
    // scrim and close button are always available, so the message is never
    // undismissable.
    if (Router.maybeOf(context) == null) {
      return layer;
    }
    return BackButtonListener(
      onBackButtonPressed: () async {
        onDismiss();
        return true; // handled; do not pop the host's route
      },
      child: layer,
    );
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/overlay_presenter_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/in_app_messaging/analytics lib/in_app_messaging/presentation test/in_app_messaging/overlay_presenter_test.dart
git commit -m "Add analytics interface and OverlayEntry presenter

The presenter draws into an overlay entry rather than a dialog route, so host
navigation can neither cover the message nor pop it. Dismissal is idempotent
and the auto-dismiss timer is cancelled on any manual dismissal, so a message
can never be dismissed twice.

The presenter reports events and owns no policy: it does not log analytics or
touch frequency caps, which keeps a future slideup presenter cheap.

BackButtonListener is attached only when a Router ancestor exists, because it
asserts otherwise and would crash a plain MaterialApp in debug. The scrim and
close button are always present, so the message is never undismissable."
```

---

## Task 7: Orchestrating service

**Files:**
- Create: `lib/in_app_messaging/in_app_messaging_service.dart`
- Test: `test/in_app_messaging/in_app_messaging_service_test.dart`

**Interfaces:**
- Consumes: `GameballMessageSource`, `GameballMessagePresenter`, `FrequencyCap`, `CapState`, `MessageAnalytics`, `selectCampaign`, `isWithinFloor`, `InAppMessageCampaign`, `GameballAudience`/`CustomerAudience`, all trigger and message types, `iamLog`
- Produces: `enum GameballDisplayDecision { show, later, discard }`; `typedef GameballBeforeDisplay = GameballDisplayDecision Function(GameballInAppMessage message)`; `class InAppMessagingService({required GameballMessageSource source, required GameballMessagePresenter presenter, required FrequencyCap frequencyCap, required MessageAnalytics analytics, required bool Function() isHostWidgetOpen, void Function(GameballInAppMessage)? emit, DateTime Function()? clock, Future<bool> Function(Uri, {bool external})? launcher})` with `bool get isStarted`, `Future<void> start({required String customerId, GameballBeforeDisplay? beforeDisplay})`, `void stop()`, `void onCustomerChanged(String customerId)`, `void onCustomEvent(String eventName)`, `void onHostWidgetClosed()`, `InAppMessageCampaign? get pendingCampaign`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/in_app_messaging_service_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/analytics/message_analytics.dart';
import 'package:gameball_sdk/in_app_messaging/evaluation/frequency_cap.dart';
import 'package:gameball_sdk/in_app_messaging/in_app_messaging_service.dart';
import 'package:gameball_sdk/in_app_messaging/models/gameball_audience.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message_campaign.dart';
import 'package:gameball_sdk/in_app_messaging/models/message_trigger.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_presenter.dart';
import 'package:gameball_sdk/in_app_messaging/source/message_source.dart';

// ---------------------------------------------------------------- test doubles

class FakeSource implements GameballMessageSource {
  FakeSource(this.campaigns);

  List<InAppMessageCampaign> campaigns;
  Object? throwOnFetch;
  int fetchCount = 0;
  GameballAudience? lastAudience;

  @override
  Future<List<InAppMessageCampaign>> fetch(GameballAudience audience) async {
    fetchCount++;
    lastAudience = audience;
    final error = throwOnFetch;
    if (error != null) throw error;
    return campaigns;
  }
}

class FakePresenter implements GameballMessagePresenter {
  bool available = true;
  bool _showing = false;

  final List<String> shownMessageIds = <String>[];
  VoidCallback? _onDismissed;
  void Function(GameballMessageButton)? _onButtonPressed;

  @override
  bool get isShowing => _showing;

  @override
  bool present({
    required GameballInAppMessage message,
    required VoidCallback onShown,
    required void Function(GameballMessageButton button) onButtonPressed,
    required VoidCallback onDismissed,
  }) {
    if (!available || _showing) return false;
    _showing = true;
    _onDismissed = onDismissed;
    _onButtonPressed = onButtonPressed;
    shownMessageIds.add(message.id);
    onShown();
    return true;
  }

  @override
  void dismiss() {
    if (!_showing) return;
    _showing = false;
    final onDismissed = _onDismissed;
    _onDismissed = null;
    _onButtonPressed = null;
    onDismissed?.call();
  }

  /// Simulates the user tapping a button.
  void tapButton(GameballMessageButton button) => _onButtonPressed?.call(button);
}

class RecordingAnalytics implements MessageAnalytics {
  final List<String> impressions = <String>[];
  final List<String> clicks = <String>[];

  @override
  void logImpression(GameballInAppMessage message, {required String campaignId}) {
    impressions.add('$campaignId/${message.id}');
  }

  @override
  void logButtonClick(
    GameballInAppMessage message, {
    required String campaignId,
    required int buttonId,
  }) {
    clicks.add('$campaignId/${message.id}/$buttonId');
  }
}

// ------------------------------------------------------------------- fixtures

final DateTime t0 = DateTime.utc(2026, 8, 5, 12);

InAppMessageCampaign campaign(
  String id, {
  GameballMessageTrigger trigger = const GameballSessionStartTrigger(),
  int priority = 0,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
}) {
  return InAppMessageCampaign(
    id: id,
    trigger: trigger,
    priority: priority,
    message: GameballInAppMessage(
      id: 'msg_$id',
      type: GameballMessageType.modal,
      body: 'body',
      buttons: buttons,
    ),
  );
}

/// Assembles a service with controllable collaborators.
({
  InAppMessagingService service,
  FakeSource source,
  FakePresenter presenter,
  RecordingAnalytics analytics,
  InMemoryFrequencyCap cap,
  List<GameballInAppMessage> emitted,
  void Function(bool) setWidgetOpen,
  void Function(DateTime) setNow,
}) build({List<InAppMessageCampaign>? campaigns}) {
  final source = FakeSource(campaigns ?? [campaign('a')]);
  final presenter = FakePresenter();
  final analytics = RecordingAnalytics();
  final cap = InMemoryFrequencyCap();
  final emitted = <GameballInAppMessage>[];
  var widgetOpen = false;
  var now = t0;

  final service = InAppMessagingService(
    source: source,
    presenter: presenter,
    frequencyCap: cap,
    analytics: analytics,
    isHostWidgetOpen: () => widgetOpen,
    emit: emitted.add,
    clock: () => now,
    launcher: (uri, {bool external = false}) async => true,
  );

  return (
    service: service,
    source: source,
    presenter: presenter,
    analytics: analytics,
    cap: cap,
    emitted: emitted,
    setWidgetOpen: (v) => widgetOpen = v,
    setNow: (v) => now = v,
  );
}

void main() {
  group('start', () {
    test('fetches once and displays the session-start message', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.source.fetchCount, 1);
      expect(h.source.lastAudience, isA<CustomerAudience>());
      expect(h.presenter.shownMessageIds, ['msg_a']);
      expect(h.service.isStarted, isTrue);
    });

    test('logs an impression and records the cap at display', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.analytics.impressions, ['a/msg_a']);
      expect(h.cap.snapshot().shownCampaignIds, {'a'});
      expect(h.cap.snapshot().lastDisplayAt, t0);
    });

    test('emits the message for observers', () async {
      final h = build();

      await h.service.start(customerId: 'c1');

      expect(h.emitted.map((m) => m.id), ['msg_a']);
    });

    test('a second start for the same customer does not refetch', () async {
      final h = build();

      await h.service.start(customerId: 'c1');
      await h.service.start(customerId: 'c1');

      expect(h.source.fetchCount, 1);
    });

    test('a fetch failure leaves no campaigns and does not throw', () async {
      final h = build();
      h.source.throwOnFetch = Exception('network down');

      await expectLater(h.service.start(customerId: 'c1'), completes);

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.isStarted, isTrue);
    });
  });

  group('custom event trigger', () {
    test('displays a matching campaign', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, ['msg_cart']);
    });

    test('ignores a non-matching event', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');

      h.service.onCustomEvent('checkout');

      expect(h.presenter.shownMessageIds, isEmpty);
    });

    test('does nothing before start', () {
      final h = build();

      h.service.onCustomEvent('add_to_cart');

      expect(h.source.fetchCount, 0);
      expect(h.presenter.shownMessageIds, isEmpty);
    });
  });

  group('deferral and retry', () {
    test('defers while the host widget is open', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setWidgetOpen(true);

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign?.id, 'cart');
    });

    test('displays the pending message once the widget closes', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setWidgetOpen(true);
      h.service.onCustomEvent('add_to_cart');

      h.setWidgetOpen(false);
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_cart']);
      expect(h.service.pendingCampaign, isNull);
    });

    test('a retry still respects the floor', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1'); // shows 'first' at t0
      h.presenter.dismiss();

      // Widget opens, event fires, message defers.
      h.setWidgetOpen(true);
      h.setNow(t0.add(const Duration(seconds: 5)));
      h.service.onCustomEvent('add_to_cart');
      expect(h.service.pendingCampaign?.id, 'cart');

      // Widget closes only 10s after the first display — still inside the floor.
      h.setWidgetOpen(false);
      h.setNow(t0.add(const Duration(seconds: 10)));
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_first'],
          reason: 'the retry must not bypass the 30-second floor');
      expect(h.service.pendingCampaign?.id, 'cart', reason: 'it stays pending');
    });

    test('a pending message displays once the floor has passed', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.presenter.dismiss();

      h.setWidgetOpen(true);
      h.service.onCustomEvent('add_to_cart');
      h.setWidgetOpen(false);
      h.setNow(t0.add(const Duration(seconds: 31)));
      h.service.onHostWidgetClosed();

      expect(h.presenter.shownMessageIds, ['msg_first', 'msg_cart']);
    });

    test('a pending message already shown is dropped rather than repeated', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');

      // Show it normally, then force it pending and mark it shown.
      h.service.onCustomEvent('add_to_cart');
      expect(h.presenter.shownMessageIds, ['msg_cart']);
      h.setWidgetOpen(true);
      h.setNow(t0.add(const Duration(seconds: 60)));
      h.service.onCustomEvent('add_to_cart');

      expect(h.service.pendingCampaign, isNull,
          reason: 'an already-shown campaign is never selected again');
    });

    test('defers when a message is already showing', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setNow(t0.add(const Duration(seconds: 31)));

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, ['msg_first']);
      expect(h.service.pendingCampaign?.id, 'cart');
    });

    test('the pending message displays when the current one is dismissed', () async {
      final h = build(campaigns: [
        campaign('first'),
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setNow(t0.add(const Duration(seconds: 31)));
      h.service.onCustomEvent('add_to_cart');

      h.presenter.dismiss();

      expect(h.presenter.shownMessageIds, ['msg_first', 'msg_cart']);
    });

    test('a newer deferral displaces an older one', () async {
      final h = build(campaigns: [
        campaign('one', trigger: const GameballCustomEventTrigger('e1')),
        campaign('two', trigger: const GameballCustomEventTrigger('e2')),
      ]);
      await h.service.start(customerId: 'c1');
      h.setWidgetOpen(true);

      h.service.onCustomEvent('e1');
      h.service.onCustomEvent('e2');

      expect(h.service.pendingCampaign?.id, 'two');
    });
  });

  group('beforeDisplay hook', () {
    test('discard prevents display and leaves nothing pending', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => GameballDisplayDecision.discard,
      );

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign, isNull);
    });

    test('later defers using the same pending slot', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => GameballDisplayDecision.later,
      );

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign?.id, 'a');
    });

    test('show displays as normal', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => GameballDisplayDecision.show,
      );

      expect(h.presenter.shownMessageIds, ['msg_a']);
    });

    test('a throwing hook falls back to show', () async {
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (_) => throw StateError('host bug'),
      );

      expect(h.presenter.shownMessageIds, ['msg_a'],
          reason: 'the no-hook default is show, so falling back to it is least surprising');
    });

    test('the hook still receives messages it will not see displayed', () async {
      final seen = <String>[];
      final h = build();

      await h.service.start(
        customerId: 'c1',
        beforeDisplay: (m) {
          seen.add(m.id);
          return GameballDisplayDecision.discard;
        },
      );

      expect(seen, ['msg_a']);
    });
  });

  group('button taps', () {
    test('a tap logs a click and dismisses', () async {
      final h = build(campaigns: [
        campaign('a', buttons: const [
          GameballMessageButton(id: 4, text: 'Go', action: GameballDismissAction()),
        ]),
      ]);
      await h.service.start(customerId: 'c1');

      h.presenter.tapButton(const GameballMessageButton(
        id: 4,
        text: 'Go',
        action: GameballDismissAction(),
      ));

      expect(h.analytics.clicks, ['a/msg_a/4']);
      expect(h.presenter.isShowing, isFalse);
    });
  });

  group('customer changes', () {
    test('a new customer refetches and resets caps', () async {
      final h = build();
      await h.service.start(customerId: 'c1');
      expect(h.cap.snapshot().shownCampaignIds, {'a'});

      h.service.onCustomerChanged('c2');
      await Future<void>.delayed(Duration.zero);

      expect(h.source.fetchCount, 2);
      expect((h.source.lastAudience! as CustomerAudience).customerId, 'c2');
    });

    test('the same customer does not refetch', () async {
      final h = build();
      await h.service.start(customerId: 'c1');

      h.service.onCustomerChanged('c1');
      await Future<void>.delayed(Duration.zero);

      expect(h.source.fetchCount, 1);
    });

    test('does nothing before start', () async {
      final h = build();

      h.service.onCustomerChanged('c1');
      await Future<void>.delayed(Duration.zero);

      expect(h.source.fetchCount, 0);
    });
  });

  group('stop', () {
    test('dismisses, clears pending, and forgets the customer', () async {
      final h = build();
      await h.service.start(customerId: 'c1');

      h.service.stop();

      expect(h.presenter.isShowing, isFalse);
      expect(h.service.isStarted, isFalse);
      expect(h.service.pendingCampaign, isNull);
      expect(h.cap.snapshot().shownCampaignIds, isEmpty);
    });

    test('is a no-op when not started', () {
      final h = build();

      expect(h.service.stop, returnsNormally);
    });

    test('events after stop are ignored', () async {
      final h = build(campaigns: [
        campaign('cart', trigger: const GameballCustomEventTrigger('add_to_cart')),
      ]);
      await h.service.start(customerId: 'c1');
      h.service.stop();

      h.service.onCustomEvent('add_to_cart');

      expect(h.presenter.shownMessageIds, isEmpty);
    });
  });

  group('no presentation surface', () {
    test('defers when the presenter cannot draw', () async {
      final h = build();
      h.presenter.available = false;

      await h.service.start(customerId: 'c1');

      expect(h.presenter.shownMessageIds, isEmpty);
      expect(h.service.pendingCampaign?.id, 'a');
    });

    test('displays on retry once a surface appears', () async {
      final h = build();
      h.presenter.available = false;
      await h.service.start(customerId: 'c1');

      h.presenter.available = true;
      h.service.onHostWidgetClosed(); // any retry trigger

      expect(h.presenter.shownMessageIds, ['msg_a']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/in_app_messaging_service_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../in_app_messaging_service.dart'`.

- [ ] **Step 3: Write the implementation**

`lib/in_app_messaging/in_app_messaging_service.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'analytics/message_analytics.dart';
import 'evaluation/frequency_cap.dart';
import 'evaluation/trigger_evaluator.dart';
import 'iam_log.dart';
import 'models/gameball_audience.dart';
import 'models/in_app_message.dart';
import 'models/in_app_message_campaign.dart';
import 'models/message_trigger.dart';
import 'presentation/message_presenter.dart';
import 'source/message_source.dart';

/// What the host wants done with a message about to be displayed.
enum GameballDisplayDecision {
  /// Display it now.
  show,

  /// Hold it; it will be retried at the next display opportunity.
  later,

  /// Drop it. It will not be shown for this trigger occurrence.
  discard,
}

/// Consulted immediately before a message is displayed.
///
/// Synchronous, matching Braze Android's `beforeInAppMessageDisplayed`. If it
/// throws, the SDK falls back to [GameballDisplayDecision.show].
typedef GameballBeforeDisplay = GameballDisplayDecision Function(
  GameballInAppMessage message,
);

/// Signature for opening a URL, injectable so tests never touch the platform.
typedef UrlLauncher = Future<bool> Function(Uri uri, {bool external});

/// Wires fetching, evaluation, deferral, display and analytics together.
///
/// Owns no display policy of its own — [selectCampaign] decides what shows —
/// and no drawing. Its job is sequencing and the pending-message slot.
class InAppMessagingService {
  InAppMessagingService({
    required GameballMessageSource source,
    required GameballMessagePresenter presenter,
    required FrequencyCap frequencyCap,
    required MessageAnalytics analytics,
    required bool Function() isHostWidgetOpen,
    void Function(GameballInAppMessage message)? emit,
    DateTime Function()? clock,
    UrlLauncher? launcher,
  })  : _source = source,
        _presenter = presenter,
        _cap = frequencyCap,
        _analytics = analytics,
        _isHostWidgetOpen = isHostWidgetOpen,
        _emit = emit,
        _clock = clock ?? DateTime.now,
        _launcher = launcher ?? _defaultLauncher;

  final GameballMessageSource _source;
  final GameballMessagePresenter _presenter;
  final FrequencyCap _cap;
  final MessageAnalytics _analytics;
  final bool Function() _isHostWidgetOpen;
  final void Function(GameballInAppMessage message)? _emit;
  final DateTime Function() _clock;
  final UrlLauncher _launcher;

  GameballAudience? _audience;
  GameballBeforeDisplay? _beforeDisplay;
  List<InAppMessageCampaign> _campaigns = const <InAppMessageCampaign>[];

  /// The one message waiting for a display opportunity, if any.
  ///
  /// A single slot: a newer deferral displaces an older one. Braze keeps a
  /// stack; for one message type a slot is honest and enough.
  InAppMessageCampaign? _pending;

  /// Whether in-app messaging is running for a customer.
  bool get isStarted => _audience != null;

  /// Exposed for the debug surface in the sample app and for tests.
  InAppMessageCampaign? get pendingCampaign => _pending;

  static Future<bool> _defaultLauncher(Uri uri, {bool external = false}) {
    return launchUrl(
      uri,
      mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault,
    );
  }

  /// Opts in to in-app messaging for [customerId] and evaluates session start.
  Future<void> start({
    required String customerId,
    GameballBeforeDisplay? beforeDisplay,
  }) async {
    final current = _audience;
    if (current is CustomerAudience && current.customerId == customerId) {
      iamLog('start ignored: already running for customer "$customerId"');
      return;
    }

    _beforeDisplay = beforeDisplay;
    _resetFor(CustomerAudience(customerId));
    await _fetchAndEvaluateSessionStart();
  }

  /// Clears all state and dismisses anything on screen.
  void stop() {
    if (!isStarted) return;
    _presenter.dismiss();
    _pending = null;
    _campaigns = const <InAppMessageCampaign>[];
    _cap.reset();
    _audience = null;
    _beforeDisplay = null;
    iamLog('in-app messaging stopped');
  }

  /// Called when the host identifies a (possibly different) customer.
  void onCustomerChanged(String customerId) {
    if (!isStarted) return;
    final current = _audience;
    if (current is CustomerAudience && current.customerId == customerId) return;

    iamLog('customer changed to "$customerId"; refetching campaigns');
    _resetFor(CustomerAudience(customerId));
    // Fire and forget: the caller's contract must not wait on ours.
    _fetchAndEvaluateSessionStart();
  }

  /// Called when the host logs an event that may trigger a message.
  void onCustomEvent(String eventName) {
    if (!isStarted) return;
    _evaluate(GameballCustomEventTrigger(eventName));
  }

  /// Called when the Gameball profile widget closes, freeing the screen.
  void onHostWidgetClosed() => _retryPending();

  // ------------------------------------------------------------------ internals

  void _resetFor(GameballAudience audience) {
    _presenter.dismiss();
    _pending = null;
    _campaigns = const <InAppMessageCampaign>[];
    _cap.reset();
    _audience = audience;
  }

  Future<void> _fetchAndEvaluateSessionStart() async {
    final audience = _audience;
    if (audience == null) return;

    await _cap.load();
    try {
      _campaigns = await _source.fetch(audience);
      iamLog('fetched ${_campaigns.length} campaign(s)');
    } catch (error) {
      _campaigns = const <InAppMessageCampaign>[];
      iamLog('fetch failed; no campaigns available for this session ($error)');
      return;
    }

    _evaluate(const GameballSessionStartTrigger());
  }

  void _evaluate(GameballMessageTrigger trigger) {
    if (_campaigns.isEmpty) {
      iamLog('trigger ignored: no campaigns loaded');
      return;
    }

    final campaign = selectCampaign(
      trigger: trigger,
      campaigns: _campaigns,
      capState: _cap.snapshot(),
      now: _clock(),
    );
    if (campaign == null) return;

    // Observers see every selected message, whatever the host then decides.
    _emit?.call(campaign.message);

    switch (_decide(campaign.message)) {
      case GameballDisplayDecision.discard:
        iamLog('campaign "${campaign.id}" discarded by beforeDisplay');
      case GameballDisplayDecision.later:
        _defer(campaign, 'the host asked to display it later');
      case GameballDisplayDecision.show:
        _tryPresent(campaign);
    }
  }

  GameballDisplayDecision _decide(GameballInAppMessage message) {
    final hook = _beforeDisplay;
    if (hook == null) return GameballDisplayDecision.show;
    try {
      return hook(message);
    } catch (error) {
      iamLog('beforeDisplay threw; defaulting to show ($error)');
      return GameballDisplayDecision.show;
    }
  }

  void _tryPresent(InAppMessageCampaign campaign) {
    if (_isHostWidgetOpen()) {
      _defer(campaign, 'the Gameball widget is open');
      return;
    }
    if (_presenter.isShowing) {
      _defer(campaign, 'another message is showing');
      return;
    }

    final presented = _presenter.present(
      message: campaign.message,
      onShown: () {
        // Recorded at impression, never at selection, so a deferred or
        // suppressed message does not burn its slot.
        _cap.recordDisplay(campaign.id, _clock());
        _analytics.logImpression(campaign.message, campaignId: campaign.id);
      },
      onButtonPressed: (button) {
        _analytics.logButtonClick(
          campaign.message,
          campaignId: campaign.id,
          buttonId: button.id,
        );
        _runAction(button.action);
        _presenter.dismiss();
      },
      onDismissed: _retryPending,
    );

    if (!presented) {
      _defer(campaign, 'no presentation surface available');
      // start() can precede the first frame, so try once more after it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _retryPending());
    }
  }

  void _defer(InAppMessageCampaign campaign, String reason) {
    final displaced = _pending;
    if (displaced != null && displaced.id != campaign.id) {
      iamLog('pending campaign "${displaced.id}" displaced by "${campaign.id}"');
    }
    _pending = campaign;
    iamLog('campaign "${campaign.id}" deferred: $reason');
  }

  void _retryPending() {
    final campaign = _pending;
    if (campaign == null) return;
    _pending = null;

    final capState = _cap.snapshot();
    if (capState.shownCampaignIds.contains(campaign.id)) {
      iamLog('pending campaign "${campaign.id}" dropped: already shown');
      return;
    }
    // Re-validated so a message deferred before another was displayed cannot
    // slip through inside the floor.
    if (isWithinFloor(capState: capState, now: _clock())) {
      _pending = campaign;
      return;
    }

    _tryPresent(campaign);
  }

  Future<void> _runAction(GameballClickAction action) async {
    switch (action) {
      case GameballDismissAction():
        return;
      case GameballOpenUrlAction(url: final url, external: final external):
        final uri = Uri.tryParse(url);
        if (uri == null) {
          iamLog('cannot open malformed url "$url"');
          return;
        }
        try {
          final opened = await _launcher(uri, external: external);
          if (!opened) iamLog('could not open "$url"');
        } catch (error) {
          // Never trap the user: the message is dismissed regardless.
          iamLog('could not open "$url" ($error)');
        }
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/in_app_messaging_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the whole suite and the analyzer**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test
flutter analyze 2>&1 | tail -3
```

Expected: all PASS; `13 issues found.`

- [ ] **Step 6: Commit**

```bash
git add lib/in_app_messaging/in_app_messaging_service.dart test/in_app_messaging/in_app_messaging_service_test.dart
git commit -m "Add orchestrating service with deferral and retry

The service sequences fetch, evaluation, display and analytics but owns no
display policy — selectCampaign decides what shows, the presenter decides how.

Deferral actually retries, which is the part that is easy to get wrong: a
message blocked by the Gameball widget, by another message, or by a missing
presentation surface goes into a single pending slot and is retried when the
blocker clears. The retry re-validates the frequency cap rather than bypassing
it, so a message deferred before another was displayed cannot slip through
inside the 30-second floor.

Caps are recorded at impression rather than at selection, so a deferred or
discarded message does not burn its slot. A throwing beforeDisplay hook falls
back to show, matching the behaviour when no hook is set."
```

---

## Task 8: Public barrel, SDK wiring, version bump

**Files:**
- Create: `lib/in_app_messaging/in_app_messaging.dart`
- Modify: `lib/gameball_sdk.dart` (imports; static field; three methods; three hooks at the existing `initializeCustomer`, `sendEvent`, and the widget-close `.then` at `:402-404`)
- Modify: `pubspec.yaml:3` (`3.2.0` → `3.3.0`)
- Modify: `lib/utils/gameball_utils.dart:26` (`"3.2.0"` → `"3.3.0"`)
- Test: `test/in_app_messaging/compatibility_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–7
- Produces: on `GameballApp` — `void startInAppMessaging({required String customerId, required GlobalKey<NavigatorState> navigatorKey, GameballBeforeDisplay? beforeDisplay})`, `void stopInAppMessaging()`, `Stream<GameballInAppMessage> get onInAppMessage`, `bool get isInAppMessagingStarted`, `InAppMessageCampaign? get pendingInAppMessageCampaign`

- [ ] **Step 1: Write the failing test**

Create `test/in_app_messaging/compatibility_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';

void main() {
  GameballApp app() => GameballApp.getInstance();

  setUp(() {
    // Static state is shared across tests; leave every test a clean module.
    app().stopInAppMessaging();
  });

  group('the module is inert until started', () {
    test('a fresh SDK reports in-app messaging as not started', () {
      expect(app().isInAppMessagingStarted, isFalse);
    });

    test('nothing is pending before start', () {
      expect(app().pendingInAppMessageCampaign, isNull);
    });

    testWidgets('no overlay is inserted when start is never called', (tester) async {
      final key = GlobalKey<NavigatorState>();
      app().init(GameballConfigBuilder().apiKey('test-key').lang('en').build());

      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('host screen')),
      ));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('host screen'), findsOneWidget);
      expect(app().isInAppMessagingStarted, isFalse);
    });

    test('sendEvent does not start in-app messaging', () {
      app().init(GameballConfigBuilder().apiKey('test-key').lang('en').build());

      // The request itself will fail (no network in tests); what matters is
      // that the additive hook neither throws nor starts the module.
      expect(
        () => app().sendEvent(
          EventBuilder().customerId('c1').eventName('add_to_cart').build(),
          (_, __) {},
        ),
        returnsNormally,
      );
      expect(app().isInAppMessagingStarted, isFalse);
    });

    test('stopInAppMessaging before any start is a no-op', () {
      expect(app().stopInAppMessaging, returnsNormally);
    });
  });

  group('lifecycle guards', () {
    test('start without init is ignored rather than throwing', () {
      // A fresh process would have no api key; this asserts the guard exists
      // and does not throw. Ordering makes this best-effort, so the assertion
      // is only that it never throws.
      expect(
        () => app().startInAppMessaging(
          customerId: 'c1',
          navigatorKey: GlobalKey<NavigatorState>(),
        ),
        returnsNormally,
      );
    });
  });

  group('observation stream', () {
    test('onInAppMessage can be subscribed before start', () async {
      final received = <GameballInAppMessage>[];
      final sub = app().onInAppMessage.listen(received.add);
      addTearDown(sub.cancel);

      expect(received, isEmpty);
    });

    test('onInAppMessage returns the same broadcast stream each time', () {
      final a = app().onInAppMessage;
      final b = app().onInAppMessage;

      expect(a.isBroadcast, isTrue);
      final subA = a.listen((_) {});
      final subB = b.listen((_) {});
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);
    });
  });

  group('public surface is exported from the single import', () {
    test('the in-app messaging types resolve via gameball_sdk.dart', () {
      // Compile-time assertion: if the barrel export is missing, this file
      // will not compile at all.
      const decision = GameballDisplayDecision.show;
      const type = GameballMessageType.modal;
      const action = GameballDismissAction();
      const trigger = GameballSessionStartTrigger();

      expect(decision, GameballDisplayDecision.show);
      expect(type, GameballMessageType.modal);
      expect(action, isA<GameballClickAction>());
      expect(trigger, isA<GameballMessageTrigger>());
    });
  });
}
```

> **Note for the implementer:** the `EventBuilder` chain above is verified against `lib/models/requests/event.dart` and compiles as written (`customerId(String)`, `eventName(String?)`, `build()`). Two things to watch: `eventName()` must precede any `eventMetaData()` call, and the analyzer may flag `(_, __)` under `unnecessary_underscores` — use `(_, _)` if so.

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter test test/in_app_messaging/compatibility_test.dart
```

Expected: FAIL — `The method 'startInAppMessaging' isn't defined for the class 'GameballApp'`, plus undefined `GameballDisplayDecision` etc.

- [ ] **Step 3: Create the public barrel**

`lib/in_app_messaging/in_app_messaging.dart`:

```dart
/// Public surface of the in-app messaging module.
///
/// Everything else under `in_app_messaging/` is internal. In particular the
/// source, presenter, frequency cap and analytics interfaces are deliberately
/// not exported: they are seams for our own extensibility and tests, and
/// publishing them now would be API we must support.
library;

export 'in_app_messaging_service.dart'
    show GameballBeforeDisplay, GameballDisplayDecision;
export 'models/in_app_message.dart'
    show
        GameballButtonStyle,
        GameballClickAction,
        GameballDismissAction,
        GameballInAppMessage,
        GameballMessageButton,
        GameballMessageStyle,
        GameballMessageType,
        GameballOpenUrlAction,
        maxModalButtons;
export 'models/message_trigger.dart'
    show
        GameballCustomEventTrigger,
        GameballMessageTrigger,
        GameballSessionStartTrigger;
```

- [ ] **Step 4: Wire the module into `GameballApp`**

In `lib/gameball_sdk.dart`, add these imports alongside the existing ones:

```dart
import 'in_app_messaging/analytics/message_analytics.dart';
import 'in_app_messaging/evaluation/frequency_cap.dart';
import 'in_app_messaging/iam_log.dart';
import 'in_app_messaging/in_app_messaging_service.dart';
import 'in_app_messaging/models/in_app_message.dart';
import 'in_app_messaging/models/in_app_message_campaign.dart';
import 'in_app_messaging/presentation/overlay_presenter.dart';
import 'in_app_messaging/source/stub_message_source.dart';

export 'in_app_messaging/in_app_messaging.dart';
```

Add `import 'dart:async';` if it is not already present (needed for `StreamController`).

Add these static fields next to the existing ones (after `static VoidCallback? _dismissActiveWidget;`):

```dart
  static InAppMessagingService? _inAppMessaging;
  static StreamController<GameballInAppMessage>? _inAppMessageController;
```

Add these members to `GameballApp` (placing them after `sendEvent` keeps related code together):

```dart
  /// Opts in to in-app messaging for [customerId].
  ///
  /// Nothing in the in-app messaging module runs until this is called: no
  /// requests, no timers, no state. Existing integrations are unaffected by
  /// upgrading.
  ///
  /// [navigatorKey] must be the key assigned to your `MaterialApp.navigatorKey`
  /// — it is how the SDK finds a surface to draw on without needing a
  /// `BuildContext` at every call site.
  ///
  /// [beforeDisplay] is consulted immediately before each message is shown, and
  /// can show, defer or discard it. Omit it to always show.
  ///
  /// Calling this again with a different [customerId] refetches campaigns and
  /// resets frequency caps. Calling it with the same one does nothing.
  void startInAppMessaging({
    required String customerId,
    required GlobalKey<NavigatorState> navigatorKey,
    GameballBeforeDisplay? beforeDisplay,
  }) {
    if (isNullOrEmpty(_apiKey)) {
      iamLog('startInAppMessaging ignored: API key is not initialized. '
          'Call init() first');
      return;
    }

    final service = _inAppMessaging ??= InAppMessagingService(
      source: StubMessageSource(),
      presenter: OverlayPresenter(navigatorKey),
      frequencyCap: InMemoryFrequencyCap(),
      analytics: LoggingMessageAnalytics(),
      isHostWidgetOpen: () => _dismissActiveWidget != null,
      emit: (message) => _inAppMessageController?.add(message),
    );

    service.start(customerId: customerId, beforeDisplay: beforeDisplay);
  }

  /// Stops in-app messaging, dismissing anything on screen and clearing state.
  ///
  /// Call on logout. Safe to call when it was never started.
  void stopInAppMessaging() => _inAppMessaging?.stop();

  /// Whether in-app messaging is currently running.
  bool get isInAppMessagingStarted => _inAppMessaging?.isStarted ?? false;

  /// The message waiting for a display opportunity, if any. Diagnostic.
  InAppMessageCampaign? get pendingInAppMessageCampaign =>
      _inAppMessaging?.pendingCampaign;

  /// Every in-app message the SDK selects for display.
  ///
  /// Observation only — the SDK owns impression and click logging, so there is
  /// no way to double-count from here. Safe to subscribe before
  /// [startInAppMessaging]. The controller is created on first access, so hosts
  /// that never listen pay nothing.
  Stream<GameballInAppMessage> get onInAppMessage =>
      (_inAppMessageController ??=
              StreamController<GameballInAppMessage>.broadcast())
          .stream;
```

- [ ] **Step 5: Add the three additive hooks**

**Hook 1** — at the very end of `initializeCustomer`, *after* its existing `try`/`catch` block closes:

```dart
    // Additive: tell in-app messaging the customer may have changed. Guarded,
    // and deliberately outside the request's future chain — that chain has no
    // catchError, so anything thrown inside it escapes unhandled.
    try {
      _inAppMessaging?.onCustomerChanged(request.customerId);
    } catch (error) {
      iamLog('onCustomerChanged hook failed: $error');
    }
```

**Hook 2** — at the very end of `sendEvent`, *after* its existing `try`/`catch` block closes:

```dart
    // Additive: an event may trigger an in-app message. Guarded and outside
    // the request's future chain, for the same reason as above.
    try {
      final service = _inAppMessaging;
      if (service != null) {
        for (final eventName in event.events.keys) {
          service.onCustomEvent(eventName);
        }
      }
    } catch (error) {
      iamLog('onCustomEvent hook failed: $error');
    }
```

**Hook 3** — in `_openCustomerProfileWidget`, extend the existing `.then` at lines 402–404:

```dart
    ).then((_) {
      _dismissActiveWidget = null;
      // Additive: the screen is free again, so a deferred message may now be
      // presentable.
      try {
        _inAppMessaging?.onHostWidgetClosed();
      } catch (error) {
        iamLog('onHostWidgetClosed hook failed: $error');
      }
    });
```

- [ ] **Step 6: Bump the version in both places**

In `pubspec.yaml`, line 3:

```yaml
version: 3.3.0
```

In `lib/utils/gameball_utils.dart`, line 26:

```dart
  return "3.3.0";
```

- [ ] **Step 7: Run the full suite and the analyzer**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter pub get
flutter test
flutter analyze 2>&1 | tail -3
flutter analyze 2>&1 | grep 'in_app_messaging' || echo "no issues in the new module"
```

Expected: all tests PASS; `13 issues found.`; no issues in `in_app_messaging`.

If the analyzer reports more than 13, the extras are yours — fix them. Do not touch the pre-existing 13.

- [ ] **Step 8: Verify the version bump reaches the header**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
grep -n 'version:' pubspec.yaml | head -1
grep -n '3.3.0' lib/utils/gameball_utils.dart
```

Expected: both report `3.3.0`. The `x-gb-agent` header is built from `getSdkVersion()`, so a missed bump silently misreports the SDK version to the backend.

- [ ] **Step 9: Stage 0 — prove the compatibility invariant against the real sample app**

```bash
cd /Users/mostafamoaty/Desktop/Gameball/gameball-sample-app
git status --short
export PATH="$HOME/development/flutter/bin:$PATH"
flutter pub get
flutter analyze 2>&1 | tail -3
```

Expected: the sample app is **unmodified**, resolves the new SDK version, and analyzes clean (`No issues found!`).

Then run it and confirm behaviour is unchanged:

```bash
./run.sh
```

Expected: the storefront loads with six products and the SDK status chip, exactly as before. **No modal appears**, because `startInAppMessaging` is never called. Quit with `q`.

- [ ] **Step 10: Commit**

```bash
cd /Users/mostafamoaty/Desktop/Gameball/gameball-flutter
git add lib pubspec.yaml test
git commit -m "Wire in-app messaging into GameballApp as an opt-in module

Adds startInAppMessaging/stopInAppMessaging, an observation stream, and two
diagnostic getters. Nothing runs until startInAppMessaging is called: no
requests, no timers, no state, and the stream controller is created only if a
host actually listens.

The three hooks into initializeCustomer, sendEvent and the widget-close path
are additive, individually guarded, and placed outside the existing .then
chains — those chains have no catchError, so anything thrown inside them would
escape as an unhandled async error.

Public types are all Gameball-prefixed because gameball_sdk.dart now re-exports
the module, injecting names into the namespace of every existing importer.

Bumps 3.2.0 to 3.3.0 in both pubspec.yaml and the hardcoded getSdkVersion,
which feeds the x-gb-agent header."
```

---

## Task 9: Sample app — stage 1, in-app messaging alone

**Files (all in `/Users/mostafamoaty/Desktop/Gameball/gameball-sample-app`):**
- Modify: `lib/main.dart` (navigator key on `MaterialApp`)
- Modify: `lib/gameball/gameball_service.dart` (start/stop wrappers, IAM status)
- Modify: `lib/screens/gameball_debug_screen.dart` (start/stop controls, IAM diagnostics)

**Interfaces:**
- Consumes: `GameballApp.startInAppMessaging`, `stopInAppMessaging`, `isInAppMessagingStarted`, `pendingInAppMessageCampaign`, `onInAppMessage`, `GameballInAppMessage`
- Produces: nothing consumed by later tasks except the debug controls used in Task 10

- [ ] **Step 1: Add a navigator key to the app**

In `lib/main.dart`, add a static key to `SampleApp` and pass it to `MaterialApp`:

```dart
class SampleApp extends StatelessWidget {
  const SampleApp({super.key, required this.service});

  final GameballService service;

  /// Gives the Gameball SDK a surface to present in-app messages on.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gameball Store',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C4DF6),
        useMaterial3: true,
      ),
      home: HomeScreen(service: service),
    );
  }
}
```

Keep the existing `theme` and `home` values as they are if they differ — only `navigatorKey` is being added.

- [ ] **Step 2: Add in-app messaging control to the sample service**

In `lib/gameball/gameball_service.dart`, add these members to `GameballService`:

```dart
  /// Messages the SDK has selected, newest last. Populated from the SDK stream.
  final List<GameballInAppMessage> receivedMessages = <GameballInAppMessage>[];

  StreamSubscription<GameballInAppMessage>? _messageSubscription;

  bool get isInAppMessagingStarted => _app.isInAppMessagingStarted;

  String? get pendingCampaignId => _app.pendingInAppMessageCampaign?.id;

  /// Opts in to in-app messaging. Deliberately manual so the app can be run
  /// both with and without it.
  void startInAppMessaging(GlobalKey<NavigatorState> navigatorKey) {
    _messageSubscription ??= _app.onInAppMessage.listen((message) {
      receivedMessages.add(message);
      _log('in-app message', 'selected "${message.id}" (${message.type.name})');
    });

    _app.startInAppMessaging(
      customerId: GameballEnv.customerId,
      navigatorKey: navigatorKey,
    );
    _log('startInAppMessaging', 'customerId=${GameballEnv.customerId}');
    _emit(statusNotifier.value);
  }

  void stopInAppMessaging() {
    _app.stopInAppMessaging();
    _log('stopInAppMessaging', 'cleared campaigns, caps and pending message');
    _emit(statusNotifier.value);
  }
```

Add `import 'dart:async';` and `import 'package:flutter/widgets.dart';` if not already present. `GameballInAppMessage` arrives through the existing `package:gameball_sdk/gameball_sdk.dart` import.

If `_emit(statusNotifier.value)` does not force a rebuild because the status object is unchanged, add a monotonically increasing field to `GameballStatus` — or simpler, call `statusNotifier.notifyListeners()` via a small public `refresh()` method on the service. Use whichever the existing `GameballStatus`/`copyWith` shape makes cleanest; the requirement is only that the debug screen re-renders.

- [ ] **Step 3: Add in-app messaging controls to the debug screen**

In `lib/screens/gameball_debug_screen.dart`, add a section rendering:

- A row: **In-app messaging** — `Started` / `Not started`, from `service.isInAppMessagingStarted`
- A row: **Pending campaign** — `service.pendingCampaignId ?? '—'`
- A row: **Messages selected** — `service.receivedMessages.length`
- A **Start in-app messaging** button calling
  `service.startInAppMessaging(SampleApp.navigatorKey)`
- A **Stop in-app messaging** button calling `service.stopInAppMessaging()`

Wrap the buttons' `onPressed` bodies in `setState(() { ... })` so the rows above refresh. Import `SampleApp` from `../main.dart`.

Follow the existing row/button helpers in that file rather than inventing new ones.

- [ ] **Step 4: Verify it analyzes**

```bash
cd /Users/mostafamoaty/Desktop/Gameball/gameball-sample-app
export PATH="$HOME/development/flutter/bin:$PATH"
flutter pub get
flutter analyze 2>&1 | tail -3
```

Expected: `No issues found!`

- [ ] **Step 5: Verify stage 1 by hand**

```bash
./run.sh
```

Walk through, confirming each:

1. App opens on the storefront. **No modal** — in-app messaging has not been started.
2. Tap the SDK status chip to open the debug screen. It shows **In-app messaging: Not started**.
3. Tap **Start in-app messaging**. The **welcome modal** appears — header "Welcome back!", body about 1,250 points, two buttons "Later" and "Redeem". The image will fail to load (the fixture URL is not real); the modal must render regardless.
4. Tap the scrim outside the modal. It dismisses.
5. Debug screen now shows **Started**, and **Messages selected: 1**.
6. Go back to the storefront, open any product, tap **Add to cart**.
7. Because the welcome modal displayed under 30 seconds ago, **no modal appears** — the floor is holding. Wait 30 seconds and tap **Add to cart** again: the **cart nudge** modal appears ("Add one more item for 2x points").
8. Tap **Add to cart** again. **No modal** — the cart campaign has already been shown this run.
9. Return to the debug screen and tap **Stop in-app messaging**, then **Start** again. The welcome modal appears once more, because stopping reset the caps.

- [ ] **Step 6: Commit**

```bash
cd /Users/mostafamoaty/Desktop/Gameball/gameball-sample-app
git add lib
git commit -m "Add in-app messaging stage 1 harness

Wires a navigator key into MaterialApp and adds explicit start/stop controls
plus diagnostics to the Gameball debug screen.

Starting is deliberately manual rather than automatic on launch, so the app
demonstrates both states: the compatibility invariant with in-app messaging off,
and the feature with it on. The existing add_to_cart event on the product
details screen drives the custom-event trigger, so no new harness code was
needed to exercise it."
```

---

## Task 10: Sample app — widget usage, stages 2 and 3

**Files (all in `/Users/mostafamoaty/Desktop/Gameball/gameball-sample-app`):**
- Modify: `lib/screens/home_screen.dart` (a Gameball profile button in the app bar)
- Modify: `lib/gameball/gameball_service.dart` (a `showProfile` wrapper, a delayed event helper)
- Modify: `lib/screens/gameball_debug_screen.dart` (a delayed-trigger button)

**Interfaces:**
- Consumes: `GameballApp.showProfile`, `ShowProfileRequest`/`ShowProfileRequestBuilder`, and the stage-1 debug controls from Task 9
- Produces: nothing

- [ ] **Step 1: Add a showProfile wrapper to the sample service**

In `lib/gameball/gameball_service.dart`, add:

```dart
  /// Opens the Gameball profile widget, the way existing clients do today.
  void showProfile(BuildContext context) {
    final request = ShowProfileRequestBuilder()
        .customerId(GameballEnv.customerId)
        .showCloseButton(true)
        .build();

    _log('showProfile', 'customerId=${GameballEnv.customerId}');
    _app.showProfile(context, request);
  }
```

Add `import 'package:gameball_sdk/models/requests/show_profile_request.dart';`.

This chain is verified against `../gameball-flutter/lib/models/requests/show_profile_request.dart` and compiles as written. Other builder methods available if you want them: `openDetail`, `hideNavigation`, `widgetUrlPrefix`, `closeButtonColor`, `mobile`, `email`, `externalLinkCallback`, `widgetEventCallback`.

- [ ] **Step 2: Add a profile button to the storefront**

In `lib/screens/home_screen.dart`, add an icon button to the existing `AppBar.actions`, before `GameballStatusChip`:

```dart
          IconButton(
            icon: const Icon(Icons.card_giftcard),
            tooltip: 'Gameball profile',
            onPressed: () => widget.service.showProfile(context),
          ),
```

- [ ] **Step 3: Add a delayed trigger, so stage 3 is testable at all**

Stage 3 needs an event to fire **while the widget is open** — but the widget covers the screen, so nothing can be tapped to fire one. A scheduled trigger solves it.

In `lib/gameball/gameball_service.dart`:

```dart
  /// Fires [eventName] after [delay], so a trigger can be made to occur while
  /// the Gameball widget is covering the screen.
  void sendEventAfter(
    Duration delay,
    String eventName,
    Map<String, Object> metadata,
  ) {
    _log('scheduled event', 'will send "$eventName" in ${delay.inSeconds}s');
    Timer(delay, () => sendEvent(eventName, metadata));
  }
```

In `lib/screens/gameball_debug_screen.dart`, add a button beside the existing ones:

```dart
              OutlinedButton.icon(
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Fire add_to_cart in 5s'),
                onPressed: () {
                  widget.service.sendEventAfter(
                    const Duration(seconds: 5),
                    'add_to_cart',
                    <String, Object>{'productId': 'sku-001'},
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('add_to_cart fires in 5s — open the widget now'),
                    ),
                  );
                },
              ),
```

Match the existing button style in that file rather than copying this verbatim if they differ.

- [ ] **Step 4: Verify it analyzes**

```bash
cd /Users/mostafamoaty/Desktop/Gameball/gameball-sample-app
export PATH="$HOME/development/flutter/bin:$PATH"
flutter analyze 2>&1 | tail -3
```

Expected: `No issues found!`

- [ ] **Step 5: Verify stage 2 — the widget alone, in-app messaging off**

```bash
./run.sh
```

1. Do **not** start in-app messaging.
2. Tap the gift icon in the app bar. The Gameball widget opens as a near-fullscreen sheet with a web view. It will show an error or empty state unless `GB_API_KEY` is set — that is expected and irrelevant here; what matters is that it **opens and closes normally**.
3. Close it with its close button. The storefront is intact.
4. Open and close it twice more. No modal ever appears, no error, no leaked overlay.

This is the existing-client path on the new SDK version. Any regression here is a compatibility failure.

- [ ] **Step 6: Verify stage 3 — widget and in-app messaging together**

Still in the running app, in order:

1. Open the debug screen and tap **Start in-app messaging**. The welcome modal appears. Dismiss it via the scrim.
2. Wait 30 seconds so the floor clears. (The debug log timestamps make this easy to judge.)
3. On the debug screen, tap **Fire add_to_cart in 5s**, then immediately go back to Home and tap the **gift icon** to open the Gameball widget.
4. The event fires while the widget is open. **No modal appears** — the widget is undisturbed. This is contract item 2.
5. Close the widget with its close button. The **cart nudge modal now appears** — this is the deferral retry firing on widget close. **Without the pending-slot mechanism this step silently does nothing, so it is the load-bearing assertion of the whole task.**
6. Dismiss the modal. Reopen the debug screen and confirm **Pending campaign: —**.
7. Now the reverse order: tap **Stop**, then **Start** so the welcome modal shows. With it on screen, go to Home and open the widget. The widget opens over the modal; closing the widget leaves the modal still dismissible, and no exception is thrown.
8. Throughout, confirm only one Gameball modal is ever on screen at a time.

If step 5 fails, the bug is in `_retryPending` or in hook 3 (the widget-close notification), not in the evaluator.

- [ ] **Step 7: Commit**

```bash
cd /Users/mostafamoaty/Desktop/Gameball/gameball-sample-app
git add lib
git commit -m "Add Gameball widget usage for stage 2 and 3 validation

Adds a profile button to the storefront so the sample app exercises the widget
path existing clients already use, which the app previously had no coverage of
at all.

Together with the stage 1 controls this makes the widget and in-app messaging
interaction testable by hand: suppression while the widget is open, and the
deferred message appearing once it closes."
```

---

## Self-review

**1. Spec coverage.** Walked each spec section against the plan:

| Spec section | Covered by |
| --- | --- |
| Architecture, two flows | Task 7 (service sequencing) |
| Compatibility contract items 1–8 | Task 8 (prefixes, hooks, version, Stage 0 verification); contract item 2 (widget suppression) in Task 7 and verified in Task 10 |
| File layout | Tasks 1–8, plus the `iam_log.dart` deviation noted up front |
| Public API | Task 8 |
| Message contract + parsing rules | Task 1 (every rule has a test), Task 2 (fixture) |
| Backend contract alignment | Task 1 — case-insensitive enums and hex-or-int colours implemented and tested; the remaining rows are decisions, not code |
| Evaluation and capping | Tasks 3 and 4 |
| Presentation and deferral, back-button limitation | Tasks 6 and 7 |
| Analytics | Task 6 (interface), Task 7 (single-owner call sites) |
| Error handling tables | Task 7 tests for lifecycle/fetch/deferral; Task 6 tests for overlay/timer/idempotent dismissal; Task 5 for image failure |
| Testing strategy | Tasks 1–8 test files match the spec's list one-for-one |
| Staged validation 0–3 | Task 8 step 9 (stage 0), Task 9 (stage 1), Task 10 (stages 2 and 3) |
| Out of scope | Nothing in the plan touches any of it |

No gaps found.

**2. Placeholder scan.** No "TBD", no "add error handling", no "similar to Task N". Every code step has complete code.

The `EventBuilder` and `ShowProfileRequestBuilder` chains were checked against their source files and compile as written. One judgement call is left open on purpose: how the sample app's debug screen forces a rebuild after start/stop (Task 9, step 2). That depends on the shape of the existing `GameballStatus`/`copyWith` in the sample app, and either a `refresh()` method or a status field works — the requirement stated is only that the rows re-render.

**3. Type consistency.** Checked signatures across task boundaries:

- `parseCampaignsJson(String) -> List<InAppMessageCampaign>` — produced Task 1, consumed Task 2 ✓
- `parseColor(Object?) -> Color?` — produced and tested Task 1 ✓
- `triggerMatches(campaignTrigger, occurred)` — Task 1, consumed Task 4 ✓
- `CapState({shownCampaignIds, lastDisplayAt})` — Task 3, consumed Tasks 4 and 7 ✓
- `FrequencyCap.load/snapshot/recordDisplay/reset` — Task 3, consumed Task 7 ✓
- `selectCampaign({trigger, campaigns, capState, now})` / `isWithinFloor({capState, now})` — Task 4, consumed Task 7 ✓
- `GameballMessagePresenter.present({message, onShown, onButtonPressed, onDismissed}) -> bool` — Task 6, consumed Task 7; the fake in Task 7 implements the same signature ✓
- `MessageAnalytics.logImpression(message, {campaignId})` / `logButtonClick(message, {campaignId, buttonId})` — Task 6, consumed Task 7 ✓
- `InAppMessagingService` constructor params — Task 7, consumed Task 8 (`isHostWidgetOpen`, `emit` both used) ✓
- `GameballInAppMessage` field names (`autoDismissAfter`, `showCloseButton`, `isTestSend`) consistent across Tasks 1, 5, 6, 7 ✓
- `maxModalButtons` defined Task 1, used Task 1 parser and exported Task 8 ✓
- Barrel exports in Task 8 name only types that exist in Tasks 1 and 7 ✓

One inconsistency found and fixed while reviewing: the service exposes `pendingCampaign` while `GameballApp` exposes `pendingInAppMessageCampaign`. Both are intentional — the SDK-level name needs the qualifier — and Task 9 consumes the `GameballApp` one. Verified the sample app uses `pendingInAppMessageCampaign`, not `pendingCampaign`.
