# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.2.0

**Release Date**: 2026-07-01
**Version**: 3.2.0
**Type**: Minor Release

---

## 🎉 What's New

v3.2.0 introduces a **widget event channel** so your app can react to what customers do inside the widget, **dismissal controls** for both the widget and the host app, **external-link handling**, optional **channel-merging parameters**, and internal **diagnostic logging**. All v3.1.x code continues to work without modification — every addition is backward compatible.

### Widget Event Channel

The widget can now post events (e.g. game completion, reward redemption) back to your app. Register `widgetEventCallback` and each event arrives as a `Map<String, dynamic>` with a top-level `type` and a nested `metadata`. On a parse failure the callback is invoked with `(null, exception)`:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .widgetEventCallback((event, error) {
      if (error != null) return;                                   // parse failure
      final type = event?['type'] as String?;                      // e.g. "gameCompleted"
      final metadata = event?['metadata'] as Map<String, dynamic>?;

      if (type == 'gameCompleted') {
        final hasWon = metadata?['hasWon'] as bool? ?? false;
        final rewardType = metadata?['rewardType'] as String?;     // "Default", "Bonus", "NoReward"…
        final discountType = metadata?['discountType'] as String?; // "FreeShipping", "Percentage"… (null if not a coupon win)
        final rewardName = metadata?['rewardName'] as String?;     // localized display name
        final campaignId = metadata?['campaignId'] as String?;     // "90340"
        final campaignType = metadata?['campaignType'] as String?; // "spinTheWheel", "scratchCard"…
        if (hasWon) refreshBalance();
      }
    })
    .build();

GameballApp.getInstance().showProfile(context, request);
```

The `gameCompleted` event's `metadata` carries:

| Field | Type | Description |
|---|---|---|
| `hasWon` | `bool` | Whether the player won a reward this round |
| `rewardType` | `String?` | Reward category — `Default`, `Friend`, `Bonus`, `CustomText`, `Streak`, `NoReward` |
| `discountType` | `String?` | Coupon kind when the win is a coupon — e.g. `Fixed`, `Percentage`, `FreeShipping`, `FreeProduct`, `Custom`, `RechargeFixed`, `RechargePercentage`, `ExternalReward`; `null` for non-coupon wins |
| `rewardName` | `String?` | Localized, human-readable reward name |
| `campaignId` | `String` | Challenge / campaign identifier |
| `campaignType` | `String?` | Game type — `spinTheWheel`, `slotMachine`, `quiz`, `scratchCard`, `matchCards`, `catcher`, `ticTacToe`, `shooter`, `puzzle`, `tapTarget`, `highwayDrive` |

> All `gameCompleted` values arrive as `String` or `bool` — there are no numeric fields.

### Web-Initiated Close

The widget can dismiss its own webview by calling `window.GameballWidget.closeWidget()` — no host code required.

### Host-Initiated Dismiss

Dismiss the widget programmatically from your app (e.g. on logout or a deep link):

```dart
GameballApp.getInstance().hideProfile();   // no-op when nothing is shown
```

### External-Link Handling

Links the widget flags with `gbExternalBrowser=true` open in the system browser. Optionally intercept them with `externalLinkCallback`:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .externalLinkCallback((url) {
      // open `url` your own way — in-app browser, router, etc.
    })
    .build();
```

### Channel-Merging Parameters

`showProfile` now accepts optional `mobile` and `email`, so the widget can merge a guest/known profile with a customer's contact channels:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .mobile("+201234567890")
    .email("customer@example.com")
    .build();

GameballApp.getInstance().showProfile(context, request);
```

### Diagnostic Logging

The SDK now records internal diagnostic logs to aid troubleshooting. This is automatic and requires no integration changes.

---

## 🔄 Changes

- Added `ShowProfileRequestBuilder().widgetEventCallback(...)` — `void Function(Map<String, dynamic>? event, Exception? error)?`
- Added `ShowProfileRequestBuilder().externalLinkCallback(...)` — `void Function(String url)?`
- Added optional `mobile` and `email` on `ShowProfileRequestBuilder` (channel merging)
- Added `GameballApp.hideProfile()`
- Exposed `window.GameballWidget.closeWidget()` to the widget webview
- Added internal SDK diagnostic logging
- Unified the `x-gb-agent` header format to `GB/flutter/<version>`
- Widened `share_plus`/`device_info_plus`/`package_info_plus` version ranges (floors unchanged; opting into `share_plus` 13.x requires Flutter 3.38.1+ / Dart 3.10+)

---

## Usage Examples

**React to a reward and refresh the wallet:**
```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .widgetEventCallback((event, error) {
      if (error != null) return;
      final metadata = event?['metadata'] as Map<String, dynamic>?;
      if (metadata?['hasWon'] as bool? ?? false) {
        showWinAnimation(metadata?['rewardName'] as String? ?? '');
        refreshBalance();
      }
    })
    .build();

GameballApp.getInstance().showProfile(context, request);
```

**Dismiss on logout:**
```dart
void logout() {
  GameballApp.getInstance().hideProfile();
  clearSession();
}
```

---

## Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 21+
- iOS 12.0+

---

## Migration

No changes required — all v3.1.x and v3.0.0 code works without modification. The new callbacks, parameters, and `hideProfile()` are additive. Diagnostic logging is automatic.

See [MIGRATION.md](MIGRATION.md) for details.

---

## Installation

```yaml
dependencies:
  gameball_sdk: ^3.2.0
```

---

## Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-flutter/issues

---

## Previous Release: v3.1.1

**Release Date**: 2025-12-15
**Type**: Patch Release

Guest mode support — the profile widget can be shown without customer authentication, and the `ShowProfileRequest` builder no longer requires a customer ID. See [CHANGELOG.md](CHANGELOG.md) for the full history.
