# In-App Message Analytics — Backend Handoff

**Audience:** backend engineers implementing in-app message analytics.
**Status:** the Flutter SDK side is implemented and tested. It will call the
endpoint below as soon as it exists. Nothing here is speculative — every field,
header and status-code behaviour described is what the shipped client actually does.

**What we need from you:** one new endpoint, one optional field added to the
campaigns response, and answers to the nine questions in §9.

---

## 1. The short version

The SDK reports **four events** about each in-app message: `impression`, `click`,
`button_click`, `dismiss`. It buffers them, batches them, persists them across app
restarts, and retries until you accept them.

```
POST {base}/api/v4.0/integrations/mobile/in-app-messages/events

{
  "audience": { "type": "customer", "customerId": "customer-123" },
  "events": [
    {
      "eventId": "8f14e45f-ea8b-4a1f-9f1d-2b3c4d5e6f70",
      "event": "impression",
      "campaignId": "cmp_welcome_modal",
      "messageId": "msg_welcome_v1",
      "occurredAt": "2026-08-10T09:14:22.184Z",
      "analyticsToken": "eyJjbXAiOiJ…"
    },
    {
      "eventId": "1c9f0a22-77bd-4c0e-8b31-9a0d5e2f1c44",
      "event": "button_click",
      "campaignId": "cmp_welcome_modal",
      "messageId": "msg_welcome_v1",
      "occurredAt": "2026-08-10T09:14:29.902Z",
      "analyticsToken": "eyJjbXAiOiJ…",
      "buttonId": 1
    }
  ]
}
```

Two rules matter more than anything else in this document:

1. **Deduplicate on `eventId`.** Delivery is at-least-once. If you do not
   deduplicate, a badly timed app kill inflates impression counts.
2. **Return 2xx for anything you accept *or intend to ignore*.** A 4xx makes us
   discard the batch; a 5xx makes us retry it forever. See §5.

---

## 2. Request

### 2.1 Endpoint

```
POST {apiPrefix}/api/v4.0/integrations/mobile/in-app-messages/events
```

`{apiPrefix}` defaults to `https://api.gameball.co` and is overridable per
integration, exactly like every other call the SDK makes. **The path is our
proposal, chosen to match `/api/v4.0/integrations/mobile/logs`.** If you want a
different one, tell us — it is a one-line constant.

### 2.2 Headers

Identical to every other SDK request; produced by the same helper.

| Header | Value | Notes |
| --- | --- | --- |
| `Content-Type` | `application/json; charset=UTF-8` | |
| `ApiKey` | the integration's API key | |
| `Lang` | resolved language code | The customer's preferred language when known, otherwise the app's |
| `x-gb-agent` | `GB/flutter/<sdkVersion>` | e.g. `GB/flutter/1.9.0` |
| `X-GB-TOKEN` | session token | **Only present when the integration uses session tokens** |

### 2.3 Body

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `audience` | object | yes | Who the events belong to. Currently always `{"type":"customer","customerId":"…"}` — the same shape as the campaigns request, so a future device-scoped variant is additive |
| `events` | array | yes | 1 to 50 events per request, **oldest first** |

### 2.4 One event

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `eventId` | string (UUID v4) | yes | **Idempotency key.** Generated on the device, unique per event, stable across retries |
| `event` | string enum | yes | `impression` · `click` · `button_click` · `dismiss` |
| `campaignId` | string | yes | The campaign's `id` from the campaigns response |
| `messageId` | string | yes | The message's `id` from the campaigns response |
| `occurredAt` | string, ISO-8601 UTC | yes | When it happened **on the device**, always UTC with a `Z` suffix and millisecond precision |
| `analyticsToken` | string | no | Echoed verbatim from the campaign. **Omitted, not null,** when the campaign carried none |
| `buttonId` | integer | no | **Present only on `button_click`.** The `id` of the button from the campaign payload |
| `isTestSend` | boolean | no | **Present only when true.** Set when the campaign's message had `isTestSend: true` |

Absent optional fields are **omitted from the JSON entirely**, never sent as
`null`. That means `"buttonId" in event` is a reliable test for "a button was
tapped".

---

## 3. What each event means, precisely

### `impression` — the message became visible

Logged **once**, from a post-frame callback after the first frame containing the
message has actually painted. Not when the campaign is selected, not when the
overlay is inserted.

This distinction is deliberate and it is why the number is trustworthy. Braze
defines an impression as logged "only when the message becomes visible to the user
on their screen", and an earlier version of our client fired at insertion time —
one frame too early, which counted an impression for a message the user could never
have seen if the app was backgrounded in that instant.

Consequences for you:

- An impression means a human could see it. It is the honest denominator.
- A campaign that is selected and then suppressed (frequency cap, host deferral,
  no surface available) produces **no** impression.
- A campaign deferred and shown later produces exactly one impression, at the
  later time.

### `click` — the message surface itself was tapped

Only possible when the campaign set a message-level action. A message with no
message-level action is not tappable at all, so an inert message produces no
`click` — there is nothing to click.

This is Braze's "Body Clicks".

### `button_click` — a button was tapped

Carries `buttonId`, taken from the button in the campaign payload.

**We do not use Braze's positional convention.** Braze requires the marketer to set
an "Identifier for Reporting" to `0` and `1` for Button 1 / Button 2 reporting to
work at all, and a mismatch silently reports nothing. Our `buttonId` is whatever
you put on the button, carried through unchanged. **Please assign `0` and `1`
consistently anyway**, so "Button 1 clicks" means the same thing across campaigns.

### `dismiss` — the message left without being tapped

Covers the close button, a tap on the scrim, the Android back button, and
auto-dismiss expiry.

**Braze has no equivalent event.** Their own reporting explicitly logs nothing for
the close button, for tapping outside, or for backgrounding the app — so "shown and
ignored" is invisible in Braze. It costs us one event, and it gives you the
denominator for genuine indifference.

### 3.1 The identity you can rely on

Per impression there is **at most one terminal event**: `click`, `button_click`, or
`dismiss`, never two. A tap suppresses the dismissal that follows it, which is
enforced in the client and covered by tests.

```
impressions = clicks + button_clicks + dismisses + (displays interrupted by app death)
```

The last term is the only leak, and it is unavoidable: if the process is killed
while a message is on screen, the impression was already sent but no terminal event
ever will be. Treat a missing terminal event as "unknown", not as a dismissal.

---

## 4. Delivery behaviour — what to expect on the wire

| Behaviour | Detail |
| --- | --- |
| **Batching** | One request per burst, not per event |
| **Cadence** | A non-empty buffer is sent after **30 seconds**, or immediately once **10 events** accumulate |
| **Forced flush** | When the app goes to the background, and when in-app messaging stops (logout) |
| **Persistence** | The unsent buffer is written to device storage after every change, so an impression logged one second before a force-quit still arrives — on the **next launch** |
| **Ordering** | Oldest first within a batch. **Across batches, expect out-of-order arrival.** A batch stranded by a dead network can arrive after later ones |
| **Lateness** | An event can arrive **hours or days** after `occurredAt`. Never infer time-of-event from time-of-receipt |
| **Batch size** | 1 to 50 events per request. The outbox holds up to 500 and flushes in chunks of 50, so a long offline period arrives as several requests rather than one |
| **Ceiling** | The outbox holds 500 events. Beyond that the **oldest are dropped** and it is logged on the device |
| **Concurrency** | One request in flight at a time, per app instance |

**Practical consequence:** the endpoint must be safe to call with a batch you have
already seen, in an order you did not expect, describing something that happened
last Tuesday.

---

## 5. Status codes — this part changes client behaviour

| You return | We do |
| --- | --- |
| **2xx** | Drop the batch. Done |
| **408, 429, any 5xx** | Keep the batch and retry later |
| **network error / timeout** | Keep the batch and retry later |
| **any other 4xx** (400, 401, 403, 404, 422…) | **Discard the batch permanently**, with a loud device log |

The 4xx rule exists because the outbox is FIFO. A batch that is retried forever
sits at the front and blocks every event logged after it, so one malformed payload
would take *all* analytics down until the 500-event ceiling rotated it out.
Discarding loses that batch and nothing else.

**What this means for you:**

- If you receive an event type you do not store — say you decide not to keep
  `dismiss` — **return 2xx and ignore it.** A 422 would make us throw away the
  impressions in the same batch.
- Reserve 4xx for genuinely unrecoverable requests: bad API key, malformed body.
- Use 429 for throttling, never 400.

---

## 6. The one change to the campaigns response

Add an optional `analyticsToken` to each campaign object:

```json
{
  "campaigns": [
    {
      "id": "cmp_welcome_modal",
      "priority": 100,
      "analyticsToken": "eyJjbXAiOiI1YmE1MzE5OGJmNWNlYTQ0NmIxNTNiNmIiLCJ2IjoiYiJ9",
      "trigger": { "type": "session_start" },
      "message": { "…": "…" }
    }
  ]
}
```

**The SDK treats it as opaque.** It is never parsed, validated, inspected or
shortened — only stored and echoed back on every event for that campaign. Encode
whatever you need in it.

### Why this matters more than it looks

This is Braze's `trigger_id`, and adopting it answers four questions with one field
because they are all the same question — *which exact send was this?*

1. **Which A/B variant displayed.** `campaignId` cannot say. Without a token,
   variant reporting is impossible no matter what you build server-side.
2. **Which dispatch.** Distinguishes "shown from the campaign as it was on Monday"
   from "shown after Tuesday's edit".
3. **Conversion attribution.** Anchors a conversion to a specific exposure.
4. **Re-eligibility bookkeeping.** Identifies which send a user already received.

Suggested contents (entirely your call): campaign id, variant id, a dispatch or
config version, and the user id, signed or encrypted. Keep it under ~512 bytes —
it is repeated on every event.

If you omit it, everything still works: `campaignId` and `messageId` carry enough
for impression and click reporting. You just cannot do variants.

---

## 7. Metrics to implement, and the two easy ways to get them wrong

Definitions taken from Braze's published glossary, because matching them means our
numbers are comparable to a tool the market already understands.

| Metric | How to compute it |
| --- | --- |
| **Total impressions** | Count of `impression` events, deduplicated by `eventId` |
| **Unique impressions** | Distinct users per campaign **per calendar day** — see below |
| **Body clicks** | Count of `click` |
| **Button N clicks** | Count of `button_click` grouped by `buttonId` |
| **Dismissals** | Count of `dismiss`. No Braze equivalent |
| **Click-through rate** | clicks ÷ **total impressions** |
| **Conversion rate** | primary conversions ÷ **unique impressions** |

### 7.1 Unique impressions use a calendar-day boundary

Braze's rule: multiple views by the same user on the same day count **once**, where
the day boundary is **the workspace's time zone**. Re-eligibility lets the count
increment on a new day.

This is computable only because every event carries `occurredAt`. Do not use
receipt time — a batch delayed past midnight would land on the wrong day.

### 7.2 The in-app conversion-rate denominator is unique impressions

Every other channel divides by unique *recipients*. In-app messaging has no
"delivery" to divide by, so Braze divides by unique impressions, and so should we.

This is the single most likely thing to be implemented wrong, because the email
formula is right there and looks reusable. It is not.

### 7.3 Conversion attribution anchors to the impression

Not to the send, and not to the fetch. The window runs from the impression's
`occurredAt` and can be up to 30 days.

---

## 8. What the SDK does *not* do

So nobody waits on us for it:

- **No aggregation or deduplication.** We send raw events. Uniqueness, rates and
  conversion attribution are entirely server-side.
- **No conversion tracking.** The SDK has no notion of a conversion event. You
  attribute by correlating the impression with events that already reach you
  through `sendEvent` and `logPurchase`.
- **No device or app context on this endpoint.** Only `x-gb-agent` identifies the
  client. OS, OS version, app version and time zone are a separate known gap that
  affects platform targeting and dayparting; if you need them here too, say so and
  we will add the same block to both requests.
- **No delivery receipts.** There is no "message received" event, only "message
  became visible".
- **No retry after logout.** `stopInAppMessaging` flushes once and stops
  scheduling. Anything still queued goes out on the next launch.

---

## 9. What we need decided

Nine questions. The first three block us; the rest we can proceed without.

1. **Confirm the endpoint path**, or give us yours.
2. **Confirm the status-code policy in §5** — specifically that you will return
   2xx for event types you choose not to store.
3. **Confirm you deduplicate on `eventId`.** Without it, impression counts inflate
   on app kills.
4. **Will you send `analyticsToken`?** If yes, when is it minted — once per campaign
   per fetch? And does it need to survive a campaign edit?
5. **Do you want `dismiss` at all?** It is more than Braze offers and cheap for us
   to send. If you would rather not store it, we can stop sending it — but say so
   rather than rejecting it.
6. **Maximum batch size you will accept.** ~~Answered by V4: no hard limit.~~ We cap the outbox at 500 events; if your
   limit is lower, we will lower ours to match.
7. **Confirm the conversion-rate denominator** is unique impressions (§7.2).
8. **Authentication.** Today this posts `ApiKey` plus a `customerId` in the body.
   For a write endpoint that drives reporting, that means anyone holding a public
   API key can forge impressions for an arbitrary customer. Do you want
   `X-GB-TOKEN` required here even for integrations that do not use session tokens
   elsewhere? **We think you should.**
9. **Retention and access.** How long are raw events kept, and is there an
   equivalent of Braze's Event User Log — a per-user view of recent SDK activity
   with the raw payload? That one tool answers most "why didn't my message show"
   questions, and Braze keeps 30 days of it.

---

## 10. Worked example: one session

A returning customer opens the app, sees the welcome modal, taps "Redeem now",
browses, adds to cart, sees the cart nudge, closes it, then backgrounds the app.

```
09:14:22.184  message painted        → impression      cmp_welcome_modal
09:14:29.902  taps "Redeem now"      → button_click    cmp_welcome_modal  buttonId 1
09:14:32      ── 10s timer fires, batch of 2 sent ──
09:16:40.551  add_to_cart fires, nudge painted → impression  cmp_cart_nudge
09:16:44.203  taps the scrim         → dismiss         cmp_cart_nudge
09:16:50      ── 10s timer fires, batch of 2 sent ──
09:17:05      app backgrounded       → forced flush (outbox empty, no request)
```

Four events, two requests. Same session with no connectivity: nothing is sent, all
four events are on disk, and they arrive in one batch of four on the next launch —
with the original `occurredAt` values, possibly the next day.

---

## 11. How to test your side against ours

1. **Idempotency.** Post the same batch twice. Impression count must not change.
2. **Out-of-order.** Post a `dismiss` before its `impression`. Both must be stored;
   the impression must not be rejected for arriving second.
3. **Late arrival.** Post an event with `occurredAt` three days ago. It must land on
   that day's unique-impression bucket, not today's.
4. **Unknown event type.** Post `"event": "something_new"`. You must return 2xx and
   ignore it, so a future SDK cannot break an older backend.
5. **Missing token.** Post an event with no `analyticsToken`. It must be accepted
   and attributed by `campaignId`.
6. **Calendar-day boundary.** Post two impressions from one user either side of
   midnight in the workspace time zone. Unique impressions must be 2, total 2. Two
   on the same day: unique 1, total 2.
7. **Batch of 50.** Must be accepted, not truncated. The client chunks at 50 even though V4 states no hard limit — it bounds the cost of a failed retry rather than satisfying a cap.
8. **Throttling.** Return 429 and confirm the same batch is re-offered rather than
   lost.

---

## Appendix: where this lives in the SDK

| Concern | File |
| --- | --- |
| Event value object and wire JSON | `lib/in_app_messaging/analytics/message_event.dart` |
| Buffering, batching, persistence, retry | `lib/in_app_messaging/analytics/batched_message_analytics.dart` |
| HTTP call and status-code policy | `lib/network/request_calls/send_message_events_request.dart` |
| Endpoint path | `lib/network/utils/constants.dart` |
| Where events are raised | `lib/in_app_messaging/in_app_messaging_service.dart` |
| Impression timing | `lib/in_app_messaging/presentation/overlay_presenter.dart` |
| Tests | `test/in_app_messaging/batched_message_analytics_test.dart` |

Background on why the model is shaped this way, including what Braze does and where
we deliberately diverge: `docs/research/braze-analytics-and-logging-reference.md`.
