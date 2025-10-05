# Release Notes - Gameball Flutter SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.1.0

**Release Date**: 2025-10-14
**Version**: 3.1.0
**Type**: Feature Release

---

## 🎉 What's New

Gameball Flutter SDK v3.1.0 introduces **Session Token authentication** for enhanced API security. This feature release adds optional token-based authentication with automatic secure endpoint routing, providing an additional layer of security for your API communications.

### 🔒 Security Enhancements

- **Session Token Authentication**: Optional token-based authentication mechanism for secure API communication
- **Automatic Secure Routing**: SDK automatically switches from API v4.0 to v4.1 endpoints when Session Token is provided
- **Secure Header Transmission**: `X-GB-TOKEN` header added to requests when using Session Token authentication
- **Backward Compatible**: Existing implementations continue to work without any changes

### 🛠️ Developer Experience

- **Simple Configuration**: Add `sessionToken` to your `GameballConfig` to enable secure authentication
- **Transparent Security**: No code changes required beyond initial configuration
- **Flexible Authentication**: Token authentication is optional and can be enabled per configuration
- **Per-Request Override**: All SDK methods now support optional `sessionToken` parameter for fine-grained control

### 🐛 Bug Fixes

- **Enum Naming**: Updated `PushProvider` enum to follow Dart lowerCamelCase convention (`firebase`, `huawei`)

---

## 🚀 Key Features

### GB Token Authentication

Enable secure authentication by adding the `sessionToken` parameter to your SDK configuration:

```dart
import 'package:gameball_sdk/models/requests/gameball_config.dart';

final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .sessionToken("your-secure-session-token")  // Optional: Enable secure authentication
    .build();

gameballApp.init(config);
```

When a Session Token is provided:
- All API requests automatically route to secure v4.1 endpoints
- `X-GB-TOKEN` header is included in all authenticated requests
- Enhanced security for customer data and API communications

### Per-Request Session Token Override

All SDK methods now support an optional `sessionToken` parameter for maximum flexibility:

```dart
// Use global sessionToken from init()
await gameballApp.initializeCustomer(request, callback);

// Override with a specific token for this request
await gameballApp.initializeCustomer(request, callback, sessionToken: "user-specific-token");

// Nullify sessionToken for this request
await gameballApp.sendEvent(event, callback, sessionToken: null);

// Show profile with a different token
gameballApp.showProfile(context, request, sessionToken: "session-token");
```

**Behavior:**
- **If provided (non-null)**: Overrides and updates the global sessionToken for this and subsequent requests
- **If provided (null)**: Clears the global sessionToken for this and subsequent requests
- **If omitted entirely**: Uses the current global sessionToken from `init()` or last override

**Important Note:** The `sessionToken` parameter must be explicitly passed to **every method call** where you want to use a specific token. If you want consistent authentication across multiple calls, either set it globally via `init()` or pass it to each individual call.

### Standard Configuration (Without Token)

```dart
final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .platform("your_platform")
    .shop("your_shop")
    .build();

gameballApp.init(config);
```

---

## ⚠️ Breaking Changes

**None.** This is a backward-compatible feature release. All existing v3.0.0 implementations continue to work without modification.

---

## 📈 What's Changed

### Security Improvements
- **Enhanced API Security**: Session Token authentication adds an additional security layer for sensitive operations
- **Automatic Endpoint Management**: Smart routing to secure endpoints when authentication is enabled
- **Secure Token Storage**: GB tokens are securely managed via static variables

---

## 🔧 Technical Details

### Requirements
- **Minimum Flutter**: 1.17.0 (Recommended: 3.0+)
- **Dart**: 3.4.4+
- **Android**: API level 21+
- **iOS**: 12.0+

### New Configuration Option

#### GameballConfig

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sessionToken` | String | ❌ Optional | Session Token for secure authentication |

### Internal Changes
- Added `getIntegrationsUrl()` function for conditional endpoint routing
- HeaderGenerator now conditionally adds `X-GB-TOKEN` header when token is present
- Automatic API version switching logic (v4.0 → v4.1) in request handlers
- API version constants added for version management

---

## 🛡️ Security & Reliability

### Authentication Security
- **Optional Session Token**: Adds token-based authentication layer when needed
- **Automatic Secure Routing**: Transparent upgrade to secure v4.1 endpoints
- **Header Security**: Secure transmission of authentication tokens via HTTP headers
- **Token Management**: Secure storage and lifecycle management of GB tokens

---

## 📚 Upgrading from v3.0.0

### No Migration Required

This is a backward-compatible release. Your existing v3.0.0 code will continue to work without any changes.

### To Enable GB Token Authentication (Optional)

Simply add the `sessionToken` parameter to your existing configuration:

```dart
// Before (v3.0.0) - Still works in v3.1.0
final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .build();

// After (v3.1.0) - With optional GB Token
final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .sessionToken("your-secure-session-token")  // Add this line
    .build();
```

### Support
- 📧 **Email**: support@gameball.co
- 📖 **Documentation**: [https://developer.gameball.co/](https://developer.gameball.co/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/gameballers/gameball-flutter/issues)

---

## 🎯 What's Next

### Future Enhancements
- Enhanced analytics capabilities
- Additional security features
- Performance optimizations
- New integration features

### Roadmap
- Version 3.2.0: Enhanced analytics and reporting
- Future versions: Continued improvements and new features

---

## 📦 Installation

### pubspec.yaml
```yaml
dependencies:
  gameball_sdk: ^3.1.0
```

### Flutter CLI
```bash
flutter pub add gameball_sdk
```

---

## 🏆 Benefits Summary

✅ **Enhanced Security**: Optional Session Token authentication for sensitive operations
✅ **Backward Compatible**: Zero migration effort - existing code continues to work
✅ **Automatic Routing**: Smart endpoint selection based on authentication status
✅ **Simple Configuration**: One-line addition to enable secure authentication
✅ **Flexible**: Use token authentication only when needed
✅ **Transparent**: No code changes beyond initial configuration

---

## ⭐ Acknowledgments

We thank our development community for their feedback on security features.

---

**Ready to upgrade?** Simply update your dependency to v3.1.0. No migration required!

*For technical support, contact us at support@gameball.co*