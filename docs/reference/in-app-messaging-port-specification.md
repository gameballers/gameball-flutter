# In-App Messaging — Port Specification

**Purpose:** implement in-app messaging in the iOS native, Android native and React Native SDKs so
that all four behave identically where it matters and idiomatically where it does not.

**Source of truth:** the Flutter SDK (`gameball-flutter`, 3.3.0) is the reference implementation, and
the behaviour below is what it does. Where this document and the code disagree, the code is right and
this document is a bug.

**Wire contract:** [`backend-sdk-endpoints-reference.md`](backend-sdk-endpoints-reference.md).
**Design rationale:** [`../superpowers/specs/2026-08-17-in-app-messaging-v4-migration-design.md`](../superpowers/specs/2026-08-17-in-app-messaging-v4-migration-design.md).

---

## 0. How to read this

Every section is labelled with how much freedom you have:

| Label | Meaning |
| --- | --- |
| **INVARIANT** | Must be identical in every SDK. A difference here is a bug, and usually one a customer notices before we do. |
| **PLATFORM** | The *what* is fixed, the *how* is yours. Draw the overlay however your platform draws overlays. |
| **IDIOMATIC** | Match your platform's conventions, not Flutter's. Naming, async style, error surfacing. |

**Do not port the Dart code.** It is one instantiation of the design, shaped by Flutter's widget tree
and Dart's async model. Read the rules, then write what your platform would naturally write. A Swift
file that reads like transliterated Dart will be wrong in ways that are hard to see.

**Read §13 before you start.** It lists the mistakes the Flutter implementation actually made and
fixed. They cost days to find and minutes to avoid, and nothing else in this document will stop you
repeating them.

---

## 1. What the module is, in one paragraph

A marketer authors a campaign in the dashboard: some artwork, copy, a button, and a rule about when
it should appear. At session start the SDK asks the backend which campaigns this customer is eligible
for and caches them. When something happens — the session begins, or the app reports an event — the
SDK decides locally whether any campaign should display, picks at most one, draws it above the app,
and reports what the customer did with it.

Three properties are non-negotiable:

1. **Opt-in.** Until the host calls `startInAppMessaging` (or your platform's equivalent), the module
   makes no requests, starts no timers, draws nothing and stores nothing.
2. **Never throws into the host.** Every failure is logged and swallowed. A malformed campaign, a dead
   network, a corrupt cache — none of them may surface as an exception in the host's code.
3. **Evaluation is local.** After the sync, deciding what to show requires no network. This is what
   makes messages instant and what makes them work offline.

---

## 2. Architecture — INVARIANT in shape, PLATFORM in implementation

Seven responsibilities. Keep them separate; the separation is what makes the thing testable without a
network or a screen, and every one of them is substituted in the Flutter test suite.

| Responsibility | Owns | Must not know about |
| --- | --- | --- |
| **Source** | Fetching campaigns, parsing them | Display, analytics, caps |
| **Cache** | Last good payload, per customer | Anything but bytes and a customer id |
| **Evaluator** | Which campaign displays, if any | I/O, clocks, UI |
| **Frequency cap** | What has been shown and when | Why, or what it looked like |
| **Presenter** | Drawing, dismissing, auto-dismiss timing | Analytics, caps, eligibility |
| **Analytics** | Buffering, batching, delivery, retry | What a message looks like |
| **Personalisation** | Current variable values, substitution | Everything else |

And one **orchestrator** that sequences them and owns the pending-message slot. Nothing else holds
mutable state.

> **The evaluator must be a pure function.** No network, no clock read, no UI handle — the current
> time is passed *in*. In the Flutter SDK this is 93 lines and the single most heavily tested unit in
> the module, because every display rule lives there and can be exercised in microseconds. If your
> port reaches for the system clock inside the selection logic, you have lost that.

---

## 3. The data model — INVARIANT

Field names below are the wire names. Use your platform's naming for the in-memory model, but do not
rename concepts.

### 3.1 Campaign

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `campaignId` | int | **required** | The identity everything keys on. Drop the campaign if absent. |
| `variationId` | int? | null | A/B arm. Reported in telemetry; **never** used as an identity key. |
| `dispatchId` | string? | null | Opaque. Echo on every event; never parse or validate it. |
| `name` | string? | null | Marketer-facing. Use it in logs and debug UI, never in logic. |
| `priority` | int | 0 | Higher wins. |
| `messageType` | int | **required** | 1 slideup · 2 modal · 3 fullscreen · 4 htmlFullscreen · 5 emailCapture |
| `contentMode` | string | `"prerendered"` | Anything else → **skip the campaign entirely**. |
| `expiresAt` | ISO-8601 UTC? | null | Never display at or after this. Enforced locally, see §5. |
| `isTest` | bool | false | Displays normally, reports **nothing**. |
| `trigger.repeatable` | bool | false | false means once ever, enforced on the device. |
| `trigger.minIntervalSeconds` | int? | null | Only meaningful when repeatable. 0 or null → every occurrence. |

### 3.2 Message

Assembled from two halves of the payload: `content` (untranslated styling and behaviour) and `locale`
(translated text). Buttons appear in **both** and are paired by string `id` — render only ids present
in both halves.

| Field | Source | Default | Notes |
| --- | --- | --- | --- |
| `id` | derived | — | `"{campaignId}"` or `"{campaignId}/{variationId}"`. Diagnostics only. |
| `type` | `messageType` | — | Unknown value → keep the campaign but mark it unsupported (§5). |
| `header` | `locale.header` | null | |
| `body` | `locale.message`, else `locale.body` | null | |
| `imageUrl` | see §3.3 | null | |
| `iconUrl` | `content.iconUrl` | null | Slideup only. Distinct from `imageUrl`. |
| `clickAction` | `content.action` | null | **Null means the surface is inert** — do not default to dismiss. |
| `buttons` | paired | empty | Max 2 for modal. |
| `showCloseButton` | `content.closeBehaviour` | true | true when the value contains `button`. |
| `dismissOnScrimTap` | `content.closeBehaviour` | true | true when the value contains `swipe`. |
| `autoDismissAfter` | `content.autoDismissSeconds` | null | Null means it stays until dismissed. Ignore values ≤ 0. |
| `layout` | `content.layout` | `text_with_image` | See §3.4. |
| `orientation` | `content.orientation` | `any` | Fullscreen only enforces it. |
| `slidePosition` | `content.slideFrom` | `bottom` | Slideup only. |
| `extras` | `content.extras` | empty | Passed through untouched. |
| `style` | `content.colors`, `content.textAlignment` | host theme | Every colour is optional; fall back to the host's theme, never to a hardcoded value. |

> **A campaign with nothing to render is dropped.** No header, no body, and no image means there is
> nothing to show, and drawing an empty box is worse than showing nothing. A **slideup** additionally
> requires text — an icon alone is not a message.

### 3.3 Artwork resolution — INVARIANT, and easy to get wrong

Two fields can carry the image, and precedence depends on the type:

- **fullscreen** → `content.media.url` first, then `content.imageUrl`
- **everything else** → `content.imageUrl` first, then `content.media.url`

`content.media` is an object `{type, url, autoplay, muted}`. Use `url` **only when `type` is
`"image"` or absent**; log and ignore `"video"` — handing a video URL to an image view draws a broken
frame.

Normalise blank strings to null. An empty URL otherwise reaches the artwork loader, fails, and — per
§6.4 — takes the whole campaign with it, silently.

### 3.4 Layout

| Type | Values | Default |
| --- | --- | --- |
| Modal | `text_with_image`, `image_only` | `text_with_image` |
| Fullscreen | `image_and_text`, `image_only` | `image_and_text` |

`image_and_text` and `text_with_image` mean the same arrangement; the two types spell it differently.

**An unrecognised value falls back to the type's default and keeps the campaign.** Layout is a
rendering hint, not a contract — a value a future dashboard invents must never cost the customer the
message. Do **not** infer layout from which fields are populated: a campaign whose personalised copy
resolves to empty is indistinguishable from a deliberately image-only one, and that mistake shipped
once already.

### 3.5 Actions

Flat object; `type` selects which fields matter.

| `type` | Fields | Behaviour |
| --- | --- | --- |
| `dismiss` | — | Close. |
| `open_url` | `url`, `external` | In-app browser, or the OS browser when `external` is true. |
| `navigate` | `route`, `arguments` | Hand to the host's router. `route` is a bare name — no leading slash. |
| `log_event` | `eventName`, `eventMetadata` | **Not implemented.** Parse and treat as unsupported. |
| `log_attribute` | `attributeKey`, `attributeValue` | **Not implemented.** |
| `request_push_permission` | — | **Not implemented.** |

**A button with no usable action falls back to dismiss** — a button that does nothing is a dead end.
**A message surface with no action stays inert** — do not make the whole surface dismiss on tap.

Every button tap reports a `click`, including a dismiss button.

### 3.6 Triggers

Two types, and only two.

- `session_start` — no fields.
- `event` — `name` (the event name; **match on this, never on `eventId`**), plus optional
  `metadataFilters` and `metadataLogicalOperator`.

A null or empty `name` on an event trigger → **drop the campaign** and log it. The numeric id is
internal to the backend and cannot be resolved on a device.

**Purchases are not a trigger type.** A purchase reaches the evaluator as an event named `purchase`,
with `productId`, `price`, `currency` and `quantity` folded into its properties so filters work on
them with the same syntax as any other event.

### 3.7 Metadata filters

Each filter: `name` (the property to test), `operator`, `value`.

Operators to support: `equals`, `notEquals`, `greaterThan`, `greaterThanOrEqual`, `lessThan`,
`lessThanOrEqual`, `contains`. Accept the backend's spellings case-insensitively (`Is`, `IsNot`, …)
and map them.

Three rules, and the asymmetry is deliberate:

1. **A filter whose `name` is missing drops the whole campaign.** A filter we cannot name is a filter
   we cannot evaluate, and evaluating it as "always true" would silently *widen* the campaign —
   showing a "spent over $100" message to everyone.
2. **A filter with an unusable operator or a null value is dropped individually.** That widens rather
   than narrows, which is the right response to one bad field rather than a contract mismatch.
3. **A missing property never matches.** A filter is a requirement, so absence is failure. Otherwise
   filters become decorative.

`metadataLogicalOperator` other than `And` → drop the campaign with a log. Only AND is supported.

---

## 4. The wire contract — INVARIANT

Three endpoints on the V4 integrations surface. Full detail in
[`backend-sdk-endpoints-reference.md`](backend-sdk-endpoints-reference.md); what follows is what the
SDK must *do*, including behaviour verified against the live endpoint that the document does not state.

| Endpoint | When |
| --- | --- |
| `POST /api/v4.0/integrations/inapp-messages/sync` | Once per session start |
| `POST /api/v4.0/integrations/inapp-messages/events` | Batched flushes |
| `POST /api/v4.0/integrations/inapp-messages/variables` | Before displaying a message carrying tokens |

**Pin to v4.0.** If your SDK routes to a v4.1 surface when a session token is present, do **not** do
that here: `/api/v4.1/…/inapp-messages/sync` exists and answers **401** to APIKey auth. Routing
through a version switch breaks messaging for exactly the integrations that set a token.

Auth is `APIKey`. Identity is `customerId` **in the body** — there is no player token and no encrypted
id on this surface. Sending a session-token header is harmless (verified: v4.0 returns 200 with it).

### 4.1 Sync

Body: `{customerId, platform, locale, appVersion, sdkVersion}`.

`platform`: **1 = iOS, 2 = Android.**

> **`platform` is optional in the schema and load-bearing in fact.** Omit it and the backend returns
> `200` with an empty message list. Send an unrecognised value — `0`, `3`, `99` — and you get the same
> empty list. **Not an error.** So a wrong platform code produces a feature that silently does nothing.
> Log loudly before sending anything other than 1 or 2, and never substitute a platform you are not.
> Campaigns are targeted per platform: the same customer sees 12 campaigns as iOS and 8 as Android.

Response `200`: a **plain payload**, `{cooldownSeconds, messages[]}`. No envelope, no success flag.
Treat unknown root keys as forward compatibility and ignore them — two undocumented ones
(`quietHours`, `campaignOrdering`) appeared during development.

Failures: `400` missing customerId · `401` bad key · `404` unknown customer *(with an `ErrorResponse`
body)* · `503` retry. Every non-2xx means **"could not ask"**, which is different from "no campaigns"
— see §5.1.

> A `404` with **no body** means the endpoint is not deployed on that environment. A `404` **with** an
> `ErrorResponse` means the customer does not exist. Distinguish them in your log; they are very
> different problems and otherwise indistinguishable from a wrong base URL.

### 4.2 Events

Body: `{customerId, platform, events[]}`.

Each event: `eventUid`, `dispatchId?`, `campaignId`, `variationId?`, `type`, `occurredAt`,
`buttonId?`, `url?`.

`type` is one of `impression`, `click`, `dismiss` (`submit` exists for email capture, which is not
implemented). Case-insensitive on the wire.

> **`eventUid` must be a v4 UUID.** Undocumented, and a non-GUID is a hard **400** that discards the
> entire batch rather than rejecting one event. Generate a real UUID v4. Do not use a timestamp, a
> counter, or a hash.

**`occurredAt` is when it happened on the device, never when it was sent.** Events can arrive hours
late; conversion windows and per-day unique-impression counts are anchored to this field.

Outcome mapping — measured, not assumed:

| Status | Do | Note |
| --- | --- | --- |
| `2xx` (202 in practice) | **Accept**, clear the batch | Body is `{accepted, rejected}`. Log `rejected` if non-zero; those events can never succeed. |
| `400`, `401`, `404`, `422` | **Discard** permanently, log loudly | |
| `408`, `429`, `5xx` | **Retry**, keep the batch | |
| network error, timeout | **Retry** | |

> **`422` is overloaded.** The document assigns it to a deactivated customer; the live endpoint also
> returns it for a batch in which *every* event was malformed. Both are permanent for that batch so
> the outcome is the same — but do not write code or comments that read a 422 as "customer
> deactivated".

A mixed batch (some valid, some not) returns `202 {accepted:n, rejected:m}` — **one bad event does not
poison the good ones**, so "clear the batch on 2xx" is correct and does not lose the accepted ones.

### 4.3 Variables

Body: `{customerId}`. Response: `{variables: {name: "value", …}}` — a flat map of **pre-formatted
strings** (points already thousand-separated). Insert them verbatim; never re-parse or re-format.

**Any failure means an empty result**, not an exception. 404, 422, 503, timeout, no network — the
caller's only correct response to all of them is identical, so there is nothing to distinguish.

> **Not deployed as of 2026-08-18.** It answers `404` with an empty body. Build it, expect it to do
> nothing, and see §8.

---

## 5. Lifecycle and evaluation — INVARIANT

### 5.1 When to sync

**Once per session start**, where a session starts when:

- the host opts in, or
- the host identifies a different customer, or
- the app returns to the foreground after more than the **session timeout** in the background.

Session timeout default: **30 seconds**, deliberately equal to the display cooldown. Because a message
can only display in the foreground, time-since-last-display is always at least time-spent-in-
background — so aligning them guarantees the cooldown can never suppress a warm session-start message.
Set it lower and you reintroduce that gap.

Sync and reading local state should run **concurrently**, not in series: the stored display history
gates the *decision*, not the *request*.

**Apply the cache only when the sync failed.** That is the backend's rule — *"on sync failure keep the
previous unexpired cache"* — and it also removes the race a parallel read creates, where a slow cache
read lands after a fast sync and clobbers fresher campaigns.

### 5.2 Selection — the pure algorithm

Given: the occurrence that just happened, the campaigns held, the display history, the current time,
and the cooldown from the last sync. Returns at most one campaign.

```
select(occurrence, campaigns, history, now, cooldown):

    eligible = []
    for c in campaigns:
        if not triggerMatches(c.trigger, occurrence):   continue
        if c.expiresAt != null and now >= c.expiresAt:  continue
        if not repeatEligible(c, history, now):         continue
        if c.message.type is unsupported:               continue
        if not artworkReady(c):                         continue      # see §6.4
        eligible.append(c)

    if eligible is empty:                               return null
    if now - history.lastDisplayAt < cooldown:          return null   # global floor

    sort eligible by priority DESC, then by original response order ASC
    return eligible[0]


repeatEligible(c, history, now):
    last = history.lastDisplayOf(c.campaignId)
    if last == null:            return true      # never shown
    if not c.repeatable:        return false     # once ever, forever
    if c.minInterval == null:   return true
    return now - last >= c.minInterval
```

Four details that are load-bearing:

1. **Expiry is checked at selection, not only at fetch.** Campaigns are cached for the session; one
   fetched at 23:58 would otherwise fire all night, and keep firing after the campaign was paused.
2. **Unsupported types are filtered here, not refused at display.** That lets a usable lower-priority
   campaign win instead of the occurrence being wasted.
3. **The tie-break is response order**, so it must be stable. If your platform's sort is not stable —
   Dart's is not — carry the original index explicitly. Otherwise equal-priority campaigns rotate
   arbitrarily between runs.
4. **The global floor is checked after eligibility, before sorting.** Inside the floor, nothing
   displays at all; it is not per campaign.

### 5.3 Cooldown and caps

- **Global floor** (`cooldownSeconds`, default 30) — minimum gap between *any two* displays, from any
  campaign. Comes from the sync response, so the backend can tune marketing pressure without a client
  release. Do not hardcode it.
- **Per-campaign repeat rule** — `repeatable` and `minIntervalSeconds`, above.

**Both are recorded at impression, never at selection.** A message that was selected and then deferred
or suppressed must not burn its slot. This is why a suppressed campaign is eligible again next session
with no manual reset.

Both must **survive a restart** — see §10.

> Repeat rules compare wall-clock times, because they have to survive process death and a monotonic
> clock does not. A customer who moves their device clock backwards can therefore suppress messages,
> and forwards can bypass the floor. Accepted, unfixable client-side, and Braze has the same exposure.

---

## 6. Display — INVARIANT rules, PLATFORM mechanism

### 6.1 Deferral versus suppression

Two outcomes for a message that matched but is not being shown, and they are not interchangeable.

**Defer** — hold it in a single pending slot and retry at the next display opportunity. The obstacle is
temporary:

- no drawing surface yet
- the host's own Gameball widget is open
- another message is already showing
- a fullscreen campaign's orientation does not match
- the host's `beforeDisplay` hook returned "later"

**Suppress** — do not show it, and this occurrence is spent. Nothing is held, nothing retries:

- inside the cooldown floor
- the campaign's repeat rule says no
- artwork is not ready
- `beforeDisplay` returned "discard"

**One pending slot, not a queue.** A newer deferral displaces an older one, with a log naming both.
Braze keeps a stack; a slot is honest and enough.

**Retry the pending message when:** the current message is dismissed, the host's widget closes, a
drawing surface appears, or the device rotates.

**Re-validate on retry.** Check the campaign has not since been shown, and re-check the cooldown floor
— a message deferred before another displayed must not slip through inside the floor.

> The pending slot is **in-memory only** and dies with the process. That is deliberate, and it is why
> a long obstacle (a quiet-hours window, say) should suppress rather than defer: "retry when it ends"
> would never fire.

### 6.2 Impression timing — INVARIANT, and the most commonly botched rule

**An impression is reported when the message becomes visible — not when it is inserted.**

On Flutter that means waiting for the frame to paint. On your platform it means whatever "the user can
now see this" means: a completed presentation animation, a view-did-appear callback. If the app is
backgrounded in that instant, the callback never fires and **no impression is reported**, which is
correct.

Everything downstream depends on this:

- The frequency cap is recorded here, so a message dismissed before painting does not burn its slot.
- The auto-dismiss timer starts here, so a configured duration measures time *visible* rather than
  time since insertion.
- `impressions = clicks + dismissals` holds as an identity the backend can rely on.

### 6.3 Dismissal accounting

Track two flags per presentation, both local to it:

- **shown** — the impression fired. A dismissal without an impression is nonsense; do not report one.
- **engaged** — a tap happened. Report `dismiss` **only when shown and not engaged**, so the dismissal
  that follows a tap is not also counted as "shown and ignored".

Braze reports no dismissal event at all, so "shown and ignored" is invisible in their analytics. It
costs one event here and it is worth having.

### 6.4 Artwork must load before display — INVARIANT

Load every held campaign's `imageUrl` and `iconUrl` **at sync**, before anything displays. A campaign
whose artwork fails is **passed over**, letting a lower-priority ready campaign take the slot.

Why it matters: the impression fires when the widget appears, so artwork arriving a beat later means a
view was counted of something the customer could not see. Impression accuracy is the number this
feature is judged on.

Warm the **whole set**, not just the winner — an event trigger fires with no warning and no time to
fetch, so a campaign waiting on `add_to_cart` depends on this having run at sync.

Bound it: **5 seconds** per campaign, concurrently. Concurrent matters — the ceiling is then the
slowest single image regardless of how many campaigns arrive, not the sum. Verified: 8 images at 300 ms
each complete in ~308 ms.

Failure is **per sync, not permanent** — the next sync re-evaluates.

> Log when a campaign's artwork is served over `http://`. Both platforms block cleartext by default,
> so the load fails, the campaign is passed over, and the only symptom is a campaign that silently
> never shows.

### 6.5 The three message types — PLATFORM

| | Modal | Slideup | Fullscreen |
| --- | --- | --- | --- |
| Blocks the app | yes, scrim | **no** | yes, opaque |
| Buttons | up to 2 | **none** | any, stacked full-width |
| Dismissal | close glyph, scrim tap, back | **swipe toward its own edge** | close glyph, back |
| Orientation lock | ignored | ignored | **enforced** |
| Artwork | `imageUrl`, never cropped | `iconUrl`, fixed 40pt square | `media`/`imageUrl`, cropped to fill |

**Slideup is not a squashed modal.** It has no scrim, occupies only its own band so taps outside reach
the app, has no buttons because the whole surface is the tap target, and must be swipe-dismissible —
live campaigns carry neither a close behaviour nor an auto-dismiss, so a drag is the only exit. Swipe
**only toward its own edge**; sideways fights a horizontal scroll underneath.

**Fullscreen has two genuinely different compositions.** `image_and_text` stacks artwork, copy and
full-width buttons. `image_only` lets the artwork fill the screen with buttons floated *over* it. The
second is not the first with the text hidden.

**Orientation is enforced only for fullscreen**, at display time: a mismatch is refused, deferred, and
retried on rotation. A poster with its copy baked into the artwork is unreadable sideways. Enforcing it
for a small centred card would suppress messages for no benefit.

### 6.6 Layout requirements that are not cosmetic — INVARIANT

Learned the hard way; all four of these were real defects in the Flutter SDK, found by testing on a
320×568 screen and at 2× text scale:

1. **Copy must scroll, not clip.** Long promotional text on a small phone, or any text at an
   accessibility scale, exceeds the card. Clipping removes the **buttons** first, so the call to action
   the campaign exists for becomes unreachable. Measured overflows before the fix: 296 px on an
   iPhone SE, **1,552 px at 2× text**.
2. **A short message must stay short.** The obvious implementation of "make it scrollable" makes every
   card full-height. Test both directions.
3. **Buttons must wrap, not overflow.** Two German or Arabic labels are wider than two English ones —
   360 px of overflow in the Flutter SDK before it was fixed.
4. **Right-to-left must actually mirror.** Use directional layout primitives throughout. Close glyphs
   sit at the *trailing* corner, gaps on the *start*/*end* side, and a chevron pointing "forward" must
   flip. Gameball serves Arabic customers; this is not hypothetical.

Also: honour the platform's **reduce-motion** setting by skipping entry animations outright rather than
shortening them, and take the close-button tooltip from the platform's own localised string rather than
hardcoding "Close".

### 6.7 Where to draw it — PLATFORM

The requirement: **above every screen the host can show, without being coverable or dismissable by the
host's own navigation, and without requiring a permission.**

| Platform | Approach |
| --- | --- |
| **iOS native** | Present into your own `UIWindow` at a raised level. On iOS 13+ this needs a `windowScene` — take it from the active scene, do not assume `UIApplication.shared.windows.first`. |
| **Android native** | Add a view to the current `Activity`'s content root, or a `DialogFragment` for the modal. **Do not** use `SYSTEM_ALERT_WINDOW`; drawing over other apps needs a permission you must not ask for. Handle configuration changes — an Activity recreation must not leave an orphaned view. |
| **React Native** | A root-level component rendered above the navigator, fed by native module events. The RN tree is the equivalent of Flutter's overlay. |

Whatever you choose, **presentation must be able to fail and say so** — returning "could not draw"
rather than throwing is what feeds the deferral in §6.1.

Handle the **Android back button** for modal and fullscreen: it dismisses the message and must **not**
pop the host's route. Do **not** intercept back for a slideup — a non-blocking banner has no claim on
the gesture, and intercepting it breaks navigation for a message the user is entitled to ignore.

---

## 7. Analytics — INVARIANT

### 7.1 Vocabulary

Three event types: `impression`, `click`, `dismiss`.

**There is no separate button-click type.** A button tap is a `click` carrying `buttonId`; presence of
that field is what distinguishes it from a tap on the message surface. The backend's vocabulary also
includes `submit`, which belongs to email capture and is not implemented.

Report `url` alongside a click whose action opened one, so the backend can attribute outbound traffic
without re-deriving it.

**`isTest` campaigns report nothing at all.** They display normally so a marketer can see their work;
their telemetry must never reach campaign statistics.

### 7.2 The outbox

| Property | Value | Why |
| --- | --- | --- |
| Never blocks the caller | logging is fire-and-forget | An impression must not wait on a network round trip while a message animates in |
| Flush interval | **30 s** | Backend's stated cadence |
| Flush at count | **10 events** | |
| Events per request | **50** | The server states no limit; chunking bounds the cost of a failed retry |
| Outbox ceiling | **500** | Beyond that, drop the **oldest** and log it |
| Concurrency | one request in flight | |
| Persisted | **after every change** | An impression logged a second before a force-quit still arrives, on the next launch |

**Forced flush** on: app backgrounded, messaging stopped (logout), and **immediately before an action
that may take the user away** — `open_url` or `navigate`. Bound that last one (Flutter uses 800 ms):
the events are on disk either way, so the worst case is they go out next launch, and a dead network
must not delay a tap the user is waiting on.

### 7.3 Delivery semantics — INVARIANT

**At-least-once, deduplicated server-side on `eventUid`.**

- Generate the uid **once per event**, and **never regenerate it on retry**. That is the entire point of
  the field. A process killed between the response and the outbox bookkeeping resends the batch, and
  dedup is what stops that inflating impressions.
- A re-display of a repeatable campaign is a **new impression with a new uid**, not a resend.
- **Ordering:** oldest first within a batch. Across batches, expect out-of-order arrival — a batch
  stranded by a dead network can land after later ones.

**A poison batch must be discarded, not retried forever.** The outbox is FIFO, so one permanently
rejected batch at the front blocks every event behind it — taking all analytics down until the ceiling
rotates it out. Discard on the permanent statuses in §4.2 and log loudly.

---

## 8. Personalisation — INVARIANT

Currently **inert**: the backend substitutes variables at sync, so no live message carries a token.
That changes — sync will send templates and the SDK will substitute. Build it; it activates by itself.

### 8.1 Substitution

Token syntax is `{token_name}` — **single** braces around a bare identifier matching
`[A-Za-z_][A-Za-z0-9_]*`. Not Liquid, not double braces, no filters, no conditionals.

Rules:

- Apply to `header`, `body` and every **button label**.
- Values are inserted **verbatim** — they arrive pre-formatted, thousand separators included.
- **A token with no matching key is left exactly as written.** Blanking it would silently delete copy a
  marketer wrote.
- **One pass only.** A substituted value is data, not a template; a value containing braces is never
  expanded again.
- **Be strict about what counts as a token.** `{ spaced }`, `{2}` and a lone `{` are not tokens. A
  loose pattern lets a value map mangle ordinary copy — and this check is also what keeps the whole
  feature inert, so a false positive costs a network round trip before every display.

### 8.2 When to fetch

**Immediately before display**, and **only for a message that actually carries a token.** A cheap scan
for `{` before the regex means the common case costs one character comparison.

Bound the fetch at **2 seconds**. On timeout, error, or an empty result, **display the text you already
have** — never block or drop a display on this call.

Cache the values for **60 seconds**, keyed by customer, so several messages in a burst share one fetch.

> **Drop the cache whenever the customer acts.** Clear it on every event and purchase, before
> evaluating; do **not** clear it on session start. The campaign this exists for is *"you just earned
> 200 points, you now have X"* — its trigger is the purchase, and a value cached before that purchase
> makes the message announcing the change quote the number from before it. Values cannot move between
> a sync and the message that sync triggered, so clearing there buys a second fetch and nothing else.
>
> Clearing is free unless a message displays: it empties a map, and the fetch happens later.

### 8.3 Persisting values, and the PII rule

Store the last successful values **per customer**, so a failed fetch falls back to them rather than to
raw braces. Slightly stale is the problem this endpoint *reduces*; `{points_balance}` is not a stale
number, it is not a number at all.

> **Store only the tokens the held campaigns actually use.** The endpoint returns `player_name`,
> `player_last_name` and `player_email` alongside the balances. This is the only customer PII the
> module keeps at rest, so derive the needed set from the campaigns after each sync and store nothing
> else. A campaign set mentioning no tokens stores nothing at all. The **live fetch still returns
> everything** — the filter applies only to what lands on the device.

Two properties:

- **Clear on logout and customer change**, storage included. Logging out must not leave a name behind.
- **A pending write must not resurrect cleared values.** If the write after a fetch is not awaited — and
  it should not be, a display must never wait on storage — a clear issued moments later can be
  overtaken by it. Re-check the customer **after** acquiring storage, not before: a check before the
  await passes, because the clear has not been issued yet. This race was real.

### 8.4 Unresolved tokens after substitution — **OPEN, do not guess**

What to do with a message that still carries a token after substitution is an **open product decision**
(recorded as O22). Today's behaviour is fail-open: display the raw text.

Do not decide this per SDK. Whatever is chosen must be identical everywhere, or the same campaign
behaves differently per platform. Ask before implementing.

---

## 9. Host API surface — IDIOMATIC

Four entry points and four hooks. Names should follow your platform; the semantics must not change.

| Concept | Flutter | Semantics |
| --- | --- | --- |
| Opt in | `startInAppMessaging(customerId, navigatorKey, …)` | Idempotent for the same customer. A **different** customer refetches and resets caps, so the host need not stop first. |
| Opt out | `stopInAppMessaging()` | Dismiss what is showing, flush telemetry, clear per-customer state. |
| Is running | `isInAppMessagingStarted` | |
| Observe | `onInAppMessage` stream | Every message *selected*, whatever happens next. |

| Hook | Signature | Contract |
| --- | --- | --- |
| **beforeDisplay** | `(message) → show \| later \| discard` | Synchronous. **If it throws, default to `show`.** |
| **onAction** | `(message, button?, action) → bool` | `true` = host handled it, SDK does nothing further. `button` is null for a surface tap. **If it throws, fall back to built-in handling.** |
| **onNavigate** | `(route, arguments) → void` | For hosts whose router the SDK cannot drive. |
| Purchase | `logPurchase(...)` | Reaches campaigns as an event named `purchase`. |

**The hooks replace the action, never the bookkeeping.** The impression, the click and the dismissal are
reported regardless of what a hook returns.

**A throwing hook must never break the feature.** A buggy host loses its override, not its messages.

### 9.1 What each platform must additionally require

| Platform | Extra requirement |
| --- | --- |
| Flutter | a `GlobalKey<NavigatorState>` |
| iOS native | nothing — you own the window |
| Android native | current `Activity` reference (or an application-level lifecycle callback) |
| React Native | a root component mounted above the navigator |

**Wire the host's existing calls, do not add new ones.** In the Flutter SDK, `initializeCustomer`
already notifies the module of a customer change, `sendEvent` already feeds the trigger engine, and the
app-lifecycle observer already reports foreground and background. Do the same: an integrator should not
have to call anything twice.

Every such hook must be **individually guarded** — wrap each in its own try/catch that logs and
swallows, and place it **outside** any existing callback chain that lacks error handling, or a throw
inside your addition escapes as an unhandled error in someone else's code path.

---

## 10. Persistence — INVARIANT in *what*, PLATFORM in *how*

Four things must survive the process dying. Use whatever your platform uses for small key-value data —
`UserDefaults`, `SharedPreferences`, `AsyncStorage`.

| What | Key used by Flutter | Must survive a restart because |
| --- | --- | --- |
| Display history | `gameball_iam_display_history` | Otherwise a "once ever" campaign shows again on every launch |
| Campaign cache | `gameball_iam_campaign_cache` | A failed sync must fall back to the last good payload, not show nothing |
| Analytics outbox | `gameball_iam_analytics_outbox` | An impression logged before a force-quit must still arrive |
| Variable values | `gameball_iam_variables` | A failed fetch must fall back to real values, not raw tokens |

Rules for all four:

- **Keyed per customer, and discarded on mismatch at read.** Showing one person's campaigns — or name —
  to another is the single failure this scoping exists to prevent.
- **A corrupt or unreadable store must not stop messaging from starting.** Log, discard, carry on.
- **The campaign cache stores the raw payload**, not serialised objects. That means no serialiser to
  keep in step with the model, and the parser stays the only thing that reads a sync. Re-parse on read
  — so a payload a newer SDK version rejects is not resurrected as stale objects.
- **Bound every read.** Storage goes through a platform channel or disk, and a wedged store that never
  answers is not something a `try` catches. Flutter bounds these at **2 seconds** and degrades to "no
  history" — because showing a once-ever campaign twice is a far smaller failure than the feature being
  silently dead.

> Display history grows without pruning, and that is deliberate. Naive pruning is **wrong**: the backend
> stops returning a non-repeatable campaign once its impression lands, so forgetting it could show a
> once-ever message twice. If you must bound it, cap the entry count and drop oldest — do not prune by
> "no longer in the current sync".

---

## 11. Diagnostics — INVARIANT in spirit

**Every decision the module makes must be logged, with a reason, naming the campaign.**

This is not a nicety. The module never throws, so a log line is the *only* evidence of why something did
not happen — and "why didn't my campaign show" is the question you will be asked most. Every one of the
following must be answerable from the log alone:

- campaign dropped at parse, and which field caused it
- campaign skipped for an unsupported type or content mode, named rather than numbered
- campaign passed over because artwork was not ready
- campaign not selected because of the floor, its repeat rule, or expiry
- message deferred, and what blocked it
- pending message displaced by a newer one, naming both
- a batch discarded rather than retried, and the status that decided it
- an unrecognised platform code being sent
- artwork served over `http://`

Use a prefix the integrator can filter on (`[GameballIAM]`), and keep it **separate from telemetry that
posts to the backend** — these are developer diagnostics, not analytics.

---

## 12. Conformance test matrix

Every SDK must demonstrate all of these. Same behaviours, same names where practical, so the four suites
can be compared. The Flutter SDK has **511** tests; the counts below are groupings, not test counts.

### Parsing
- [ ] A fully populated campaign parses with every field mapped
- [ ] A minimal campaign (id, type, trigger, some text) parses
- [ ] Missing `campaignId` → dropped
- [ ] Unknown `messageType` → kept, marked unsupported, **not** dropped
- [ ] Unknown `contentMode` → campaign dropped
- [ ] Buttons paired by id across `content` and `locale`; unmatched ids dropped
- [ ] Event trigger with null `name` → campaign dropped
- [ ] Filter with missing `name` → **whole campaign** dropped
- [ ] Filter with bad operator or null value → **that filter** dropped, campaign kept
- [ ] `metadataLogicalOperator: "Or"` → campaign dropped
- [ ] Every `layout` value, plus an unknown one falling back to the type's default
- [ ] Absent copy does **not** imply image-only
- [ ] Fullscreen prefers `media.url`; other types prefer `imageUrl`; each falls back to the other
- [ ] `media.type == "video"` ignored, not rendered
- [ ] Blank URL treated as absent
- [ ] Malformed JSON, non-object root, missing `messages` → empty result, no throw

### Selection
- [ ] Session start selects a session-start campaign
- [ ] A named event selects a matching event campaign; a non-matching name selects nothing
- [ ] Property filters: each of the seven operators; a missing property never matches
- [ ] Expired campaign never selected, **even from cache**
- [ ] Non-repeatable campaign never selected twice, **across a restart**
- [ ] Repeatable campaign respects `minIntervalSeconds`
- [ ] Inside the global floor, nothing is selected
- [ ] Highest priority wins; ties break on response order, **stably**
- [ ] Unsupported type filtered so a lower-priority supported campaign wins
- [ ] Purchase selects a campaign triggered on `purchase`, and its price/product filters work

### Display
- [ ] Impression reported when **visible**, not when inserted
- [ ] Message dismissed before it paints → **no** impression and **no** dismissal
- [ ] Cap and floor recorded at impression, not selection
- [ ] `dismiss` reported only when shown and not engaged
- [ ] Button tap reports `click` **with** `buttonId`; surface tap reports `click` **without**
- [ ] Deferred when no surface, widget open, another showing, orientation mismatch, or hook says later
- [ ] Deferred message retried on dismissal, widget close, surface appearing, and **rotation**
- [ ] Retry re-checks already-shown and the floor
- [ ] A newer deferral displaces an older one
- [ ] `isTest` campaign displays and reports **nothing**
- [ ] Auto-dismiss measured from visibility
- [ ] Modal: scrim tap honours `closeBehaviour`; back dismisses without popping the host route
- [ ] Slideup: no scrim, app usable underneath, swipe only toward its own edge, back **not** intercepted
- [ ] Fullscreen: orientation enforced, refused message retried on rotation

### Layout resilience
- [ ] Long copy on a 320×568 screen: no overflow, copy scrolls
- [ ] 2× accessibility text scale: no overflow
- [ ] Two long localised button labels: wrap rather than overflow
- [ ] A short message stays short — the card is not full-height
- [ ] Right-to-left: close glyph at the trailing corner, gaps mirrored, chevron flipped
- [ ] Reduce-motion: no entry animation at all
- [ ] A dead image URL does not prevent the message rendering

### Artwork
- [ ] Every held campaign warmed at sync, not just the one that displays
- [ ] Campaign whose artwork failed is passed over; a lower-priority ready one wins
- [ ] Readiness recomputed on the next sync, not permanent
- [ ] A hung load is bounded and the campaign skipped

### Analytics
- [ ] Each status in §4.2 produces the right outcome
- [ ] `2xx` with `rejected > 0` still clears the batch
- [ ] Unreadable `2xx` body still accepted
- [ ] `eventUid` is a valid v4 UUID — **assert the shape**, so a future change cannot silently break ingestion
- [ ] `eventUid` never regenerated on retry
- [ ] Outbox survives a restart
- [ ] Ceiling drops oldest and logs
- [ ] Flush on background, on stop, and before an outward action
- [ ] Batch chunked at 50

### Personalisation
- [ ] Known token substituted; unknown token left **exactly** as written
- [ ] Malformed braces untouched; one pass only
- [ ] A message with no token never calls the endpoint
- [ ] Failure, empty result and timeout all display the text already held
- [ ] Values cached for the TTL; **dropped on any event or purchase**; **not** dropped on session start
- [ ] An event-triggered message shows values from **after** the event
- [ ] Only tokens the campaigns use are persisted; the live fetch still returns everything
- [ ] Clear on logout removes stored values
- [ ] A pending write cannot resurrect cleared values

### Lifecycle and compatibility
- [ ] Nothing happens before opt-in: **no requests, no timers, no storage writes, nothing drawn**
- [ ] Warm resume beyond the session timeout starts a new session and re-syncs
- [ ] Resume inside the timeout does not
- [ ] Customer change refetches, resets caps, discards the previous customer's cache and values
- [ ] Stop dismisses, flushes and clears
- [ ] A failed sync falls back to the cache; an **empty successful** sync replaces it
- [ ] Every host hook that throws is contained
- [ ] Sync sends the correct platform code, and an unrecognised one is logged before sending

### End to end
- [ ] Drive the whole module through the **public API only**, against a stubbed source, and assert a
      message renders, a tap dismisses it, and analytics were reported. This is the test that catches
      wiring mistakes every unit test passes.
- [ ] Parse a payload **captured from the live backend**, not one you wrote. In the Flutter SDK this
      caught two real defects that reading the documentation did not.

---

## 13. Traps — read before you start

Each of these was a real defect in the Flutter implementation, found and fixed. They are ordered by how
much time they cost.

1. **Layout overflow on small screens and large text.** Four of four realistic cases overflowed, up to
   1,552 px. In release builds this clips silently and removes the buttons first. Nothing caught it
   because every widget test ran at one screen size and 1× text. **Test small screens and 2× text
   before you believe your layouts.**

2. **Right-to-left ignored entirely.** No directional primitives anywhere, so Arabic put gaps on the
   wrong side and pointed the chevron backwards. Mechanical to fix, invisible until someone looks.

3. **Impression timing.** Reporting at insertion rather than at paint counts views nobody had. Related:
   artwork loading at display time meant the impression fired before the image arrived.

4. **A stale navigator/activity reference.** Binding the presenter to the first surface handle forever
   meant a hot restart — or an Activity recreation — left it pointing at a dead one, and messages
   silently never appeared. **Rebuild the presenter when the handle changes.**

5. **A retry loop that re-armed every frame.** A message deferred for want of a surface scheduled a
   retry, which failed, which scheduled another. Guard it. But note the inverse: that per-frame retry is
   also what makes rotation work, so if you make it one-shot you must handle rotation explicitly.

6. **Non-stable sort.** Ordering by priority alone made equal-priority ties arbitrary between runs.
   Carry the original index.

7. **Filters built but unreachable.** The event hook passed only the event *name* to the evaluator, not
   its metadata — so every filtered campaign was unmatchable. The filters were fully unit-tested and
   completely dead. **Test filters end-to-end through the public API, not just as units.**

8. **A write-after-clear race.** An unawaited storage write issued before a logout can land after it,
   restoring data that was just deleted. Re-check the customer **after** acquiring storage, not before —
   a check before the await always passes.

9. **Inferring layout from populated fields.** A campaign whose personalised copy resolved to empty was
   indistinguishable from a deliberately image-only one. Never infer; read the field.

10. **Trusting the wire format's documentation over the wire.** The live endpoint returned a 422 where
    the document said 2xx, required a GUID the document never mentioned, and grew two undocumented
    fields mid-development. **Probe the endpoint yourself before you finish the parser.**

---

## 14. Out of scope — keep it that way

Do not implement these; the Flutter SDK does not, and parity matters more than features:

- **HtmlFullscreen** (`messageType` 4) and its sandboxed webview with a JS bridge
- **EmailCapture** (`messageType` 5) and the `submit` event
- **Video media** — parse `media.type == "video"` and ignore it
- **`log_event`, `log_attribute`, `request_push_permission`** actions — parse as unsupported
- **Custom fonts** (`content.font`), `allowedAssetUrls`
- **Dayparting in local time** — the sync request carries no time zone
- **`quietHours` / `campaignOrdering`** — present in the response, undocumented, not yet enforced

An unknown `messageType` must skip **safely**, so these arrive as no-ops rather than errors when the
backend starts sending them.

---

## 15. Open questions that will affect your port

These are unresolved on the backend side and identical for every SDK. Check their status before you
build the affected part.

| # | Question | Affects |
| --- | --- | --- |
| **O19** | The V4 endpoints are on **alpha only**; production returns a bare 404 | Whether you can test at all |
| **O13/O21** | Sync will stop substituting variables. **Deployment order is load-bearing** — if it lands before the variables endpoint, every personalised campaign shows raw braces | §8 |
| **O22** | What to do with an unresolved token. **Open product decision** — do not decide per SDK | §8.4 |
| **O20** | `quietHours` is SDK-enforced against the device timezone; the model is still to come. A message caught by a window should be **suppressed**, not deferred | §5, §6.1 |
| **O23** | Is the variables endpoint read-after-write consistent with event processing? If not, "you just earned X" quotes the old balance however correctly the client behaves | §8.2 |
| **O9** | `eventUid` must be a GUID — undocumented, and a non-GUID is a hard 400 discarding the batch | §4.2 |
| **O4/O6** | The authoritative filter operator vocabulary, and whether `Or` is reachable from the dashboard | §3.7 |
| **O14/O15** | The token model has no conditionals and reaches text only | §8 |

---

## Appendix — reference implementation map

Where to look in `gameball-flutter` when this document is ambiguous.

| Concern | File |
| --- | --- |
| Wire parsing, every leniency rule | `lib/in_app_messaging/source/message_parser.dart` |
| Selection algorithm | `lib/in_app_messaging/evaluation/trigger_evaluator.dart` |
| Caps and history | `lib/in_app_messaging/evaluation/frequency_cap.dart` |
| Orchestration, deferral, pending slot | `lib/in_app_messaging/in_app_messaging_service.dart` |
| Overlay, auto-dismiss, orientation | `lib/in_app_messaging/presentation/overlay_presenter.dart` |
| The three layouts | `lib/in_app_messaging/presentation/in_app_message_{modal,slideup,fullscreen}.dart` |
| Outbox | `lib/in_app_messaging/analytics/batched_message_analytics.dart` |
| Personalisation | `lib/in_app_messaging/personalisation/` |
| Host wiring and public API | `lib/gameball_sdk.dart` |
| Conformance tests | `test/in_app_messaging/` |
| A live captured payload | `test/fixtures/v4-sync-response.json` |
