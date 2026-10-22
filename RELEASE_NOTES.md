# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v4.0.0

**Release Date**: 2026-10-22
**Version**: 4.0.0
**Type**: Major Release

---

## 🎉 What's New

v4.0.0 raises the minimum supported versions to **iOS 15.0** and **Android API 24 (Android 7.0)**, and adds **in-app messaging**: campaigns authored in the Gameball dashboard, displayed inside your app. It is opt-in — an app that upgrades without calling `startInAppMessaging` behaves exactly as it did on v3.3.1. No requests, no timers, no overlay and no stored state exist until you opt in.

- **In-app messaging**: modal, slideup and fullscreen campaigns from the Gameball dashboard, shown inside your app
- **Triggers**: session start, and custom events filtered on their metadata
- **Purchase logging**: `logPurchase(...)` for purchase-triggered campaigns
- **Host control**: `beforeDisplay`, `onAction`, `onNavigate` and the `onInAppMessage` stream
- **Raised minimums**: iOS 15.0+ and Android API 24+ (Android 7.0)

---

## 🚀 Key Features

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
GameballApp.getInstance().sendEvent(
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

Campaign text can contain `{token}` placeholders. Just before a message with placeholders is shown, the SDK fetches the customer's current values and fills them in, so points balances and profile fields are current at the moment the message appears.

It is bounded and never stops a message from showing: the fetch waits at most two seconds and is cached for a minute. If the values don't arrive — a timeout, no network, or an error — the placeholders are removed rather than shown as raw `{braces}`. A message with no placeholders skips the call entirely.

> Requires `integrations/inapp-messages/variables` to be enabled for your account. Until then, placeholders are removed from the text.

### 🛒 Purchase logging

```dart
GameballApp.getInstance().logPurchase(
  customerId: 'customer-123',
  productId: 'sku-001',
  price: 49.99,
  currency: 'USD',
);
```

`logPurchase` sends a `purchase` event to Gameball with `productId`, `price`, `currency` and `quantity` as metadata, so purchase-triggered campaigns can filter on them.

### 🖐️ Taking control

```dart
GameballApp.getInstance().startInAppMessaging(
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
    // e.g. router.push(route);
  },
);
```

`onInAppMessage` is a stream of every message the SDK selects, whatever the host then decides to do with it.

### ⚠️ Availability

In-app messaging needs the `integrations/inapp-messages` endpoints enabled for your account. Where they aren't, the SDK records the 404 in its debug log and stays silent — nothing surfaces to your app and nothing else is affected.

---

## ⚠️ Breaking Changes

**This is a major release.** Apps targeting older OS versions must raise their minimums before upgrading.

- **iOS**: minimum raised from 12.0 to **15.0**
- **Android**: minimum raised from API 21 (Android 5.0) to **API 24 (Android 7.0)**

There are no changes to the public API — every v3.x call keeps its signature and behaviour, and in-app messaging does nothing until you call `startInAppMessaging`.

---

## 🔄 Changes

- Raised the minimum supported iOS version to 15.0 and Android version to API 24 (Android 7.0)
- Added in-app messaging: `startInAppMessaging`, `stopInAppMessaging`, `isInAppMessagingStarted` and the `onInAppMessage` stream
- Added modal, slideup and fullscreen messages, triggered on session start or by custom events with metadata filters
- Added `logPurchase(...)` to send purchase events that campaigns can target
- Added `beforeDisplay`, `onAction` and `onNavigate` hooks to control display, taps and routing
- Added automatic impression, click and dismissal analytics, kept on the device until sent
- Added `gameballInAppMessagingLogging` to control in-app messaging debug logs
- The package published to pub.dev now contains only the SDK sources

---

## 🔧 Technical Details

### Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 24+ (Android 7.0)
- iOS 15.0+

---

## 📚 Migration Support

Raise your app's `minSdk` to 24 and its iOS deployment target to 15.0. No Dart code changes are required — all v3.x calls work without modification. In-app messaging is opt-in; to adopt it, pass your `MaterialApp`'s navigator key to `startInAppMessaging` and call `stopInAppMessaging()` on logout.

### Migration Resources
- **[Migration Guide](MIGRATION.md#migration-guide-v3x--v400)**: Step-by-step migration instructions
- **[README](README.md)**: Complete usage documentation with examples
- **[Changelog](CHANGELOG.md)**: Detailed list of all changes

### Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-flutter/issues

---

## 📦 Installation

```yaml
dependencies:
  gameball_sdk: ^4.0.0
```

---

## Previous Release: v3.3.1

**Release Date**: 2026-10-19
**Type**: Patch Release

Fixed the widget close button direction, `setLanguage(lang)` being outranked by an earlier preferred language, widget URL encoding, and `initializeCustomer`/`sendEvent` callback reporting; unsupported language codes now fall back to `en` and customers are always initialized as registered. See [CHANGELOG.md](CHANGELOG.md) for the full history.
