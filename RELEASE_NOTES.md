# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.2.1

**Release Date**: 2026-08-06
**Version**: 3.2.1
**Type**: Patch Release

---

## 🎉 What's New

v3.2.1 is a bug-fix release that corrects how the `shop` value is sent to the Gameball widget. There are no API changes — upgrading from any 3.x version requires no code changes.

### 🐛 Fixed: Widget Shop Parameter

When `GameballConfigBuilder` was configured with both `.platform(...)` and `.shop(...)`, the SDK appended the shop value to the widget URL as a **second `platform` key**:

```
...&platform=<platform>&platform=<shop>&...
```

The widget parses duplicate query keys into an array, and its coupon-redemption flow calls `platform.toLowerCase()` — which throws a `TypeError` on an array. The visible symptom: tapping redeem showed an infinite loading spinner and no request ever reached the backend.

The SDK now sends the value under its own key:

```
...&platform=<platform>&shop=<shop>&...
```

### Who should upgrade

Any app that sets both `platform` and `shop` in `GameballConfigBuilder` — widget coupon redemption is broken for that configuration in all prior releases.

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
  gameball_sdk: ^3.2.1
```

---

## Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-flutter/issues

---

## Previous Release: v3.2.0

**Release Date**: 2026-07-01
**Type**: Minor Release

Widget event channel (`widgetEventCallback` receiving events such as `gameCompleted`), widget dismissal controls (`GameballApp.hideProfile()` and web-initiated `window.GameballWidget.closeWidget()`), external-link handling with optional `externalLinkCallback`, optional `mobile`/`email` channel-merging parameters, diagnostic logging, and widened dependency ranges. See [CHANGELOG.md](CHANGELOG.md) for the full history.
