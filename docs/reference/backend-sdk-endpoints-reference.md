# In-App Messages — SDK Endpoints Reference (V4 Integrations)

The single reference for SDK developers: every endpoint the device calls, what it expects, what it
returns, and the behavior contract. Three endpoints exist on the **V4 integrations surface**;
nothing else is ever called for in-app messaging.

| # | Endpoint | Purpose | When |
|---|---|---|---|
| 1 | `POST /api/v4.0/integrations/inapp-messages/sync` | Fetch every eligible, pre-rendered message | Once per session start |
| 2 | `POST /api/v4.0/integrations/inapp-messages/events` | Report impression / click / dismiss / submit telemetry | Batched flushes |
| 3 | `POST /api/v4.0/integrations/inapp-messages/variables` | Fetch the customer's CURRENT personalisation variable values | Just before displaying a message whose text carries `{tokens}` |

Shared integrations conventions, all three endpoints:
- **Auth:** the standard integrations headers (`APIKey`; secret-key rules follow the client's
  high-security-mode configuration, same as the sibling integrations endpoints).
- **Identity:** the customer is named explicitly as `customerId` in the request body (the
  customer's id in YOUR system — the same value used everywhere else in the integrations API).
  There is no player token and no encrypted id on this surface.
- **Responses are plain payloads with HTTP status codes** (no bots-style wrapper): `400` missing or
  invalid payload, `401` auth failure, `404` the customer does not exist, `422` the customer exists
  but is deactivated, `503` a downstream dependency was unavailable — retry safely.

Custom/business events (purchases, add-to-cart, anything about what the user did in the app) keep
going to the normal Gameball events integration endpoint, unchanged. Boundary rule: message
lifecycle → these endpoints; user behavior → events endpoint. Neither carries the other's payload.

---

# 1. Sync — `POST integrations/inapp-messages/sync`

## Request

```
POST /api/v4.0/integrations/inapp-messages/sync
Headers: APIKey, Content-Type: application/json
```

```json
{
  "customerId": "10708564181292",
  "platform": 1,
  "locale": "en",
  "appVersion": "3.2.1",
  "sdkVersion": "1.0.0"
}
```
`customerId` is **required**. `platform`: 1 = iOS, 2 = Android. `locale` drives translation choice
(device locale → player's preferred language → en → any).

## Response

`200 OK` with the payload below (`404`/`422`/`503` per the shared conventions above):

```json
{
  "cooldownSeconds": 30,
  "messages": [
    {
      "campaignId": 2041,
      "variationId": 4,
      "dispatchId": "b1a4c2e8-...",
      "name": "Welcome Back Offer",
      "priority": 10,
      "messageType": 2,
      "trigger": {
        "type": "session_start | event",
        "eventId": 812,
        "name": "add_to_cart",
        "metadataLogicalOperator": "And",
        "metadataFilters": [ { "metadataId": 4051, "name": "category", "value": "electronics", "operator": "Is" } ],
        "repeatable": false,
        "minIntervalSeconds": null
      },
      "contentMode": "prerendered",
      "content": { ...styling/behaviour/media, see below... },
      "locale":  { ...translated text, variables already substituted... },
      "localeCode": "en",
      "expiresAt": "2026-09-30T21:59:59Z",
      "isTest": false
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `cooldownSeconds` | Minimum gap between two displayed messages; SDK-enforced. Currently 30. |
| `dispatchId` | Store it; echo it on every telemetry event. |
| `priority` | Higher wins when several messages share a trigger occurrence; show one, rest wait. |
| `messageType` | 1 Slideup, 2 Modal, 3 Fullscreen, 4 HtmlFullscreen, 5 EmailCapture |
| `trigger.name` | For `event` triggers: the Gameball event's NAME. **Match logged events by this name, never by `eventId`** (ids are internal). Filters likewise carry `name` (the property key) to match against the logged event's properties. A null `name` on an event trigger means it cannot be evaluated — skip the message. |
| `trigger.repeatable` | **false = once ever**: after one display, never show again (server also stops returning it once the impression is reported). **true**: the trigger re-arms after `minIntervalSeconds` since the last local display (0 = every occurrence). |
| `contentMode` | Always `"prerendered"` today; skip messages with unknown values. |
| `expiresAt` | Never display after this moment. Null = no expiry. |
| `isTest` | **true = dashboard test delivery**: display normally on the trigger, but report NO telemetry for it. |

### `content` (styling/behaviour — untranslated)

```json
{
  "colors": { "background","text","header","closeButton","border","frame" },
  "textAlignment": { "header": "left|center|right", "body": "left|center|right" },
  "font": { "mode": "inherit|custom", "name": "...", "url": "..." },
  "closeBehaviour": "swipe|button|both",
  "action": { ...surface tap action... },
  "extras": { "any-key": "any-value" },
  "slideFrom": "top|bottom", "autoDismissSeconds": 6, "iconUrl": "...",      // Slideup
  "imageUrl": "...",                                                          // Modal
  "media": { "type": "image|video", "url": "...", "autoplay": true, "muted": true },
  "orientation": "portrait|landscape|any",                                    // Fullscreen
  "layout": "text_with_image|image_only",                                     // Modal (see below)
  //         "image_and_text|image_only"                                      // Fullscreen values
  "allowedAssetUrls": ["https://..."],                                        // HtmlFullscreen
  "submitButtonColors": { ... }, "onSuccessAction": "close|showSuccessMessage", // EmailCapture
  "buttons": [ { "id": "b1", "action": { ... }, "colors": { ... } } ]         // Modal & Fullscreen
}
```

### `layout` (Modal & Fullscreen only)

Rendering mode of the message, following Braze's image-style model. Server-validated at authoring
time; absent/null means the type's default rendering.

| Type | Values | Rendering rule |
|---|---|---|
| Modal | `text_with_image` (default), `image_only` | `image_only`: render ONLY the image (`content.imageUrl`) + close affordance + buttons; NO header/message text block. The server guarantees `imageUrl` is present for image_only modals. |
| Fullscreen | `image_and_text` (default), `image_only` | `image_only`: the media (`content.media`) fills the screen; no text block. Buttons and close behaviour still apply. |

Unknown/unsupported `layout` values → fall back to the type's default rendering (never skip the
message for an unknown layout; it is a rendering hint, not a contract).

### Actions (surface `action` and each button's `action`)

| `type` | Fields | SDK behavior |
|---|---|---|
| `dismiss` | — | Close the message |
| `open_url` | `url`, `external` | In-app browser, or OS browser when `external:true` |
| `navigate` | `route`, `arguments` | Named in-app destination; args passed untouched |
| `log_event` | `eventName`, `eventMetadata` | Log a Gameball custom event through the NORMAL events endpoint (this can trigger other campaigns locally) |
| `log_attribute` | `attributeKey`, `attributeValue` | Set the player attribute via the attribute-update path |
| `request_push_permission` | — | Show the OS push-permission prompt |

Defaults: a **button** with no action falls back to dismiss; the **message surface** with no action
does nothing. Every button tap also logs a `click` telemetry event (even dismiss buttons).

### `locale` (translated text — render verbatim, variables already substituted)

```json
{
  "header": "...", "message": "...",
  "html": "...",                                              // HtmlFullscreen
  "placeholder": "...", "submitText": "...",
  "successMessage": "...", "errorMessage": "...",             // EmailCapture
  "buttons": [ { "id": "b1", "text": "Shop now" } ]           // labels, pair by id
}
```

Button labels pair with `content.buttons` by `id`; render only buttons present on both sides.

### HtmlFullscreen sandbox
Webview with JS but NO network access except `allowedAssetUrls`; bridge exposes only `dismiss()`,
`openUrl(url)`, `navigate(route,args)`, `logClick(buttonId)`. No cookies/storage persistence.

## SDK behavior checklist (sync)

1. Sync once per session start; replace the entire cache with the response.
2. Discard messages past `expiresAt`; on sync failure keep the previous unexpired cache.
3. On a trigger occurrence show the highest-priority eligible message; one per occurrence; respect
   `cooldownSeconds` between any two displays.
4. Non-repeatable message displayed once → never again (locally too, don't wait for the server).
   Repeatable → re-display allowed after `minIntervalSeconds` since ITS last display.
5. Record `campaignId`, `variationId`, `dispatchId` at display time for telemetry.
6. `isTest:true` → display normally, report nothing.
7. Unknown `messageType`/`contentMode`/action `type` → skip that message/action silently.
8. Never block app startup on this call.

## Sync errors

| Case | HTTP | Body |
|---|---|---|
| Missing `customerId` | 400 | `ErrorResponse` (CustomerIdIsMissing) |
| Bad/missing APIKey | 401 | auth error |
| Customer not found | 404 | `ErrorResponse` (PlayerDoesNotExist) |
| Customer deactivated | 422 | `ErrorResponse` (PlayerInactive) |
| Messages service unavailable | 503 | `ErrorResponse` — retry safely; keep the previous cache |

---

# 2. Events — `POST integrations/inapp-messages/events`

## Queue & flush rules

- Queue events on disk until acknowledged 2xx.
- Flush on ANY of: **10 events**, **30 seconds**, **app background/session end**, **immediately
  before executing an open_url/navigate action**.
- No hard batch-size limit; flush whatever is queued. Retries are safe (server dedupes).

## Request

```
POST /api/v4.0/integrations/inapp-messages/events
Headers: APIKey, Content-Type: application/json
```

```json
{
  "customerId": "10708564181292",
  "platform": 1,
  "events": [
    {
      "eventUid": "3f1c2b34-...",        // REQUIRED: generated ONCE per event, never per retry
      "dispatchId": "b1a4c2e8-...",      // from the sync payload
      "campaignId": 2041,                 // REQUIRED
      "variationId": 4,
      "type": "impression|click|dismiss|submit",   // case-insensitive
      "occurredAt": "2026-08-09T19:30:00Z",        // device clock; future values clamped
      "buttonId": "cta",                  // click on a button
      "url": "https://..."               // click with open_url
    }
  ]
}
```

Event semantics:
- **impression** — at render time, once per display; a re-display (repeatable campaign) is a NEW
  impression with a NEW eventUid.
- **click** — every tap on a button or tappable surface, including dismiss-buttons.
- **dismiss** — message left the screen without click-through (swipe/close/auto-dismiss/back).
- **submit** — EmailCapture successful submission.
- **Never send telemetry for `isTest:true` messages.**

## Response

`202 Accepted` with the counts directly as the body:

```json
{ "accepted": 3, "rejected": 1 }
```

On any 2xx clear the acknowledged events. `rejected` counts individually-dropped malformed events
(missing eventUid/campaignId, unknown type) — they will never succeed, don't retry them. The
counts are diagnostics only; ingestion is fire-and-forget from the SDK's point of view.

| Case | HTTP | Body |
|---|---|---|
| Missing `customerId` or missing/empty `events` | 400 | `ErrorResponse` |
| Bad/missing APIKey | 401 | auth error |
| Customer not found | 404 | `ErrorResponse` (PlayerDoesNotExist) |
| Customer deactivated | 422 | `ErrorResponse` (PlayerInactive) |
| Broker unavailable | 503 | `ErrorResponse` — keep the batch queued and retry |

Server side (context): events are validated, published asynchronously, and persisted deduplicated
on `eventUid` — duplicate flushes can never double-count. The first impression per dispatch anchors
conversion windows and impression caps, so impression timing accuracy matters most.

---

# 3. Variables — `POST integrations/inapp-messages/variables`

## Why this endpoint exists

The sync's `locale` text arrives with variables **already substituted** — a snapshot of the
customer at session start. A message displayed hours later would show stale points or profile
values. This endpoint returns the customer's **current** variable values; the SDK substitutes them
into the message text locally just before display. The backend serves it alone from its own player
store — no downstream hop — so it is cheap enough for the display-critical path.

## Request

```
POST /api/v4.0/integrations/inapp-messages/variables
Headers: APIKey (+ the standard integrations auth), Content-Type: application/json
```

```json
{ "customerId": "10708564181292" }
```

Note this lives on the **integrations** surface (server-key auth, customer named explicitly in the
body), not the bots surface — same conventions as `integrations/inapp-messages/sync` and `/events`.

## Response

```json
{
  "variables": {
    "player_name": "Ahmed",
    "first_name": "Ahmed",
    "player_last_name": "El Assy",
    "player_display_name": "Ahmed El Assy",
    "player_unique_id": "10708564181292",
    "player_email": "ahmed@example.com",
    "points_balance": "1,250",
    "available_points": "1,250",
    "pending_points": "100"
  }
}
```

| Case | HTTP | Meaning |
|---|---|---|
| OK | 200 | Use the values. |
| Customer not found | 404 | Keep the cached rendering. |
| Customer deactivated | 422 | Keep the cached rendering (and expect the next sync to return nothing). |
| Player store degraded | 503 | Retryable; keep the cached rendering meanwhile. |

## SDK behavior contract

1. Keys are **bare token names**; replace every occurrence of `{token}` (single braces) in the
   message's text fields (`header`, `message`, `html`, button labels, EmailCapture strings) with
   the paired value.
2. Values are pre-formatted strings (points already thousand-separated) — insert them verbatim.
   The token names and formatting are identical to the server-side substitution, so a refreshed
   text differs from the cached text only where the customer's actual state changed.
3. Call this just before display **only when the cached text still contains `{` tokens** or when
   displaying long after the sync; apply a short timeout (~2s). On ANY failure or timeout, display
   the sync-time rendering you already hold — never block or drop a display on this call.
4. A token in the text with no key in the map: leave it as-is (forward compatibility — a newer
   server may know tokens an older SDK list does not).
5. Cache the map briefly (e.g. 60s) if several messages may display in quick succession.
