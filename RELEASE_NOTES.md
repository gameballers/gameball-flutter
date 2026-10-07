# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.3.1

**Release Date**: 2026-09-30
**Version**: 3.3.1
**Type**: Patch Release

---

## 🎉 What's New

v3.3.1 is a bug-fix release: the widget's close button no longer lands on the wrong side, `setLanguage(lang)` takes effect when a preferred language was already set, and failed `initializeCustomer` requests now reach your callback. There are no API changes.

### 🐛 Fixed: Close Button Direction

The widget's close button is now positioned from the widget's own language alone: left for Arabic, right for every other language.

Previously only the codes on the SDK's built-in left-to-right list (`en`, `fr`, `es`, …) got an explicit side. Any other code (e.g. `"tr"`) got none, so the button fell back to the host app's text direction instead — in a left-to-right app, the top-left corner rather than the top-right.

### 🐛 Fixed: Runtime Language Switching

`setLanguage(lang)` was only setting the SDK's global preferred language, which is resolved *after* the customer's preferred language. When a `preferredLanguage` had been passed to an earlier `initializeCustomer`, that value won and the call silently had no effect.

```dart
GameballApp.getInstance().setLanguage("ar");
```

It now takes precedence, so the change applies to `showProfile` presentations that don't pass their own `lang` and to subsequent `initializeCustomer`/`sendEvent` requests.

### 🔄 Changed: Preferred Language Sync

`setLanguage(lang)` now also mirrors the new language onto the customer's Gameball profile, so server-driven communications (campaigns, emails) follow it as well — previously the change only affected this device. The profile update goes to the most recently initialized customer (remembered across app launches) and is skipped until one has been initialized; to set the language before that, pass it as `preferredLanguage` to `initializeCustomer`.

### 🔄 Changed: Registered Customers Only

The SDK now always initializes customers as registered: `initializeCustomer` sends `guest` as `false`, and `InitializeCustomerRequestBuilder().isGuest(...)` is ignored.

### 🐛 Fixed: Customer Initialization Errors

A failed `initializeCustomer` request never reached its callback — the error surfaced as an unhandled async error instead, which crash reporters may record as a crash. The callback now receives it as `(null, error)`.

### Who should upgrade

Any app that calls `setLanguage(lang)` after passing a `preferredLanguage` to `initializeCustomer`, presents the widget in a language outside the SDK's built-in left-to-right list, or relies on the `initializeCustomer` callback to handle failures.

---

## 🔄 Changes

- Fixed the widget close button following the host app's text direction for languages outside the built-in left-to-right list
- Fixed `setLanguage(lang)` being outranked by a preferred language set through `initializeCustomer`
- `setLanguage(lang)` now mirrors the preferred language onto the customer's Gameball profile
- `initializeCustomer` now passes request failures to its callback
- `initializeCustomer` now always sends `guest: false`; `InitializeCustomerRequestBuilder().isGuest(...)` is ignored
- Internal diagnostic logging now only records widget usage
- Removed the undocumented `isLtr` helper and `ltrLanguageCodes` list from `utils/language_utils.dart`

---

## Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 21+
- iOS 12.0+

---

## Migration

No code changes required — all v3.x code works without modification. One behavior to check: failed `initializeCustomer` requests now reach the callback as `(null, error)`, so a callback that assumes it only runs on success should check `error` before using the response. Also, `isGuest(...)` is now ignored, so apps that passed `isGuest(true)` now initialize registered customers.

See [MIGRATION.md](MIGRATION.md) for details.

---

## Installation

```yaml
dependencies:
  gameball_sdk: ^3.3.1
```

---

## Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-flutter/issues

---

## Previous Release: v3.3.0

**Release Date**: 2026-09-02
**Type**: Minor Release

Per-call widget language (`ShowProfileRequestBuilder().lang(...)`), a global language switch (`GameballApp.setLanguage(lang)`), and push notification click tracking (`GameballApp.handlePushClick(...)`). See [CHANGELOG.md](CHANGELOG.md) for the full history.
