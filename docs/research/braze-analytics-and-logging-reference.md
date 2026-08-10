# How Braze Collects Impressions, Tracking and Logs

Companion to `braze-in-app-messaging-reference.md`. That document covers how a message gets
*displayed*; this one covers everything that flows back out — what is measured, how it reaches
the backend, what each number means, and what Gameball still has to build.

## Scope and sources

| Tag | Meaning |
| --- | --- |
| **[src]** | Read directly out of the Braze Flutter SDK source, with `file:line` |
| **[doc]** | From Braze's public documentation |
| **[ours]** | Read out of `gameball-flutter` on `feature/in-app-messaging` |

- **Repo:** `github.com/braze-inc/braze-flutter-sdk`
- **Version:** `braze_plugin` 22.0.0 (`pubspec.yaml:3`)
- **Commit:** `b8e9546` (2026-08-07)
- **Native bridges at this version:** Braze Swift SDK 18.0.0, Braze Android SDK 43.0.0 (`CHANGELOG.md:4-5`)

> The sibling reference pins 21.0.0 / `ecdde249`. The in-app-message analytics surface is
> **unchanged** between 21.0.0 and 22.0.0 — only the version header there is stale.

Docs consulted: [In-app message reporting](https://www.braze.com/docs/user_guide/channels/in_app_messages/reporting),
[Metrics glossary](https://www.braze.com/docs/user_guide/data/activation/report_metrics/),
[SDK rate limits](https://www.braze.com/docs/developer_guide/sdk_integration/rate_limits),
[Network settings](https://www.braze.com/docs/developer_guide/network),
[Tracking sessions](https://www.braze.com/docs/developer_guide/analytics/tracking_sessions),
[Event User Log](https://www.braze.com/docs/user_guide/administer/global/workspace_settings/logs_and_alerts/event_user_log),
[Debugging the SDK](https://www.braze.com/docs/developer_guide/sdk_integration/debugging).

---

## 1. "Logging" means four different systems

Conflating them is the most common source of confusion, so name them up front. Only the first
reaches Braze's backend.

| # | System | Audience | Destination | Lifetime |
| --- | --- | --- | --- | --- |
| 1 | **Analytics events** | Marketers | Braze backend, batched | Permanent, drives reporting |
| 2 | **Diagnostic logs** | Developers | Device console | Process |
| 3 | **Event User Log** | Integrators | Braze dashboard | **30 days** [doc] |
| 4 | **SDK Debugger** | Integrators | Braze dashboard, exportable CSV | One paired session |

Sections 2–5 cover system 1. Sections 7–8 cover the rest.

---

## 2. The in-app-message analytics API is three calls

**[src]** `lib/braze_plugin.dart:322-347`. That is the complete surface — there is no fourth event.

| Dart | Android **[src]** `BrazePlugin.kt:352-379` | iOS **[src]** `BrazePlugin.swift:312-353` |
| --- | --- | --- |
| `logInAppMessageImpression(msg)` | `deserializeInAppMessageString(…)?.logImpression()` | `logImpression(using: braze)` |
| `logInAppMessageClicked(msg)` | `deserializeInAppMessageString(…)?.logClick()` | `logClick(buttonId: nil, using: braze)` |
| `logInAppMessageButtonClicked(msg, id)` | linear search of `messageButtons`, gated on `IInAppMessageImmersive` | `logClick(buttonId: idNumber.stringValue, using: braze)` |

### 2.1 The raw JSON string is the argument

All three send `inAppMessage.inAppMessageJsonString` — **not** the parsed model:

```dart
final Map<String, dynamic> params = <String, dynamic>{
  "inAppMessageString": inAppMessage.inAppMessageJsonString
};
_channel.invokeMethod('logInAppMessageImpression', params);
```

Native then **re-deserialises** that string to reconstruct a message object before logging.
Two consequences:

1. **The string is load-bearing.** Rebuilding a `BrazeInAppMessage` from parsed fields would
   break analytics. It must be passed through untouched.
2. **Parse failure is a silent no-op** on both platforms — Android via `?.`, iOS via an
   `if let` that simply falls through.

### 2.2 Button clicks behave differently per platform, from one Dart call

**iOS** passes the id straight through, stringified, with no validation **[src]**:

```swift
inAppMessage.logClick(buttonId: idNumber.stringValue, using: braze)
```

**Android** requires the button to exist on the message, and silently does nothing otherwise
**[src]** `BrazePlugin.kt:364-379`:

```kotlin
if (inAppMessage is IInAppMessageImmersive) {
    val buttonId = call.argument<Int>("buttonId") ?: 0
    for (button in inAppMessage.messageButtons) {
        if (button.id == buttonId) { inAppMessage.logButtonClick(button); break }
    }
}
```

So the same call can log on iOS and vanish on Android — and it no-ops entirely for
non-immersive types (slideup). This is also why the dashboard requires the
**"Identifier for Reporting"** to be `0` and `1`: button reporting is positional, and a
mismatch is invisible. **[doc]**

### 2.3 There is no dismissal event

Braze's own reporting table is explicit **[doc]**:

| Action | Click logged |
| --- | --- |
| Click message body (no buttons) | Yes — body click |
| Click a button | Yes — button click |
| **Click the close button (X)** | **No** |
| **Tap outside to dismiss** | **No** |
| **Close the app while displayed** | **No** |

"Shown and ignored" is therefore invisible in Braze. Nothing distinguishes a message a user
read and dismissed from one they never looked at.

---

## 3. The double-counting hazard

On the default integration **native already logs the impression and click** for the message it
displayed. Calling the Dart methods adds a second one.

Braze's own example app still guards this at 22.0.0 **[src]**
`example/lib/screens/user_management_screen.dart:31, 107-113`:

```dart
static const bool _automaticallyInteractIam = false;
…
if (_automaticallyInteractIam) {
  braze.logInAppMessageImpression(inAppMessage);
  braze.logInAppMessageClicked(inAppMessage);
  for (final button in inAppMessage.buttons) {
    braze.logInAppMessageButtonClicked(inAppMessage, button.id);
  }
}
```

Off by default, in their own sample, because switching it on double-counts. Dart-side logging
exists **only** for the take-over path.

**The lesson is architectural, not incidental:** two parties can log the same event, so the API
shape has to pick one owner. Braze made both possible and documented the hazard; the
alternative is to make host-side logging impossible.

---

## 4. What else the SDK collects, and what each signal is for

In-app messaging depends on all of it, not just the three message events.

| Signal | Dart | What it is used for |
| --- | --- | --- |
| **Session start / end** | implicit | Triggers the config sync · fires `session_start` · is the default conversion event ("Starts Session") · scopes "one message per session" |
| **Custom events** | `logCustomEvent` | Trigger matching · segmentation · conversion events |
| **Purchases** | `logPurchase` | Trigger matching (any / specific) · revenue · conversion |
| **Custom attributes** | 12 setter variants | Segmentation · Liquid personalisation · **locale selection** |
| **Identity** | `changeUser`, `addAlias`, `getDeviceId` | Profile consolidation — which is what makes "once per user" hold across devices |
| **Subscription state** | `setPushNotificationSubscriptionType`, subscription groups | Channel eligibility |
| **Attribution** | `setAttributionData` | Install-source segmentation |

A single event therefore does several jobs at once. `logCustomEvent('add_to_cart')` may fire a
trigger locally, update a segment server-side, and count as a conversion for a different
campaign — from one call.

### 4.1 Sessions [doc]

| Platform | Default session timeout |
| --- | --- |
| **Android** | **10 seconds** |
| **Swift** | **10 seconds** |
| Web | 30 minutes |

A session starts on foreground and a *new* one begins when the app returns to the foreground
after the timeout has elapsed. Overridable via `com_braze_session_timeout` (Android XML),
`configuration.sessionTimeout` (Swift) and `sessionTimeoutInSeconds` (Web).

Note that Braze's session timeout (10s) is **shorter than its display floor** (30s, §8.3 of the
sibling doc). That combination is deliberate on their side and has a consequence — see §10.2.

---

## 5. Transport: how events actually reach the backend [doc]

- **Batched automatically.** The SDK queues events and sends them in efficient batches rather
  than one request per event.
- **Flushed roughly every 10 seconds**, with network-aware behaviour that adjusts the rate to
  connection quality.
- **Offline-safe.** With no connection, data caches on device and uploads when connectivity
  returns. Events are not lost.
- **`requestImmediateDataFlush()`** forces a send when a test needs to see data now.
- **Rate limited by a token bucket**, and Braze deliberately publishes **no numbers**: *"Because
  limits adapt in real time, exact bucket sizes and static values are not provided."* Their
  guidance is behavioural — "track meaningful user actions and milestones" — rather than a quota.
- **`updateTrackingPropertyAllowList`** restricts which properties are collected. **iOS-only** —
  the Dart doc comment says "No-op on Android" **[src]** `lib/braze_plugin.dart:703`.

---

## 6. What the numbers mean

Verbatim definitions, with the denominator each rate uses. **[doc]**

| Metric | Definition | Rate denominator |
| --- | --- | --- |
| **Total Impressions** | "the number of times a message is viewed" — logged "only when the message becomes visible to the user on their screen" | count |
| **Unique Impressions** | "the total number of users who have viewed a message from a given campaign" | count |
| **Body Clicks** | a click on a message "that doesn't have buttons" | / Impressions |
| **Button 1 Clicks** | "the total number of clicks on Button 1 of the message" | / Impressions |
| **Button 2 Clicks** | as above, Button 2 | / Impressions |
| **Primary Conversions** | "the number of times a defined event occurred after interacting with or viewing a received message" | / Unique Recipients |
| **Conversion Rate** | "the percentage of times a defined event occurred compared to all recipients" | **in-app: / Unique Impressions** |

Three details that are easy to get wrong:

1. **Unique impressions use a calendar-day boundary in the workspace's time zone.** Two views on
   the same day count once; re-eligibility lets the count increment on a new day.
2. **In-app's conversion-rate denominator is unique impressions, not unique recipients.** Every
   other channel divides by recipients. In-app messaging has no "delivery" to divide by.
3. **Attribution anchors to the impression**, not the send, within a window of up to 30 days.

### 6.1 A measurement artifact Braze documents honestly

A control group can show a *higher* conversion rate than the variant, because rendering a
variant with large assets or Connected Content takes longer than rendering nothing. The
difference is display latency, not message quality. **[doc]**

---

## 7. Diagnostic logs — local, developer-facing, not analytics

**[src]** `lib/braze_plugin.dart:16-24, 933-947`:

```dart
enum BrazeLogLevel implements Comparable<BrazeLogLevel> {
  debug(500), info(800), error(1000);
}

void _brazeLog(String message, {BrazeLogLevel level = BrazeLogLevel.debug}) {
  if (level < BrazePlugin.logLevel) return;
  final customLogger = BrazePlugin.logger;
  if (customLogger != null) {
    customLogger(message, level);
  } else {
    log(message, level: level.value, time: DateTime.now(), name: 'BrazeFlutterSDK');
  }
}
```

Default threshold is `info` (`:29`). Dart owns the numeric values and ships the **whole enum map**
to native so native resolves thresholds from Dart rather than duplicating them
(`_syncLogLevel`, `:40-55`).

**Worth copying:** the pluggable `logger` hook. `dart:developer log()` is invisible in a plain
`flutter run`, which is exactly the problem this SDK hit and worked around with `debugPrint`.
A hook lets the host decide, instead of the SDK guessing which output channel is visible.

---

## 8. Dashboard-side tooling — three separate tools

| Tool | What it captures | Question it answers |
| --- | --- | --- |
| **Event User Log** | SDK/API activity and errors, in sections: Device Attributes, User Attributes, Events, **Campaign Events**, **Response Data**. Expandable raw JSON with error codes such as "invalid color value". Filterable by SDK/API type, app, period, user. **30-day retention** | "Did the impression arrive, and what did the server say?" |
| **SDK Debugger** | A paired debugging session: Settings → SDK Debugger → find a user by email / `external_id` / alias / push token → relaunch the app so init logs are captured → reproduce → End Session → export CSV. Needs "View PII" permissions | "Why didn't it display on *this* device?" |
| **Verbose logging** | Device console only, enabled manually | Local development |

The Event User Log is the one worth imitating soonest. Most "the message didn't show" reports
are answered by looking at one session-start response and one campaign event.

---

## 9. Gameball's current state — audited, not assumed

**[ours]** Read out of `lib/in_app_messaging/`.

### 9.1 What is already right

- **Three events, matching Braze's exactly**: `logImpression`, `logClick` (body),
  `logButtonClick` (`analytics/message_analytics.dart:9-23`).
- **Single-owner by construction.** `MessageAnalytics` is called only from the display path
  inside the SDK; hosts cannot reach it. The interface doc comment states why. This closes
  Braze's double-counting hazard (§3) at the API level rather than with a warning.
- **Recorded at display, not selection.** Both the frequency cap and the impression fire from
  the presenter's `onShown`, so a deferred or suppressed message does not burn its slot
  (`in_app_messaging_service.dart:320-327`).
- **Button ids are stable and carried on the button**, not positional — better than Braze's
  "Identifier for Reporting" convention.

### 9.2 The gaps this audit found, and what happened to them

All eight are now closed or reclassified. The wire contract they produced is
specified for the backend in
`docs/integration/in-app-message-analytics-backend-handoff.md`.

| # | Gap | Outcome |
| --- | --- | --- |
| 1 | **No endpoint** | **Built.** `POST /api/v4.0/integrations/mobile/in-app-messages/events`, with a status-code policy that distinguishes retry from discard |
| 2 | **No timestamp** | **Built.** `occurredAt`, ISO-8601 UTC, taken from the service's injected clock — so it is the moment it happened, and testable |
| 3 | **No correlation identity** | **Built.** `analyticsToken` on the campaign, echoed verbatim on every event, never parsed |
| 4 | **No batching, no persistence** | **Built.** `BatchedMessageAnalytics`: 10s cadence, immediate at 20 events, forced flush on background and on stop, outbox mirrored to disk after every change, 500-event ceiling |
| 5 | **Impression fired one frame early** | **Fixed.** `onShown` now runs from a post-frame callback, guarded so a message dismissed before it paints logs nothing |
| 6 | **No dismissal event** | **Built.** `dismiss`, suppressed when the user tapped anything, which makes at-most-one-terminal-event-per-impression an identity |
| 7 | **Body click requires an action** | **Not a defect — this audit was wrong.** `_wrapTappable` (`presentation/in_app_message_modal.dart:148-155`) returns the child unwrapped when `clickAction == null`, so an inert message never receives a surface tap at all. The early return in the service is unreachable defensiveness, not a dropped event |
| 8 | **`sessionTimeout` not configurable** | **Fixed.** A named parameter on `startInAppMessaging`, defaulting to 30s, with the reasoning from §10 in its doc comment. Passing a different value while messaging is already running logs rather than silently no-opping |

Two things worth keeping from the exercise. Gap 7 is a reminder that an audit of
one's own code is still a hypothesis until the call site is read — the defensive
branch looked like a dropped metric and was nothing of the kind. And gap 5 was
real but was not the whole story: fixing the timing does not fix the fact that a
message whose image never loads still counts, because the frame paints with a
placeholder. That belongs to asset prefetch, which is still open.

### 9.3 Still open

- **Asset prefetch.** Images load at display time, so a cold image pops in after
  the modal, and an image that never loads still produces an impression. Braze
  prefetches at sync and suppresses display on a failed download.
- **Refetch at every session start.** A warm resume fires the session-start trigger
  against the campaign list from the cold-start fetch.
- **Device and app context on the request.** Neither the fetch nor the events
  endpoint carries OS, OS version, app version or time zone, which is what platform
  targeting and local-time dayparting need.

---

## 10. Session timeout: why 30s, and whether to match Braze's 10s

### 10.1 It was a reasoned choice, not an inherited constant

**[ours]** `evaluation/frequency_cap.dart` sets the display floor to 30s (Braze parity), and
`in_app_messaging_service.dart:59-65` aligns the session timeout to it, with the rationale in
the code:

> Matched to `minimumIntervalBetweenDisplays` on purpose. A shorter timeout would create
> sessions that fire the session-start trigger while the display floor is still blocking,
> producing a dead zone where a message is selected and then silently suppressed. Braze's
> default is shorter than its floor and accepts that; here they are aligned so a new session can
> always show something.

### 10.2 The alignment is load-bearing, and provably so

A message can only display while the app is in the foreground. So for any warm resume:

```
time_since_last_display  ≥  time_spent_in_background
```

A new session requires `time_in_background ≥ sessionTimeout`. Therefore:

- **At 30s** — `time_in_background ≥ 30s` implies `time_since_display ≥ 30s`, so the display
  floor **can never block a warm session-start message**. The two constraints are exactly
  aligned.
- **At 10s** — `time_in_background ≥ 10s` allows `time_since_display` as low as 10s, which is
  inside the 30s floor. The trigger fires, a campaign is selected, and the floor drops it. A
  real dead zone, hit by any 10–30 second app switch.

### 10.3 Recommendation: keep 30s

Three reasons, in order of weight:

1. **Lowering it to 10s alone creates the dead zone above.** Matching Braze properly would mean
   lowering the floor too — and the floor is the only marketing-pressure control the module has,
   and the one value Braze's own docs treat as load-bearing.
2. **It compounds with the missing refetch.** Once campaigns are re-fetched at every session
   start (gap F1 in the config-UX register), a 10s timeout means a network round trip on almost
   every app switch. 30s makes that affordable.
3. **Braze's 10s is aggressive even for Braze.** Their own Flutter example app sets
   `configuration.sessionTimeout = 1` for testing, and their Web SDK — where they were not
   constrained by mobile lifecycle conventions — defaults to **30 minutes**. 10s is a mobile
   platform artifact, not a considered product position.

**What to change instead:** plumb `sessionTimeout` through `startInAppMessaging` (gap 8 above)
so a host that wants Braze-like session counts can opt in, and document that lowering it below
the display floor reintroduces the dead zone.

---

## 11. What the analytics contract needs

All four are now implemented on the SDK side and specified for the backend in
`docs/integration/in-app-message-analytics-backend-handoff.md`. They are kept here
because the *reasons* live in §6, and the reasons are what a reviewer needs.

1. **An opaque correlation token, echoed back verbatim.** Braze's `trigger_id`. One field that
   resolves server-side to campaign + variant + dispatch, closing variant attribution,
   correlation and conversion anchoring at once. The SDK never interprets it.
2. **`occurredAt` on every event.** Without it, "unique impressions per user per calendar day in
   the workspace time zone" is not computable, and conversion windows have no anchor.
3. **The in-app conversion-rate denominator is unique impressions.** State it, or the backend
   will build the email formula (÷ unique recipients) and the number will be quietly wrong.
4. **Batch and persist client-side before shipping the endpoint.** Braze flushes every ~10s and
   caches offline. An impression logged and then lost on app kill is a silently wrong metric,
   which is worse than a missing one.

A payload consistent with all four:

```json
POST /in-app-messages/events
{
  "analyticsToken": "eyJjbXAiOiJ…",
  "event": "impression",
  "buttonId": null,
  "occurredAt": "2026-08-10T09:14:22Z"
}
```

`event` is one of `impression`, `click`, `button_click`, and — if we take the free win Braze
does not offer — `dismiss`.

---

## Appendix: verification pointers

| Claim | Where to check |
| --- | --- |
| IAM analytics API is three calls | `lib/braze_plugin.dart:322-347` |
| Analytics round-trips the raw JSON | `lib/braze_plugin.dart:325` → `BrazePlugin.kt:352-362` / `BrazePlugin.swift:322-338` |
| Android button click is a gated linear search | `BrazePlugin.kt:364-379` |
| iOS stringifies the button id unchecked | `BrazePlugin.swift:340-353` |
| Example app guards double-counting | `example/lib/screens/user_management_screen.dart:31, 107-113` |
| Log level is Dart-owned with a pluggable sink | `lib/braze_plugin.dart:16-24, 40-55, 933-947` |
| Tracking allow list is iOS-only | `lib/braze_plugin.dart:703` |
| Native bridge versions | `CHANGELOG.md:4-5` |
| Our impression fires before paint | `lib/in_app_messaging/presentation/overlay_presenter.dart:58-59` |
| Our body click needs an action | `lib/in_app_messaging/in_app_messaging_service.dart:336-341` |
| Our session timeout is not plumbed | `lib/gameball_sdk.dart:305-318` |
