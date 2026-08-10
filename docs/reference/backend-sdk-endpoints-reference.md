# In-App Messages — SDK Endpoints Reference

The single reference for SDK/widget developers: every endpoint the device calls, what it expects,
what it returns, and the behavior contract. Two endpoints exist; nothing else is ever called by the
device for in-app messaging.

| # | Endpoint | Purpose | When |
|---|---|---|---|
| 1 | `POST bots/inapp/sync` | Fetch every eligible, pre-rendered message | Once per session start |
| 2 | `POST bots/inapp/events` | Report impression / click / dismiss / submit telemetry | Batched flushes |

Custom/business events (purchases, add-to-cart, anything about what the user did in the app) keep
going to the normal Gameball events endpoint, unchanged. Boundary rule: message lifecycle → these
endpoints; user behavior → events endpoint. Neither carries the other's payload.

---

# 1. Sync — `POST bots/inapp/sync`

## Request

**V3 (mobile SDK — use this):**
```
POST /api/v3.0/bots/inapp/sync?playerId={encryptedPlayerId}
Headers: APIKey, x-gb-token, Content-Type: application/json
```
- `playerId` (query, **required**): the encrypted internal player id, exactly as received from the
  init/player-info call — same value used by `bots/Balance/{playerId}`. Zero/missing →
  `success:false, errorMsg:"Invalid customer id"`. Malformed → HTTP 400. Cross-checked against the
  token; a mismatch is rejected. Identity always comes from `x-gb-token`, never the body.

**V1 (widget/legacy):** `POST /api/v1.0/bots/inapp/sync?playerUniqueId={externalId}&playerId={enc}` —
`APIKey` only; encrypted id wins when both present.

**Body:**
```json
{ "platform": 1, "locale": "en", "appVersion": "3.2.1", "sdkVersion": "1.0.0" }
```
`platform`: 1 = iOS, 2 = Android. `locale` drives translation choice (device locale → player's
preferred language → en → any).

## Response

Standard bots wrapper `{ response, success, errorMsg, errorCode, liveMode }`. The payload:

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
        "metadataLogicalOperator": "And",
        "metadataFilters": [ { "metadataId": 4051, "value": "electronics", "operator": "Is" } ],
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
  "allowedAssetUrls": ["https://..."],                                        // HtmlFullscreen
  "submitButtonColors": { ... }, "onSuccessAction": "close|showSuccessMessage", // EmailCapture
  "buttons": [ { "id": "b1", "action": { ... }, "colors": { ... } } ]         // Modal & Fullscreen
}
```

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
| Missing/zero playerId (V3) | 200 | `success:false, errorMsg:"Invalid customer id", errorCode:4` |
| Malformed encrypted playerId | 400 | `{"code":13,"message":"Invalid value for: playerId"}` |
| Bad token | 401 | auth error |
| Inactive player | 200 | `success:false, errorMsg:"PlayerInactive"` |
| Player not found | 200 | `success:true`, empty `messages` |

---

# 2. Events — `POST bots/inapp/events`

## Queue & flush rules

- Queue events on disk until acknowledged 2xx.
- Flush on ANY of: **10 events**, **30 seconds**, **app background/session end**, **immediately
  before executing an open_url/navigate action**.
- Max **50 events per call**; larger queues flush in chunks. Retries are safe (server dedupes).

## Request

Same auth/identity conventions as sync:
- V3: `POST /api/v3.0/bots/inapp/events?playerId={encryptedPlayerId}` + `x-gb-token`
- V1: `POST /api/v1.0/bots/inapp/events?playerUniqueId={ext}&playerId={enc}`

```json
{
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

```json
{ "response": { "accepted": 3, "rejected": 1 }, "success": true, "errorCode": 0, "liveMode": true }
```

On `success:true` clear the acknowledged events. `rejected` counts individually-dropped malformed
events (missing eventUid/campaignId, unknown type) — they will never succeed, don't retry them.

| Case | HTTP | Body |
|---|---|---|
| >50 events | 200 | `success:false, errorMsg:"Batch exceeds the maximum of 50 events"` |
| Empty events | 200 | `success:false, errorMsg:"No events to ingest"` |
| All events invalid | 200 | `success:false, response:{accepted:0,rejected:N}` |
| Bad token (V3) | 401 | auth error |

Server side (context): events are validated, published asynchronously, and persisted deduplicated
on `eventUid` — duplicate flushes can never double-count. The first impression per dispatch anchors
conversion windows and impression caps, so impression timing accuracy matters most.
