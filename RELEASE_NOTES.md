# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.3.0

**Release Date**: 2026-08-29
**Version**: 3.3.0
**Type**: Minor Release

---

## ✨ What's New

v3.3.0 adds **per-call and global language control** and **push notification click tracking**. All v3.2.x and v3.1.x code continues to work without modification — every addition is backward compatible.

### Per-Call Widget Language

`ShowProfileRequestBuilder` now accepts an optional `lang` (2-letter code, e.g. `"en"`, `"ar"`) to present that one widget in a specific language:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .lang("ar")
    .build();

GameballApp.getInstance().showProfile(context, request);
```

When `lang` is omitted, the SDK's existing resolution applies: customer preferred language, then global preferred language, then `"en"`.

### Global Language Switch

`GameballApp.setLanguage(lang)` changes the SDK's global language on demand, without re-calling `init`:

```dart
GameballApp.getInstance().setLanguage("ar");
```

This changes the fallback used by future `showProfile` presentations that don't pass their own `lang` (a per-call `lang` still wins) and `initializeCustomer`/`sendEvent` requests. Invalid codes are ignored.

### Push Click Tracking

`GameballApp.handlePushClick(payload, {callback, sessionToken})` reports taps on Gameball push notifications so campaign clicks are counted. Call it from your notification-tap handler with the notification's data payload (e.g. `RemoteMessage.data` from `onMessageOpenedApp` / `getInitialMessage`):

```dart
FirebaseMessaging.onMessageOpenedApp.listen((message) {
  final isGameball = GameballApp.getInstance().handlePushClick(
    message.data,
    callback: (reported, error) {
      if (error != null) {
        print('Click report failed: $error');
      } else {
        print('Click reported: $reported');
      }
    },
  );

  if (!isGameball) {
    // Not a Gameball notification — run your own handling.
  }
});
```

It returns `true` when the notification is a Gameball one; the tap is reported to Gameball when the payload carries a click token. An optional `sessionToken` overrides the global session token for this request.

---

## 🔄 Changes

- Added optional `ShowProfileRequestBuilder.lang(...)` (per-presentation language override)
- Added `GameballApp.setLanguage(lang)` (global language switch)
- Added `GameballApp.handlePushClick(payload, {callback, sessionToken})` (push click tracking)

---

## Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 21+
- iOS 12.0+

---

## Migration

No changes required — all v3.x code works without modification.

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

Fixed the widget `shop` parameter being sent as a duplicate `platform` key, which broke widget coupon redemption for apps setting both `platform` and `shop`. See [CHANGELOG.md](CHANGELOG.md) for the full history.
