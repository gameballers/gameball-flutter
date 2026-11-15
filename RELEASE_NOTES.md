# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v4.1.0

**Release Date**: 2026-11-19
**Version**: 4.1.0
**Type**: Minor Release

---

## 📱 What's New

v4.1.0 brings **game campaigns** to in-app messaging, shows campaigns when **any of their conditions** match, and reports **influenced opens** of Gameball pushes on Android. There are no breaking changes.

- **Game campaigns**: a spin the wheel, quiz or scratch and win opens itself over your app on its in-app messaging trigger
- **Any of the conditions**: a campaign set to match any of its event conditions shows when one of them matches
- **Influenced opens**: `handlePushReceived(payload, {sentTime})` reports app opens that a push led to without being tapped (Android)
- **Push taps counted once**: `handlePushClick` reports to the new `push-engagement` endpoint, once per tap
- **Widget host on the configuration**: `GameballConfig.widgetUrlPrefix` for the profile widget and game campaigns
- **Game events**: `onGameEvent` on `startInAppMessaging` reports what a campaign posts

---

## 🚀 Key Features

### 🎡 Game campaigns

A campaign the merchant set to open itself over your app arrives in the same sync as in-app messages and displays through the same overlay, so **there is nothing extra to integrate**:

```dart
GameballApp.getInstance().startInAppMessaging(
  customerId: "customer_123",
  navigatorKey: navigatorKey,
);
```

The SDK opens the game itself and shows the card only once the game has finished drawing, as a centred card or fullscreen, with its own close button. Games follow the message frequency rules — the repeat setting and minimum interval, the cooldown between any two in-app displays, and quiet hours — and a game the customer has played isn't offered again until the next successful sync. A game is opened only from this session's sync, never from the offline cache, and reports no in-app messaging telemetry. `onGameEvent` reports what a campaign posts, most usefully that the customer played it.

### 🔀 Any of the conditions

A campaign whose metadata filters are joined by Any (`OR`) shows when at least one of them matches. Such campaigns used to be skipped.

### 📣 Influenced opens

An influenced open is an app open that no tap caused, within 30 minutes of an untapped Gameball push arriving:

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await GameballApp.getInstance().handlePushReceived(
    message.data,
    sentTime: message.sentTime?.millisecondsSinceEpoch,
  );
}

FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
FirebaseMessaging.onMessage.listen((message) {
  GameballApp.getInstance().handlePushReceived(
    message.data,
    sentTime: message.sentTime?.millisecondsSinceEpoch,
  );
});
```

`handlePushReceived` works without `init`, so it runs in the background isolate. Influenced opens are reported on Android only: on iOS, Dart doesn't run for alert pushes that arrive in the background. Swipe-aways aren't reported.

### 👆 Push taps counted once

`handlePushClick(payload, {callback, sessionToken})` now reports to `push-engagement`, which replaces `push-click`, and counts a tap once per app run, so calling it from both `getInitialMessage` and `onMessageOpenedApp` is safe. Taps and influenced opens stay on v4.0 when a session token is set.

### 🌐 Widget host on the configuration

`GameballConfig.widgetUrlPrefix` sets the widget host once at `init`, for the profile widget and any campaign a message opens. A per-call `ShowProfileRequest.widgetUrlPrefix` still overrides it for one presentation.

---

## 🐛 Fixes

- **Game end dates**: an end date the sync sends without a time zone is read as UTC; it used to be read as device-local time, so games ended early or late by the device's UTC offset
- **Waiting messages**: a message waiting for its turn is rechecked before it shows, and dropped if it has passed its end date or the latest sync no longer carries it

---

## ⚠️ Breaking Changes

None. Every v4.0.0 call keeps its signature and behaviour.

---

## 🔄 Changes

- Added game campaigns to in-app messaging, and `onGameEvent` on `startInAppMessaging`
- Added any-condition (OR) event triggers
- Added `handlePushReceived(payload, {sentTime})` for influenced opens (Android)
- Added `GameballConfig.widgetUrlPrefix`
- Changed push tap reporting to the `push-engagement` endpoint, once per tap
- Fixed game end dates sent without a time zone, and waiting messages that had expired

---

## 🔧 Technical Details

### Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 24+ (Android 7.0)
- iOS 15.0+
- For influenced opens: firebase_messaging's `onBackgroundMessage` and `onMessage` handlers

---

## 📚 Migration Support

No code changes are required. To report influenced opens, call `handlePushReceived` from firebase_messaging's `onBackgroundMessage` handler and `FirebaseMessaging.onMessage`.

### Migration Resources
- **[Migration Guide](MIGRATION.md#migration-guide-v40x--v410)**: Step-by-step migration instructions
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
  gameball_sdk: ^4.1.0
```

---

## Previous Release: v4.0.0

**Release Date**: 2026-10-22
**Type**: Major Release

Raised the minimum supported versions to iOS 15.0 and Android API 24 (Android 7.0), and added in-app messaging: modal, slideup and fullscreen campaigns from the Gameball dashboard, triggered on session start or by custom events, with `logPurchase(...)`, display hooks, the `onInAppMessage` stream and automatic analytics. See [CHANGELOG.md](CHANGELOG.md) for the full history.
