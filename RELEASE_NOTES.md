# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.3.1

**Release Date**: 2026-10-19
**Version**: 3.3.1
**Type**: Patch Release

---

## 🎉 What's New

v3.3.1 is a bug-fix release: the widget's close button no longer lands on the wrong side, `setLanguage(lang)` takes effect when a preferred language was already set, failed `initializeCustomer` requests now reach your callback, unsupported language codes fall back to `en`, widget URL values reach the widget unchanged, and `sendEvent` reports its results correctly. There are no API changes.

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

### 🔄 Changed: Supported Languages

Language codes from `init`, `setLanguage`, `initializeCustomer` and a per-call `lang` are now matched case-insensitively against the supported languages: `en`, `ar`, `fr`, `es`, `de`, `pt`, `pl`, `it`, `hu`, `zh-tw`, `nl`, `sv`, `no`, `dk`, `ja`. Any other code falls back to `en`.

Previously any two-character code was accepted, so one that isn't a real language code (e.g. `"عر"`) could make SDK requests fail until the language was changed again or the app restarted.

Codes must match one of these exactly (letter case doesn't matter): regional variants such as `ar-EG` and three-letter codes such as `ara` aren't mapped and fall back to `en`. `initializeCustomer` still sends `preferredLanguage` to Gameball exactly as passed; only the language the SDK itself uses falls back to `en`.

### 🔄 Changed: Registered Customers Only

The SDK now always initializes customers as registered: `initializeCustomer` sends `guest` as `false`, and `InitializeCustomerRequestBuilder().isGuest(...)` is ignored.

### 🐛 Fixed: Customer Initialization Errors

A failed `initializeCustomer` request never reached its callback — the error surfaced as an unhandled async error instead, which crash reporters may record as a crash. The callback now receives it as `(null, error)`.

### 🐛 Fixed: Widget URL Encoding

The customer ID, session token, `openDetail`, platform, shop and API key are now encoded in the widget URL, like `mobile` and `email` already were. Previously they were added as-is, so a `+` arrived as a space (e.g. a session token `a+b/c=`), an `&` split the value into an extra parameter, and a `#` cut off every parameter after it.

### 🐛 Fixed: Event Callback

`sendEvent` reported `false` unless the response status was exactly 200, so events the server accepted with `202` looked failed, and a failed request never reached the callback — it surfaced as an unhandled async error instead. Any accepted (2xx) response now reports `true`, and failures reach the callback as `(null, error)`.

### 🐛 Fixed: Calls Without a Callback

`initializeCustomer` and `sendEvent` accept a `null` callback, but calling them without one threw `Null check operator used on a null value` on success and before `init`. They now run normally and skip the callback.

### Who should upgrade

Any app that calls `setLanguage(lang)` after passing a `preferredLanguage` to `initializeCustomer`, presents the widget in a language outside the SDK's built-in left-to-right list, or relies on the `initializeCustomer` or `sendEvent` callbacks to report results and failures.

---

## 🔄 Changes

- Fixed the widget close button following the host app's text direction for languages outside the built-in left-to-right list
- Fixed `setLanguage(lang)` being outranked by a preferred language set through `initializeCustomer`
- `setLanguage(lang)` now mirrors the preferred language onto the customer's Gameball profile
- Language codes are now matched against the supported languages; any other code falls back to `en`
- `initializeCustomer` now passes request failures to its callback
- `sendEvent` now reports any accepted (2xx) response as `true` and passes request failures to its callback
- `initializeCustomer` and `sendEvent` no longer throw when called without a callback
- Fixed widget URL values with `+`, `&`, `#` or spaces reaching the widget altered
- `initializeCustomer` now always sends `guest: false`; `InitializeCustomerRequestBuilder().isGuest(...)` is ignored
- Internal diagnostic logging now only records widget usage
- Removed the undocumented `isLtr` helper from `utils/language_utils.dart`

---

## Requirements

- Flutter 1.17.0+
- Dart 3.4.4+
- Android API 21+
- iOS 12.0+

---

## Migration

No code changes required — all v3.x code works without modification. Behavior changes to check: failed `initializeCustomer` and `sendEvent` requests now reach the callback as `(null, error)`, so a callback that assumes it only runs on success should check `error` before using the result; `sendEvent` now reports `true` for any accepted (2xx) response; `isGuest(...)` is now ignored, so apps that passed `isGuest(true)` now initialize registered customers; `setLanguage(lang)` now also updates the preferred language on the Gameball profile of the most recently initialized customer; and unsupported language codes now fall back to `en`.

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
