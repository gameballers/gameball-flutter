# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.3.0

**Release Date**: 2026-08-17
**Version**: 3.3.0
**Type**: Minor Release

---

## 🎉 What's New

v3.3.0 adds **in-app messaging**: campaigns authored in the Gameball dashboard, displayed inside your app. It is opt-in and additive — an app that upgrades and changes nothing behaves exactly as it did on 3.2.1. No requests, no timers, no overlay and no stored state exist until you call `startInAppMessaging`.

### 💬 Opting in

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(navigatorKey: navigatorKey, home: const HomeScreen());

GameballApp.getInstance().startInAppMessaging(
  customerId: 'customer-123',
  navigatorKey: navigatorKey,
);
```

The navigator key is how the SDK draws above your routes, so it has to be the one your `MaterialApp` (or `CupertinoApp`) uses. Call `stopInAppMessaging()` on logout.

### 🖼️ Message types

**Modal** — a centred card over a dimmed background, with up to two buttons. Blocks the app until dismissed.

**Slideup** — a banner at the top or bottom edge. It does not block: the app stays usable underneath, it carries no buttons because the whole surface is the tap target, and it is dismissed by swiping toward its own edge.

**Fullscreen** — edge to edge, in one of two compositions. Either image over copy with the buttons below, or artwork filling the screen with the buttons floated over it. A fullscreen campaign can also insist on portrait or landscape, and waits rather than showing sideways copy nobody can read.

### 🎯 Triggers

**Session start** fires on launch, and again when the app returns to the foreground after more than the session timeout (30 seconds by default).

**Custom events** match on the event name and, optionally, on the event's metadata:

```dart
gameballApp.sendEvent(
  EventBuilder()
      .customerId('customer-123')
      .eventName('add_to_cart')
      .eventMetaData('productId', 'sku-001')
      .build(),
  (success, error) {},
);
```

A campaign targeting `add_to_cart` can filter on `productId`, using equality, ordering or contains comparisons. A purchase logged through `logPurchase` arrives as an event named `purchase` whose `productId`, `price`, `currency` and `quantity` are all available to filters — so "any purchase" and "a purchase over 100" are the same trigger, filtered differently.

### 🚦 What controls whether a message actually shows

Per-campaign frequency caps, which survive a restart. A minimum interval between any two displays, set by the backend rather than hardcoded. Campaign expiry. Priority order when more than one campaign matches. And a message that cannot be drawn right now — because your own Gameball widget is open, or another message is showing — waits instead of being lost.

### 📊 Analytics

Impressions, clicks and dismissals are reported automatically. A button tap is a click carrying the button's id. Events are batched rather than sent one at a time, and the buffer is written to device storage after every change, so an impression logged a second before a force-quit still arrives on the next launch.

Artwork is loaded at sync rather than at display time, so an impression is only ever recorded for a message whose image the user could actually see.

### 🔤 Personalisation

Campaign text arrives already personalised at session start. For a message displayed much later, the SDK refreshes the values just before showing it, so points balances and profile fields are current rather than a snapshot from launch.

It is bounded and cannot delay or suppress a message: the fetch is capped at two seconds, cached for a minute, and any failure — including no network — falls back to the text already held. A message with no personalisation tokens skips the call entirely.

> This ships ahead of the endpoint it calls. Until `integrations/inapp-messages/variables` is enabled for your account, campaign text is the sync-time rendering, which is exactly what it was before.

### 🖐️ Taking control

```dart
gameballApp.startInAppMessaging(
  customerId: 'customer-123',
  navigatorKey: navigatorKey,
  // Postpone during checkout rather than interrupting it.
  beforeDisplay: (message) => isCheckingOut
      ? GameballDisplayDecision.later
      : GameballDisplayDecision.show,
  // Handle the tap yourself; return false to let the SDK act.
  onAction: (message, button, action) => false,
  // Route through go_router instead of named routes.
  onNavigate: (String route, Map<String, Object>? arguments) {
    context.push(route);
  },
);
```

`onInAppMessage` is a stream of every message the SDK selects, whatever the host then decides to do with it.

### ⚠️ Availability

In-app messaging needs the `integrations/inapp-messages` endpoints enabled for your account. Where they are not yet, the SDK records the 404 in its diagnostic log and stays silent — nothing surfaces to your app and nothing else is affected.

---

## Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 21+
- iOS 12.0+

---

## Migration

No changes required — all v3.x code works without modification. In-app messaging is opt-in; an app that does not call `startInAppMessaging` behaves exactly as before.

See [MIGRATION.md](MIGRATION.md) for details.

---

## Installation

```yaml
dependencies:
  gameball_sdk: ^3.3.0
```

---

## Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-flutter/issues

---

## Previous Release: v3.2.1

**Release Date**: 2026-08-06
**Type**: Patch Release

Corrected the widget URL's `shop` parameter, which was being appended as a second `platform` key and broke coupon redemption for apps setting both. See [CHANGELOG.md](CHANGELOG.md) for the full history.

---

## Previous Release: v3.2.0

**Release Date**: 2026-07-01
**Type**: Minor Release

Widget event channel (`widgetEventCallback` receiving events such as `gameCompleted`), widget dismissal controls (`GameballApp.hideProfile()` and web-initiated `window.GameballWidget.closeWidget()`), external-link handling with optional `externalLinkCallback`, optional `mobile`/`email` channel-merging parameters, diagnostic logging, and widened dependency ranges. See [CHANGELOG.md](CHANGELOG.md) for the full history.
