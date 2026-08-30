# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.2.2

**Release Date**: 2026-08-30
**Version**: 3.2.2
**Type**: Patch Release

---

## 🎉 What's New

v3.2.2 is a bug-fix release that corrects widget links opening in the device browser instead of in-app. There are no API changes — upgrading from any 3.x version requires no code changes.

### 🐛 Fixed: Widget Opening in Browser

The navigation handler treated **every** intercepted link as external and always prevented in-widget navigation. As a result the widget — including its own initial load and normal same-host navigation — opened in the device browser instead of rendering in-app. The visible symptom: opening the widget bounced the user out to their browser.

A link is now treated as external only when it either:

1. carries `gbExternalBrowser=true` (the flag still outranks any callback), or
2. points to a **different host** than the loaded widget (a genuinely off-widget destination).

Same-host links (including the widget's initial load) and hostless URLs (`about:blank`, `data:`, `mailto:`) now load in-widget as intended. When a link is external and an `externalLinkCallback` is set, the host still receives it; otherwise the SDK opens it in the device browser as before.

### Who should upgrade

Any app displaying the Gameball profile widget — the widget opened in the device browser instead of in-app in all prior 3.2.x releases.

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
  gameball_sdk: ^3.2.2
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
