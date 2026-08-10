# In-App Messaging — Backend Integration Design

Supersedes the wire-format half of `2026-08-05-gameball-in-app-messaging-mvp-design.md`.
Everything that spec said about architecture, layering, seams and presentation still stands;
this replaces only the parts that guessed at a contract the backend has since specified.

**Source of truth for the backend side:** `sdk-endpoints-reference.md` (backend team, Aug 2026).

## Why this exists

The MVP was built against a proposed contract, because none existed. One exists now, and it is
different in shape from what we proposed — while independently adopting the two things we argued
hardest for: an opaque dispatch identifier and idempotent event ingestion keyed on a
client-generated uid.

Two facts frame the work:

1. **Neither endpoint is implemented yet.** `grep -ri inapp` across `g-backend-v2@alpha` returns
   nothing. This is co-design, not integration against something fixed.
2. **Nothing has shipped on our side either.** The module lives on an unpushed branch, so its
   public API can still change freely. Only the pre-existing widget and events APIs are frozen.

## Decisions taken

| # | Decision | Choice | Rationale |
| --- | --- | --- | --- |
| 1 | **Identity** | V1 convention: `?playerUniqueId={customerId}` | The SDK already holds the external customer id. Verified equivalent to the backend's `PlayerUniqueId` (`OrderPointsV4.cs:13-18` aliases the two). Avoids coupling messaging to `initializeCustomer` completing |
| 2 | **Encrypted playerId** | Not used | Verified unobtainable: it is a TripleDES hex string keyed by a server secret (`Cipher.cs:16`), produced only into server-generated URLs, and never returned in any JSON response. `initializeCustomer` returns the **raw** `long` (`CustomerCreationResponse.cs:12`) |
| 3 | **Auth** | `APIKey` always; `X-GB-TOKEN` when the integration has a session token | Already plumbed. See open item O2 |
| 4 | **Trigger matching** | By name, for both the event and each metadata filter — the backend is adding both | Numeric `eventId` and `metadataId` are unresolvable on-device: the mapping lives only in the backend's database, and a client-side matcher has to work offline in microseconds |
| 5 | **Purchases** | Treated as the `purchase` event | The backend model has no purchase trigger type |
| 6 | **Analytics identity** | `dispatchId` replaces our `analyticsToken` | Same concept, their name |

## What does not change

The layering survives intact, which is the point of having had seams:

- `trigger_evaluator.dart` — pure selection function, untouched
- `property_filter.dart` — operators and matching, untouched
- `overlay_presenter.dart`, `in_app_message_modal.dart` — presentation, untouched
- `message_navigator.dart` — routing, untouched
- `batched_message_analytics.dart` — buffering, persistence, retry; only the payload it serialises changes
- The four seams (`GameballMessageSource`, `GameballMessagePresenter`, `FrequencyCap`,
  `MessageAnalytics`) keep their shapes

What changes is the wire layer at both ends, plus real persistence.

---

## Phase 1 — Wire layer

### 1.1 Endpoints

```dart
const botsInAppSyncPath   = "/api/v1.0/bots/inapp/sync";
const botsInAppEventsPath = "/api/v1.0/bots/inapp/events";
```

Both take `?playerUniqueId={customerId}`. This replaces `inAppMessageEventsPath`, which was our
own proposal and is now dead.

### 1.2 The bots envelope

Every response is wrapped:

```json
{ "response": { … }, "success": true, "errorMsg": null, "errorCode": 0, "liveMode": true }
```

**`success: false` arrives with HTTP 200.** This is the single most important behavioural change,
because the analytics transport currently treats any 2xx as "accepted, discard the batch" — which
would silently drop events the server explicitly rejected. Three documented cases return 200 with
`success:false`: a batch over 50 events, an empty batch, and a batch where every event is invalid.

Parsing rule: **unwrap `response` only when `success` is true.** Otherwise log `errorMsg` and
`errorCode` and treat it as a failure, choosing retry or discard per §3.4.

### 1.3 Sync request

```json
{ "platform": 1, "locale": "en", "appVersion": "3.2.1", "sdkVersion": "1.0.0" }
```

All four are already obtainable — `getDevicePlatform()` (1=iOS, 2=Android),
`handleLanguage(_lang, _customerPreferredLanguage)`, `PackageInfo.fromPlatform()`,
`getSdkVersion()`. This closes the device-context gap the earlier audit raised, for free.

Note their locale fallback chain is *device locale → player's preferred language → en → any*,
while `handleLanguage` prefers the **customer's** language over the app's. Ours is the better
order and matches what the widget already does; we send our resolution and let them fall back.

### 1.4 Campaign model

| Theirs | Ours now | Ours after |
| --- | --- | --- |
| `campaignId` (int) | `id` (String) | `campaignId` (int) |
| `variationId` (int) | — | `variationId` (int?) |
| `dispatchId` (String) | `analyticsToken` (String?) | `dispatchId` (String?) |
| `name` (String) | — | `name` (String?) |
| `priority` (int) | `priority` (int) | unchanged, higher wins |
| `messageType` (int) | `type` (String enum) | int → `GameballMessageType`; unknown → `unsupported` |
| `contentMode` | — | anything but `"prerendered"` → skip the campaign |
| `expiresAt` | — | `expiresAt` (DateTime?), enforced locally |
| `isTest` | `isTestSend` | `isTest`; semantics change — see §3.5 |
| `cooldownSeconds` (top level) | client constant | server-driven, per sync |

**Identity keys.** The frequency cap and the persisted caches key on `campaignId` alone, not on
`variationId`: repeatability is a property of the campaign, while the variation is which arm *this
user* was assigned. Telemetry carries both.

### 1.5 The `content` / `locale` split

Their payload separates untranslated styling (`content`) from translated text (`locale`), with
buttons appearing in both and **paired by string id**. Our model is flat, and that stays — the
parser joins the two halves.

```
content.buttons[]  ──┐
                     ├─→ GameballMessageButton (id, text, action, style)
locale.buttons[]   ──┘        paired on `id`; render only ids present in both
```

Mapping:

| Theirs | Ours |
| --- | --- |
| `locale.header`, `locale.message` | `header`, `body` |
| `content.imageUrl` | `imageUrl` |
| `content.colors.{background,text,header,closeButton,border,frame}` | `GameballMessageStyle` |
| `content.textAlignment.{header,body}` | `headerAlign`, `bodyAlign` |
| `content.closeBehaviour: swipe\|button\|both` | `showCloseButton` = contains `button`; `dismissOnScrimTap` = contains `swipe` |
| `content.autoDismissSeconds` | `autoDismissAfter` (Duration) — see open item O3 |
| `content.action` | `clickAction` |
| `content.extras` | `extras` |
| `content.font` | **ignored** — host theme only, a deliberate no |

**Button ids become Strings.** `GameballMessageButton.id` is currently `int` and is exported. It
becomes `String`. Not a compatibility break, because the module is unreleased (see "Why this
exists"). Analytics carries the string through unchanged, which is strictly better than Braze's
positional `"0"`/`"1"` convention.

### 1.6 Triggers

```json
"trigger": {
  "type": "session_start" | "event",
  "eventId": 812, "eventName": "add_to_cart",
  "metadataLogicalOperator": "And",
  "metadataFilters": [ { "metadataId": 4051, "metadataKey": "productId",
                         "value": "electronics", "operator": "Is" } ],
  "repeatable": false,
  "minIntervalSeconds": null
}
```

- `session_start` → `GameballSessionStartTrigger`
- `event` → `GameballCustomEventTrigger(eventName, filters)`
- Numeric `eventId` / `metadataId` are **parsed and discarded**. They are the backend's keys; the
  SDK matches on names.
- **Field spelling is read tolerantly.** The metadata name was agreed verbally, so the parser
  accepts `metadataKey` *or* `metadataName`, and the same for `eventName`. This follows the MVP
  spec's existing principle of not forcing the backend into one spelling, and costs one `??` per
  field. Whichever they ship, it parses.
- A filter whose name is missing → **the campaign is skipped** with a log naming it. Silently
  matching on an absent property is how filters become decorative; skipping is loud enough to
  notice and safe enough to ship.
- `metadataLogicalOperator` other than `And` → skip the campaign with a log, until O4 is settled.
- **`GameballAnyPurchaseTrigger` and `GameballSpecificPurchaseTrigger` become unreachable** from
  this backend and are removed. Instead `logPurchase` must produce an occurrence that satisfies
  `GameballCustomEventTrigger('purchase')`, with `productId`, `price`, `currency` and `quantity`
  folded into the filterable properties exactly as they are today. Without this change a
  purchase-triggered campaign would silently never fire.

### 1.7 The identity object

One internal owner of "who are we", written by `initializeCustomer` and `startInAppMessaging`,
holding `customerId` and `sessionToken`. Rules:

- **A per-call `customerId` always wins.** The object is a cache of the last explicitly supplied
  identity, never a substitute for one — so every existing client behaves identically.
- Injected at the service boundary, not another `static` on `GameballApp`. Static mutable state
  has already leaked between tests twice in this module.
- Every customer-scoped store keys on its `customerId` and **discards on mismatch** at load.

This exists in phase 1 because phase 2's persistence needs the key, and retrofitting a key onto
stored records is worse than designing it in. It also retires the `_inAppMessagingCustomerId`
static added for the analytics sender.

---

## Phase 2 — Durability

Their behaviour checklist requires state we currently keep only in memory.

### 2.1 Persisted campaign cache

*"On sync failure keep the previous unexpired cache."* So campaigns survive launches.

- Stored under a key scoped to `customerId`; a mismatch discards rather than reuses.
- Filtered by `expiresAt` on read, so an expired campaign never reaches the evaluator.
- Sync success **replaces the entire cache**; sync failure leaves it intact.

### 2.2 Persisted display history

*"Non-repeatable displayed once → never again (locally too, don't wait for the server)."*

`InMemoryFrequencyCap` resets every launch, so today a once-ever campaign reappears on every cold
start. Replaced by a persisted history of `campaignId → lastDisplayedAt`, which serves three
rules at once:

| Rule | Source |
| --- | --- |
| `repeatable: false` → never again | presence in the history |
| `repeatable: true` → after `minIntervalSeconds` since **its** last display | that campaign's timestamp |
| global floor between any two displays | the most recent timestamp overall, vs `cooldownSeconds` |

`minimumIntervalBetweenDisplays` stops being a constant and becomes the synced `cooldownSeconds`,
defaulting to 30 when absent.

### 2.3 Sync on every session start

Currently we fetch once in `start()`; a warm resume evaluates the cold-start list. Their contract
says sync per session start, which is also how edits, expiries and eligibility changes land.

`onAppResumed` gains a sync before evaluating, and must not block the session-start evaluation on
it — a failed sync still evaluates against the cache.

### 2.4 Asset prefetch

Not in their checklist, but implied by *"impression timing accuracy matters most"*: images
currently load at display time, so an impression is logged for a message whose artwork appears a
beat later. `precacheImage` at sync, and treat a failed prefetch as a reason to skip rather than
show a broken frame.

---

## Phase 3 — Events endpoint

### 3.1 Event shape

```json
{
  "platform": 1,
  "events": [
    { "eventUid": "…", "dispatchId": "…", "campaignId": 2041, "variationId": 4,
      "type": "impression", "occurredAt": "2026-08-10T09:14:22Z",
      "buttonId": "cta", "url": "https://…" }
  ]
}
```

| Ours now | Becomes |
| --- | --- |
| `eventId` | `eventUid` |
| `campaignId` (String) | `campaignId` (int) + `variationId` |
| `analyticsToken` | `dispatchId` |
| `messageId` | **dropped** — they do not want it |
| `isTestSend: true` | **dropped** — see §3.5 |
| `event: "button_click"` | `type: "click"` + `buttonId` |
| — | `url`, on a click whose action was `open_url` |
| — | `platform`, once per batch |

### 3.2 Merging `button_click` into `click`

Their vocabulary is `impression | click | dismiss | submit`. A button tap is a `click` carrying
`buttonId`; a surface tap is a `click` without one. `GameballMessageEventType.buttonClick` is
removed and `buttonId` presence becomes the discriminator.

The service's existing rule stands and is worth keeping: **a dismissal is suppressed when anything
was tapped**, so at most one terminal event follows each impression. Their doc defines `dismiss`
as *"left the screen without click-through"*, which is the same rule.

### 3.3 Batching

| Setting | Ours now | Becomes |
| --- | --- | --- |
| Batch ceiling | 500 | **50** — over-50 is a documented `success:false` |
| Timer | 10s | **30s** |
| Size trigger | 20 | **10** |
| Also flush on | background, stop | background, stop, **immediately before `open_url` / `navigate`** |

That last one is theirs and it is a good idea: the app is about to be sent elsewhere, possibly not
to return. `_act()` gains an awaited flush before executing either action, bounded by a short
timeout so a dead network cannot delay a tap.

An outbox over 50 flushes in chunks, oldest first.

### 3.4 Response handling

```json
{ "response": { "accepted": 3, "rejected": 1 }, "success": true, … }
```

- `success: true` → clear the whole batch. `rejected` events *"will never succeed, don't retry
  them"*, and since the response does not say which, clearing all is both correct and the only
  option. Log the count.
- `success: false` → do **not** clear. Retry, except where `errorMsg` indicates a permanently
  malformed batch, which discards to avoid blocking the FIFO outbox behind poison.
- HTTP 401/403 → discard; retrying an auth failure cannot help.
- HTTP 5xx, 408, 429, network error → retry.

The existing three-way `GameballAnalyticsSendResult` already models this; only the mapping moves
from status codes to the envelope.

### 3.5 Test sends report nothing

Their rule: *"isTest:true → display normally, report NO telemetry."* We currently send
`isTestSend: true` on the event and let the backend decide. That inverts: the event is never
created. `isTest` stays on the message so the debug screen can surface it.

---

## Out of scope

Deliberately not in this work, and unaffected by it:

- **Message types beyond Modal** — Slideup, Fullscreen, HtmlFullscreen, EmailCapture. Unknown
  `messageType` already skips safely, so these arrive as no-ops rather than errors.
- **The `submit` event** and email capture.
- **The HtmlFullscreen sandbox** and its JS bridge.
- **`log_event`, `log_attribute`, `request_push_permission` actions.** The first two are close to
  free once the identity object exists; push permission needs a plugin.
- **`content.media` video**, `orientation`, `slideFrom`, `iconUrl`, custom fonts.
- **Dayparting in local time** — their sync request carries no time zone.
- **The `sendEvent` durability question** — a separate decision, recorded in
  `docs/research/braze-analytics-and-logging-reference.md`.

---

## Open items

Each has a fallback so none blocks starting.

| # | Item | Fallback if unanswered |
| --- | --- | --- |
| ~~O1~~ | ~~`metadataKey` on `metadataFilters`~~ — **resolved.** The backend is adding the metadata name alongside `eventName`. Numbering kept stable for anything already citing O2–O7 | — |
| **O2** | Does V1 honour `X-GB-TOKEN` when present? V1 is documented as `APIKey` only, and the API key ships in the app binary — so without a token cross-check, anyone holding it can read every campaign's content and post telemetry for arbitrary customers | Send it anyway; harmless if ignored. Record the exposure |
| **O3** | Is `autoDismissSeconds` valid on Modal? Their doc lists it under Slideup | Honour it on Modal if present |
| **O4** | Full `metadataFilters.operator` vocabulary. Only `"Is"` is documented; we implement seven | Map `Is` → equals; skip campaigns using unknown operators |
| **O5** | Are numeric filter values JSON numbers or strings? The example shows `"value": "electronics"` | Coerce: attempt numeric parse for ordering operators, fall back to string compare |
| **O6** | Is `metadataLogicalOperator: "Or"` needed? | Support `And` only; skip others |
| **O7** | Any cap on the `messages` array? | None assumed; the cache is bounded by whatever arrives |

---

## Testing

- **Fixtures rewritten** to the bots envelope and shape. `StubMessageSource` keeps its role as the
  offline fixture source; only its payload changes, which keeps the sample app working throughout.
- **Parser tests** for the envelope, `success:false` at HTTP 200, the content/locale join, button
  pairing by id, unknown `messageType` / `contentMode`, and a missing `eventName` (the O1 fallback).
- **Persistence tests**: cache survives a restart, is discarded on customer mismatch, expired
  campaigns are dropped on read, and a failed sync preserves the previous cache.
- **History tests**: non-repeatable never re-shows across a simulated restart; repeatable respects
  its own interval; the global cooldown comes from the synced value.
- **Transport tests**: the 50 cap chunks, `success:false` does not clear, flush-before-navigate
  happens, and `isTest` produces no events at all.
- **The two end-to-end tests added for event metadata must keep passing** — they exist because
  filtered campaigns silently failed once already.

## Compatibility

Unchanged from the MVP spec's contract, with one addition: **the in-app messaging module's own
public API is not yet frozen**, because nothing has been released. `GameballMessageButton.id`
changing from `int` to `String`, and the removal of the two purchase trigger classes, are
therefore free. The widget API, `initializeCustomer`, `sendEvent` and `logPurchase` signatures all
stay exactly as they are.
