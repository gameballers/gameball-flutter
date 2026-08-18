# In-App Messaging — V4 Integrations Migration

**Status:** implemented 2026-08-17 — see [`../plans/2026-08-17-in-app-messaging-v4-migration.md`](../plans/2026-08-17-in-app-messaging-v4-migration.md)
**Supersedes the wire layer of:** [`2026-08-10-in-app-messaging-backend-integration-design.md`](2026-08-10-in-app-messaging-backend-integration-design.md)
**Reference:** [`docs/reference/backend-sdk-endpoints-reference.md`](../../reference/backend-sdk-endpoints-reference.md) — replaced with the V4 document as part of this work

---

## Why this exists

The backend finalised the in-app messaging API and moved it off the bots namespace onto the V4
integrations surface, where the rest of this SDK already lives. Three things changed that the
module cannot absorb quietly: the endpoints moved, the bots envelope disappeared, and the fields
our trigger parser reads were renamed.

It also closes the open item that has been the sharpest one on this module since fullscreen
landed. `layout` now ships explicitly, so the parser stops guessing.

Everything below was verified against `api.alpha.gameball.app` on 2026-08-17. Where a claim comes
from the document rather than a live response, it says so.

## Decisions taken

| # | Decision | Why |
| --- | --- | --- |
| 1 | **Hard cut to V4.** No dual-path, no fallback to the bots endpoints | Nothing has shipped. 3.3.0 is unreleased, so there is no integrator to keep working, and a compatibility layer would be dead code from the day it was written |
| 2 | **Pin to v4.0; do not route through `getIntegrationsUrl`** | That helper switches to v4.1 when a session token is present. `/api/v4.1/integrations/inapp-messages/sync` answers **401**, not 404 — the path exists but refuses APIKey-only auth. Routing through the helper would break in-app messaging for exactly the hosts that set a session token |
| 3 | **Keep sending `X-GB-TOKEN` when the host has one** | v4.0 sync returns 200 with the header present (verified). Harmless, and it keeps these calls consistent with the sibling integrations endpoints if high-security mode ever applies here |
| 4 | **Read `name` only; no tolerant spelling fallback** | The old parser accepted `eventName`/`metadataKey`/`metadataName` because the naming was agreed verbally. The paths are now disjoint — a v4 response always uses `name` — so tolerance would protect against nothing |
| 5 | **Fold `content.media` into `imageUrl` rather than adding a model field** | The renderer treats them as one slot and video is not rendered, so a second field would be a distinction without a difference |
| 6 | **Keep 50-event chunking even though the server no longer caps it** | It now bounds the cost of a failed retry rather than satisfying a limit. Re-documented as our choice, not theirs |
| 7 | **Build variables now, against the document, knowing it is not deployed** | Decided after the probe. The token scan makes it **inert until the backend sends templates**: no tokens in the text means no call, no cost, no behaviour change. It self-activates the day tokens appear, so building early risks nothing and saves a second pass. The contract contradiction is unresolved and stays recorded as O13 |
| 8 | **Only token-bearing messages take an async display path** | The fetch has to happen before display, but making the whole display path async would put every message through new code for a feature none of them use today. The sync path stays byte-identical for messages without tokens — which is all eight live campaigns |

## What does not change

- The module stays opt-in and additive. No public API moves; `startInAppMessaging` and everything
  around it keep their signatures.
- Evaluation, frequency caps, the cooldown floor, deferral, the pending slot, the presenter and all
  three widgets are untouched. This is a wire-and-parser change.
- Artwork prefetch, added in 3.3.0, is unaffected except that it now has a `media` URL to warm for
  fullscreen campaigns.
- The outbox's at-least-once delivery and its disk persistence are unchanged. The document now
  states dedup on `eventUid` explicitly, which is the guarantee that design already assumed.

---

## Verified against the live V4 endpoints

Measured 2026-08-17 against `api.alpha.gameball.app`, customer `moaty-survey-7`. Everything in
these tables is a real response.

### Sync

| Behaviour | Result | Consequence |
| --- | --- | --- |
| Response shape | A plain payload rooted at `{cooldownSeconds, messages, …}` | **Envelope confirmed gone.** All wrapper handling is deleted, not made optional. The root is not a closed set — see the new-fields row below |
| Campaign coverage | 8 campaigns: 5 modal, 2 slideup, 1 fullscreen | **Closes the old spec's gap.** Alpha previously served only slideups, so the modal and fullscreen paths had never met real data |
| `trigger.name` | Populated on event triggers (`place_order`, `view_product_page`); null on `session_start` | The rename is real and the values are usable |
| `layout` | **Null on all 8** | The field exists but nothing authors it yet. O12's fix ships correct but unexercised against live data |
| `content.media` | Set on the one fullscreen campaign, with `imageUrl` null | **A real gap.** That campaign currently has no artwork source at all |
| `imageUrl` | Either a real URL or a proper `null` — never `""` | No empty-string hazard. The blank-to-null normalisation below is defensive only |
| Action objects | Flat, with every field present-or-null; `navigate` carries a bare route name (`orders`, no slash) | Parses as-is |
| `locale` object (response) | Always carries all 8 keys, mostly null | Matches the shape the parser already tolerates |
| Personalisation | **No `{tokens}` anywhere** — text arrives as `"Hello Sample App User!"` | Server substitutes at sync. See O13 |
| **New root fields** | `quietHours` and `campaignOrdering` appeared between two captures minutes apart, both null, neither in the reference | Ignored safely — see O20 |
| **`platform` is required in practice** | Omitting it returns **`200` with `messages: []`** — not an error | The only mandatory-by-validation field is `customerId`, but a body without `platform` silently yields nothing. Optional in the schema, load-bearing in effect |
| Platform targeting | `platform:1` → 12 campaigns, `platform:2` → 8 | Campaigns are targeted per platform, so the code we send decides what the user can ever see |
| **Unknown platform codes** | `0`, `3`, `99` → `200` with `messages: []` | See O18. `getDevicePlatformCode()` returns **0** on macOS, web and desktop |
| `locale` field (request) | `en` and `ar` both return 8 | It selects a translation, not eligibility — these campaigns carry EN only |
| `appVersion` / `sdkVersion` | Omitting them changes nothing observable | Sent anyway, for targeting we cannot see from here |
| Missing `customerId` | 400 `{code:3000, type:"PAYLOAD_ERROR", message:"customer id is missing"}` | |
| Unknown customer | 404 **with** an `ErrorResponse` body `{code:7000, type:"CUSTOMER_ERROR"}` | Distinguishable from a missing endpoint — see below |
| Bad API key | 401 | |

### Events

| Case | HTTP | Body |
| --- | --- | --- |
| Valid batch | **202** | `{accepted:1, rejected:0}` |
| Mixed: 1 valid + 1 unknown type | **202** | `{accepted:1, rejected:1}` — **one bad event does not poison the good ones** |
| **All events invalid** | **422** | `{code:3003, "no valid events in batch"}` — *not* a 2xx with `rejected:n`, which is what the document implies |
| Missing `customerId` | 400 | `{code:3000, "customer id is missing"}` |
| Empty `events` | 400 | `{code:3000, "no events to ingest"}` |
| **Non-GUID `eventUid`** | **400** | `{code:3016, "…could not be converted to system.guid…"}` — **O9 survives the migration, still undocumented** |
| Bad API key | 401 | |
| `"type": "DISMISS"` | 202 accepted | Case-insensitive, as documented |

### Variables

| Probe | Result |
| --- | --- |
| `POST …/inapp-messages/variables` with a valid customer | **404, empty body** |
| `POST …/inapp-messages/no-such-thing` | **404, empty body** — byte-identical |
| `POST …/sync` with a bogus customer | 404 **with** `{code:7000, "customer does not exist"}` |

A real customer-not-found carries a body; the variables endpoint does not. **It is not deployed.**

### Where these endpoints exist

| Host | `…/inapp-messages/sync` | Reading |
| --- | --- | --- |
| `api.alpha.gameball.app` | `200`, 8 campaigns | Deployed |
| `api.gameball.co` (production) | **`404`, empty body** | **Not deployed** — byte-identical to a bogus path on the same host, which is the control |

So the V4 surface has the same deployment footprint the bots endpoints had: alpha only. O11 does not
close with this migration; it moves to the new paths. See O19.

---

## Section 1 — Wire layer

Replace the two bots constants:

```dart
const inAppMessagesSyncPath  = "$integrationsUrlV4_0/inapp-messages/sync";
const inAppMessagesEventsPath = "$integrationsUrlV4_0/inapp-messages/events";
```

Both request functions drop the `playerUniqueId` query parameter and carry `customerId` in the
body. Sync sends `{customerId, platform, locale, appVersion, sdkVersion}`; events sends
`{customerId, platform, events}`.

Sync's 404 log gains a distinction the probe made available: a 404 whose body parses as an
`ErrorResponse` means the customer does not exist, and a 404 with an empty body means the endpoint
is not deployed on this environment. Those are very different problems and the log should not make
the reader guess.

Sync also logs when it is about to send `platform: 0`. The server answers that with `200` and an
empty list, so without a log the only symptom is "no campaigns, no error" — on macOS, web and any
desktop target, which is where a developer is most likely to be running the sample app. One line
turns an unexplainable silence into an obvious cause. See O18.

## Section 2 — Parser

**Envelope handling is deleted.** `parseSyncResponse` reads `{cooldownSeconds, messages}` directly.
The current code accepts both wrapped and unwrapped payloads; the v4 paths never return a wrapper,
so keeping both shapes would keep a branch no response can reach.

**Trigger fields.** `trigger.name` replaces `trigger.eventName`; each filter's `name` replaces
`metadataKey`/`metadataName`. A null `name` on an event trigger skips the campaign with a log,
which the document requires and which the old parser already did for the missing-name case.

**`layout` becomes authoritative.** `_resolveLayout` reads `content.layout`, gains `image_and_text`
(the fullscreen default spelling), and **loses three things**: the field-sniffing fallback, the
`imageStyle` alternate key, and the Braze `graphic`/`top` spellings. All three were hedges against a
contract that had not been written; it is written now, and keeping them would leave four ways to
express two values. Unknown values fall back to the type's default rather than skipping the message,
because the document calls layout a rendering hint rather than a contract. This is O12 closed.

| Type | Values | Default |
| --- | --- | --- |
| Modal | `text_with_image`, `image_only` | `text_with_image` |
| Fullscreen | `image_and_text`, `image_only` | `image_and_text` |

**`content.media` becomes an artwork source.** Precedence is by type: fullscreen prefers
`media.url` and falls back to `imageUrl`; every other type prefers `imageUrl` and falls back to
`media.url`. `media.type == "video"` is logged and ignored, so a video campaign degrades to no
artwork rather than to a broken player.

**Blank URLs normalise to null.** Not required by the live data, which uses proper nulls. It is
worth one condition because the artwork prefetcher added in 3.3.0 would otherwise pass the whole
campaign over for an empty string, silently and with no way to tell it from a network failure.

## Section 3 — Events transport

`_readEnvelope` is deleted. The outcome is decided by status code alone:

| Status | Outcome | Reason |
| --- | --- | --- |
| 2xx | `accepted` — log `rejected` when non-zero | Verified: 202 with counts |
| 400, 401, 404, 422 | `discard` | The request itself is wrong; an unchanged retry cannot fix it |
| 408, 429, 5xx | `retry` | Transient, including the documented 503 |
| network error, timeout | `retry` | |

**422 is overloaded.** The document assigns it to a deactivated customer; the probe shows an
all-invalid batch returns it too. Both are discard, so behaviour is unaffected — but the code says
so in a comment, because the next reader will otherwise assume 422 means deactivated and be wrong.

**Batching needs no change.** The code already flushes at 30 seconds or 10 events, which is exactly
the documented cadence — checked against `batched_message_analytics.dart` rather than assumed.

What *is* stale is our own handoff document, which still describes the earlier design:

| | `docs/integration/…-handoff.md` says | Code and V4 reference say |
| --- | --- | --- |
| Cadence | 10 seconds / 20 events | **30 seconds / 10 events** |
| Batch size | "1 to 500 events" | chunked at 50 |

That document was written for the backend team, so leaving it wrong is worse than a stale comment —
it describes behaviour they may have built against. Section 6 corrects it.

| Setting | Value | Status |
| --- | --- | --- |
| Flush interval | 30s | already correct |
| Flush at count | 10 | already correct |
| Events per request | 50 | kept — see decision 6 |
| Outbox ceiling | 500 | unchanged |

## Section 4 — Personalisation variables

Built to the document. **Not verifiable today**: the endpoint 404s and the live payload carries no
tokens, so every test here is fixture-driven and the feature is inert in production until both
change. That is a deliberate trade, recorded in decision 7.

### The pieces

A fifth seam, matching the four the module already injects:

```dart
abstract interface class VariableSource {
  /// Current personalisation values for [customerId]. Empty when unavailable.
  Future<Map<String, String>> fetch(String customerId);
}
```

The shipped implementation posts `{customerId}` to `…/inapp-messages/variables` and reads
`{"variables": {...}}`. Any non-200 yields an empty map rather than an exception — the caller's only
correct response to every documented failure is "use what you already have", so there is nothing for
it to distinguish.

Around it: a 60-second cache keyed by `customerId`, cleared on customer change and on `stop()`, and
a pure substitution function.

### Substitution

`substituteTokens(String text, Map<String, String> values)` replaces every `{token}` whose name
matches `[A-Za-z_][A-Za-z0-9_]*`. Rules, straight from the document:

- Values are inserted verbatim; they arrive pre-formatted, including thousand separators.
- **A token with no matching key is left exactly as it is.** Forward compatibility: a newer server
  may know tokens this SDK's map does not, and blanking them would silently delete copy.
- Anything that is not a well-formed token — a stray `{`, `{ spaced }`, `{2}` — is left alone.

Applied to `header`, `body` and each button's `text`. `html` and the EmailCapture strings are
skipped because those message types are not rendered; when they are, this is the function they use.

`GameballInAppMessage` gains a narrow copy method for this — not a general `copyWith`, which would
invite mutation of fields that have no business changing between parse and display.

### Where it happens

In the service, immediately before `present()`, and **only for messages that carry a token**:

```
_tryPresent(campaign):
    widget open, or another message showing, or a presentation in flight  → defer
    message has no '{' token                                             → present now  (unchanged path)
    otherwise                                                            → resolve, then present
```

The scan is a `contains('{')` pre-check before the regex, so the common case costs one character
comparison. The resolve path sets a `_presentationInFlight` flag, awaits the fetch bounded at **2
seconds**, re-checks the display guards on the way back — the screen may have changed during the
await — and then presents the substituted copy. On timeout, on failure, or on an empty map it
presents the original text.

The flag matters: without it, a trigger firing during the await could present a second message on
top of the first. Every existing guard is re-evaluated after the await rather than trusted from
before it.

Impression, cap and dismissal bookkeeping are untouched — they still fire from `onShown`, so a
message whose variables timed out is recorded exactly like any other.

Both durations are injectable, matching `prefetchTimeout`: `variableTimeout` (2s) and
`variableCacheTtl` (60s).

## Section 5 — Fixtures and tests

Today's real response is captured as `test/fixtures/v4-sync-response.json`, replacing the bots-era
`alpha-sync-response.json`. `real_sync_response_test.dart` asserts all eight campaigns parse, which
exercises modal, slideup and fullscreen against real data for the first time — including the
fullscreen campaign whose artwork arrives only as `media`.

`StubMessageSource`'s fixture is rewritten to the V4 shape, keeping the sample app working offline.

Parser tests lose their envelope cases and gain: `trigger.name`, a null `name` on an event trigger,
each `layout` value plus an unknown one, `media` precedence per type, video ignored, and blank URLs.
The events tests become a status-code table matching the one above.

## Section 6 — Documentation

The vendored reference is replaced with the V4 document. The 2026-08-10 spec is annotated to point
here for anything wire-shaped, with O1, O2, O7, O8, O10 and O12 marked resolved.

`docs/integration/in-app-message-analytics-backend-handoff.md` is corrected: its cadence table says
10 seconds / 20 events and its batch size says "1 to 500", none of which has been true for some
time. That document was written *for the backend team*, so a wrong number there is worse than a
wrong comment — it describes behaviour they may have built against.

3.3.0 is unreleased, so CHANGELOG, RELEASE_NOTES and MIGRATION are amended in place rather than
given a new version heading.

---

## Out of scope

- **HtmlFullscreen and EmailCapture** (`messageType` 4 and 5), the `submit` event, and the HTML
  sandbox with its JS bridge. An unknown `messageType` still skips safely.
- **Video media.** `media.type == "video"` parses and is ignored.
- **`log_event`, `log_attribute`, `request_push_permission` actions.** Still unimplemented; they
  parse as unsupported and their buttons are dropped.
- **Custom fonts** (`content.font`) and `allowedAssetUrls`.
- **Dayparting in local time.** The sync request still carries no time zone.

## Open items

Numbering continues from the 2026-08-10 spec. Resolved items are struck through there.

| # | Item | Fallback / current behaviour |
| --- | --- | --- |
| ~~O1~~ | ~~metadata key spelling~~ — **resolved.** It is `name`, on both the trigger and each filter | — |
| ~~O2~~ | ~~Does V1 honour `X-GB-TOKEN`?~~ — **moot.** No player token on this surface; `APIKey` plus `customerId` in the body | — |
| ~~O7~~ | ~~Cap on the `messages` array~~ — **resolved.** No hard batch limit | — |
| ~~O8~~ | ~~Is `eventUid` deduplicated?~~ — **confirmed in writing:** "persisted deduplicated on `eventUid` — duplicate flushes can never double-count" | — |
| ~~O10~~ | ~~All-unsupported batch~~ — **resolved,** though differently than proposed: it is a 422, not a 2xx with counts | Discard |
| ~~O12~~ | ~~No field names the layout~~ — **resolved.** `layout` ships explicitly | Ships unexercised: null on all 8 live campaigns |
| **O3** | Is `autoDismissSeconds` valid on Modal? Still listed under Slideup only | Honour it on Modal if present |
| **O4** | Full `metadataFilters.operator` vocabulary. Only `"Is"` is documented; we implement seven | Map `Is` → equals; skip campaigns using unknown operators |
| **O5** | Are numeric filter values JSON numbers or strings? | Coerce: numeric parse for ordering operators, string compare otherwise |
| **O6** | Is `metadataLogicalOperator: "Or"` needed? | Support `And` only; skip others |
| **O9** | **`eventUid` must be a GUID** — survives the migration, still undocumented, still a hard 400 that discards the whole batch | We generate v4 UUIDs, so this is a landmine rather than a live bug |
| ~~O13~~ | ~~The variables contract contradicts itself~~ — **resolved 2026-08-18.** The backend will **stop substituting variables in the sync response**; text arrives with `{tokens}` intact and the SDK substitutes them from the variables API just before display. This is the model the module was built for, so no code changes — but it moves the async display path from never-used to the normal path for any personalised campaign, and it creates O21 and O22 below | Implemented. Inert until sync stops substituting, then live |
| **O14** | **The token model cannot express conditionals.** `{points} points left` reads badly at zero, and `Welcome {first_name}` reads badly when the name is empty — the failure that made O12 sharp. Braze uses Liquid, which can branch; a flat value map never can. A permanent ceiling, worth knowing before campaigns are authored against it | — |
| **O15** | **The token surface is text-only.** If personalisation ever needs to reach an image URL, a deep link or a button action, a value map cannot carry it, and the sync-time snapshot would stay silently stale in a field nobody thought to refresh | — |
| **O16** | **422 is overloaded** — deactivated customer and all-invalid batch return the same status. Harmless today because both discard, but a future reader mapping 422 to "deactivated" would be wrong | Treat 422 as discard |
| **O17** | **Do high-security-mode hosts need the v4.1 variant?** `/api/v4.1/integrations/inapp-messages/sync` exists and returns 401 to APIKey-only auth. We pin v4.0; if high-security mode ever requires v4.1 here, that is a change we have not made | Pin v4.0 |
| **O18** | **An unrecognised `platform` returns 200 with an empty list, not an error.** `getDevicePlatformCode()` sends `0` for macOS, web and every desktop target, and `0`, `3` and `99` all return zero campaigns silently. A developer demoing on macOS sees a feature that does nothing and has no way to find out why. **Either reject unknown platforms with an error, or add codes for the platforms Flutter actually runs on** | Log loudly before sending `platform: 0`; the request still goes out |
| **O20** | **`quietHours` is enforced SDK-side** — confirmed 2026-08-18. The backend will return a model the SDK evaluates against the **device** timezone, which is the only party that knows the customer's local time. The model's shape is still to come. What the SDK needs from it: the window's start and end, whether it is global or per-campaign, and whether the times are wall-clock local or an offset. `campaignOrdering` is still unanswered | Not implemented, and currently ignored safely. A message caught by a quiet window should be **suppressed**, not deferred: the pending slot is in-memory and dies with the process, while a quiet window is hours long, so "retry when it ends" would essentially never fire. Suppressing costs the occurrence and not the campaign, so it is selected again on the next session outside the window |
| **O21** | **Deployment order is now load-bearing.** If sync stops substituting *before* the variables endpoint is live, every personalised campaign displays raw `{first_name}` to every customer — a total failure, not an edge case. The two changes have to land in the other order, or behind one flag | The SDK cannot detect this. It substitutes what it is given and shows what it has |
| **O22** | **Their rule 4 is no longer safe, and needs replacing.** The contract says an unresolved token should be "left as-is" for forward compatibility. That was correct while the server had already substituted — leaving `{x}` meant leaving whatever the server produced. Once the server sends templates, leaving it as-is means **showing braces to a customer**, and it happens on any timeout, any network blip, or any token the map does not carry. Needs either a per-campaign pre-substituted fallback in the payload, or agreement that the SDK suppresses a message it cannot fully resolve | Currently the raw text is displayed. See the recommendation below |
| **O19** | **Which environment gets these next?** Supersedes O11. The V4 paths are on alpha only — production returns a bare 404, identical to a nonexistent path. The module is inert anywhere else, and the events transport still must not ship ahead of the endpoint | Point `apiPrefix` at alpha for testing |

## Once sync stops substituting

O13's resolution is the right one, and it turns two things that were harmless into
things that are not. Both are recorded above as O21 and O22; this is what the SDK should do about
the second, which is ours to fix.

**The failure fallback becomes user-visible.** Today `_resolveThenPresent` falls back to
`campaign.message` unchanged on a timeout, an error, or an empty map, and `substituteTokens` returns
text untouched when the map is empty. That fallback is currently *the server's own rendering*. Once
the server sends templates it becomes **raw braces on screen**, on a path that runs at app-open time
with a 2-second bound over a mobile network — so "sometimes" rather than "rarely".

Two changes, in this order:

1. **Persist the variable map per customer**, exactly as the campaign cache and the frequency cap
   already persist theirs. A failed fetch then falls back to the customer's *last known* values —
   slightly stale, which is the problem the endpoint was invented to reduce rather than a new one,
   and identical in kind to what the server used to send. This alone removes almost every occurrence.

2. **Suppress a message that still carries unresolved tokens after substitution.** Only reachable
   when there is no persisted map either — a first session on a dead network. Braces in
   customer-facing copy are worse than no message, and suppressing costs the occurrence rather than
   the campaign, so it is selected again next session. Needs a product decision, because it means
   marginally fewer messages on bad networks.

Both are SDK-side and small. Neither is a substitute for getting O21's deployment order right.

## Testing

- **Live fixture.** `v4-sync-response.json`, captured from alpha, parsed in full by
  `real_sync_response_test.dart`. This is the test that would have caught the `media` gap.

  Recapture it with:

  ```bash
  curl -s -X POST https://api.alpha.gameball.app/api/v4.0/integrations/inapp-messages/sync \
    -H 'Content-Type: application/json' -H "ApiKey: $GB_ALPHA_KEY" \
    -d '{"customerId":"moaty-survey-7","platform":2,"locale":"en",
         "appVersion":"3.3.0","sdkVersion":"3.3.0"}' | python3 -m json.tool
  ```

  `platform` is not optional here despite what the schema allows — omit it and the fixture comes
  back empty. Use `2`; `1` returns a different, larger set.
- **Parser.** Plain payload, `trigger.name`, null name on an event trigger, every `layout` value
  and an unknown one, `media` precedence per message type, video ignored, blank URL normalisation.
- **Events transport.** One case per row of the status table, driven through a fake HTTP client.
- **Batching.** Unchanged and already correct at 30s/10 events; the existing tests stay as they are.
- **Variables.** Token substitution as a pure function — known token, unknown token left intact,
  malformed brace left intact, multiple occurrences; the 60s cache; the 2s timeout falling back to
  the original text; a failed fetch presenting unchanged; and that a message with no token never
  calls the source at all. All fixture-driven — the endpoint 404s, so none of this is verified live.
- **Request shape.** That `customerId` and `platform` reach the body rather than the query string,
  and that a `platform: 0` sync logs before it is sent — the one case whose failure is a silent
  empty list rather than an error.
- **Unchanged suites stay green.** 418 tests pass today; the envelope and chunking tests are the
  only ones expected to be deleted or rewritten, and each deletion is justified by a contract that
  no longer exists.

## Compatibility

No public API changes. The compatibility invariant holds: a host that upgrades and does not call
`startInAppMessaging` observes nothing — no requests, no timers, no overlay, no stored state.

For a host that has opted in, the only visible difference is which endpoint is called. This does
**not** widen where the feature works: the V4 paths are on alpha and nowhere else, exactly as the
bots paths were. What the migration buys is that the module now speaks the contract the backend
intends to keep, so the day production gets these endpoints nothing else has to change.
