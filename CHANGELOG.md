# 📋 Changelog

All notable changes to the Gameball Flutter SDK are documented here.

---

## [3.2.2] - 2026-08-30 🔧

> **Patch Release**: Widget external-link fix

### 🐛 Fixed
- 🔗 **Widget Opening in Browser**: the navigation handler treated every intercepted link as external and always prevented in-widget navigation, so the widget — including its own initial load and normal same-host navigation — opened in the device browser instead of in-app. A link is now treated as external only when it carries `gbExternalBrowser=true` or points to a different host than the loaded widget; same-host and hostless URLs (`about:blank`, `data:`, `mailto:`) load in-widget as before.

---

## [3.2.1] - 2026-08-06 🔧

> **Patch Release**: Widget URL shop-parameter fix

### 🐛 Fixed
- 🎫 **Widget Shop Parameter**: the `shop` value was appended to the widget URL as a second `platform` key, so apps setting both `platform` and `shop` made the widget receive `platform` as an array — coupon redemption then failed with a `TypeError` (`toLowerCase is not a function`), showing an infinite loading spinner and never sending the request. The value is now sent under its own `&shop=` key.

---

## [3.2.0] - 2026-07-01 📱

> **Minor Release**: Widget event channel, widget dismissal controls, external-link handling, diagnostic logging, and channel-merging parameters

### ✨ Added
- 🏗️ **Widget Event Channel**: `ShowProfileRequestBuilder().widgetEventCallback(...)` receives events posted from the widget (e.g. game completion) as a `Map<String, dynamic>` `{type, metadata}`; the `gameCompleted` payload carries `hasWon`, `rewardType`, `discountType`, `rewardName`, `campaignId`, `campaignType`
- 🏗️ **Web-Initiated Close**: the widget can dismiss its own webview via `window.GameballWidget.closeWidget()`
- 🏗️ **Host-Initiated Dismiss**: new `GameballApp.hideProfile()` dismisses the widget programmatically (no-op when nothing is shown)
- ⚙️ **External-Link Handling**: links flagged `gbExternalBrowser=true` open in the system browser; optional `externalLinkCallback` lets the host intercept them
- 📊 **Diagnostic Logging**: added internal diagnostic logging to aid SDK troubleshooting
- 📇 **Channel-Merging Parameters**: `ShowProfileRequestBuilder` now accepts optional `mobile` and `email` to support customer channel merging

### 🔄 Changed
- 🔧 **User-Agent Header**: unified the `x-gb-agent` header format to `GB/flutter/<version>`
- 📦 **Dependency Constraints**: widened `share_plus` (`<=13.2.0`), `device_info_plus` (`<14.0.0`), and `package_info_plus` (`<11.0.0`) ranges — floors unchanged, so existing apps resolve the same versions; apps that opt into `share_plus` 13.x require Flutter 3.38.1+ / Dart 3.10+

---

## [3.1.1] - 2025-12-15 🔧

> **Patch Release**: Guest mode support for profile widget

### 🐛 Fixed
- 🎁 **Guest Mode Support**: Profile widget can now be displayed without customer authentication
- 🔓 **Optional Customer ID**: `ShowProfileRequest.customerId` is now optional, defaulting to `null` for guest mode

### 🔄 Changed
- 🏗️ **ShowProfileRequest Builder**: No longer requires customer ID - supports guest mode scenarios
- 📝 **Widget URL Construction**: Enhanced to support both authenticated and guest modes

### 🛠️ Developer Experience
- ⚡ **Simpler API**: Build `ShowProfileRequest` without customer ID for guest mode
- 🎯 **Flexible Usage**: Support for preview/showcase scenarios before user registration
- 📖 **Better Documentation**: Clear examples for both guest and authenticated modes

---

## [3.1.0] - 2025-10-14 🔒

> **Security Release**: Token-based authentication for enhanced API security

### 🔒 Security
- 🛡️ Added Session Token authentication mechanism for secure API communication
- 🔐 Optional `sessionToken` parameter in `GameballConfig` for token-based authentication
- 🔄 Automatic secure endpoint routing (API v4.0 → v4.1) when Session Token is provided
- 📡 `X-GB-TOKEN` header added to requests when using Session Token authentication
- ⚡ **Per-Request Session Token Override**: All SDK methods (`initializeCustomer`, `sendEvent`, `showProfile`) now accept an optional `sessionToken` parameter to override or nullify the global session token on a per-request basis

### 🔧 Internal Changes
- 🔧 Added `getIntegrationsUrl()` function for conditional endpoint routing
- 📊 Added API version constants for version management

### 📝 API Changes
- `initializeCustomer(request, callback, {sessionToken})` - Added optional sessionToken parameter
- `sendEvent(event, callback, {sessionToken})` - Added optional sessionToken parameter
- `showProfile(context, request, {sessionToken})` - Added optional sessionToken parameter

### 🐛 Fixed
- 🔧 Updated `PushProvider` enum to follow Dart lowerCamelCase convention (`firebase`, `huawei`)

---

## [3.0.0] - 2025-09-27 🎉

**Big changes are here!** 🚀 We've completely redesigned the SDK architecture with modern Flutter patterns, builder APIs, and enhanced type safety. This major release brings significant improvements to developer experience while maintaining all the features you love.

### ✨ What's New
- 🏗️ **Builder Pattern Architecture** - All request models now use intuitive builder patterns with compile-time validation
- 🛡️ **Enhanced API Validation** - Better error messages and validation across all SDK methods
- ⚙️ **Smart Defaults** - Automatic default values for channel ("mobile"), guest status (false), and platform detection
- 🔧 **Flexible Customer Attributes** - New `additionalAttributes` support for custom field handling
- 💡 **Better IDE Support** - Improved auto-completion and IntelliSense with builder patterns

### 🔄 What's Changed
- 💥 **BREAKING**: Complete architecture makeover using builder patterns for all requests
- 💥 **BREAKING**: Immutable request models with `InitializeCustomerRequestBuilder`, `EventBuilder`, `CustomerAttributesBuilder`
- 💥 **BREAKING**: Updated method signatures to use new builder-based request objects
- 🚀 **Performance Boost** - Removed 11 redundant static variables for cleaner, faster code
- 🔧 **Streamlined Flow** - Simplified customer initialization by merging redundant processes
- 📦 **Cleaner JSON** - Automatic null value removal for optimized API requests
- 🎯 **Better Error Handling** - Enhanced callback mechanisms throughout the SDK

### 🗑️ What's Removed
- 💥 **BREAKING**: Legacy static variable management (replaced with parameter-based data flow)

---

## [2.2.3] - 2025-07-09 🔗

**Better navigation everywhere!** We've improved how external URLs are handled across both iOS and Android platforms.

### 🔧 What's Fixed
- 🌐 **External URL Navigation** - External URLs now properly open outside the Gameball Widget WebView on both iOS and Android

---

## [2.2.2] - 2025-07-02 📱

**Sharing just got better!** Fixed some sharing quirks and improved navigation handling.

### 🔧 What's Fixed
- 📲 **Native Sharing** - Fixed native sharing to include the actual referral link, not just the text
- 🔗 **WebView Navigation** - Better handling of external URL navigation from within the widget

---

## [2.2.1] - 2025-07-01 🤖

**Android users, this one's for you!** Enhanced sharing capabilities with native dialog support.

### ✨ What's New
- 📱 **Native Android Sharing** - Added JavaScript injection to trigger native sharing dialog on Android

---

## [2.2.0] - 2025-03-30 🔗

**Referrals made easy!** Firebase Dynamic Links are going away, but we've got you covered with better referral handling.

### ✨ What's New
- 🎯 **Referral Codes** - New `referralCode` parameter for seamless platform integration

### 🔄 What's Changed
- 🔗 **Dynamic Links Independence** - Firebase Dynamic Links removed from customer registration for flexible usage

### 🗑️ What's Removed
- 📱 **Firebase Dynamic Links** - Deprecated functionality removed (use referralCode instead)

---

## [2.1.0] - 2025-03-07 📢

**Huawei users rejoice!** 🎉 You can now receive push notifications through Gameball using Huawei Push Kit!

### ✨ What's New
- 🔔 **Huawei Push Support** - Full integration with Huawei Push Kit for push notifications
- 🔧 **Flexible Push Setup** - Separated Firebase token handling for more control
- 🎛️ **Push Provider Methods** - New `initializeFirebase()` and `initializeHuawei()` methods

---

## [2.0.1] - 2025-02-19 🎨

**Small but important!** Better visibility for the profile widget close button.

### 🔧 What's Fixed
- 🎨 **Close Button Visibility** - Darker close button color to prevent blending with backgrounds

---

## [2.0.0] - 2024-12-11 🎉

**Welcome to the future!** 🚀 Exit Player, Enter Customer! The SDK now runs on Integrations APIs V4 with major improvements.

### ✨ What's New
- 🎯 **Customer-Centric API** - Complete transition from "Player" to "Customer" terminology
- 📱 **Better WebView** - Improved scrolling and interaction in the customer profile widget
- 🔧 **Backwards Compatibility** - Support for older Dart and Flutter versions
- 📦 **Updated Dependencies** - Latest Firebase versions for better performance

### 🔄 What's Changed
- 💥 **BREAKING**: Now runs on Integrations APIs V4 - more powerful and flexible!
- 🎨 **Enhanced Profile Widget** - Smoother scrolling and better user experience

---

## [1.0.3] - 2024-10-22 🎛️

**More control for you!** Show or hide the profile widget close button as needed.

### ✨ What's New
- 🎛️ **Close Button Control** - Option to show/hide the widget close button

---

## [1.0.2] - 2024-10-15 🔧

**Under the hood improvements!** Better URL building and request handling.

### 🔧 What's Fixed
- 🔗 **Widget URL Building** - Fixed issues with widget URL construction
- 📡 **HTTP Headers** - Improved request header handling

---

## [1.0.1] - 2024-10-10 🌍

**Global-ready!** Better language support and cleaner code.

### ✨ What's New
- 🌍 **RTL/LTR Support** - Close button now properly supports right-to-left languages

### 🔄 What's Changed
- 🧹 **Code Cleanup** - Removed unused imports and unnecessary code
- 🌐 **Better Language Handling** - Improved global vs preferred language logic
- 📡 **Enhanced Requests** - Language parameter included in all API requests
- 🔗 **Widget URL Refactor** - Cleaner widget URL construction

---

## [1.0.0] - 2024-10-01 🎉

**Welcome to Gameball Flutter SDK!** 🎉 The first release brings all the essential features you need.

### ✨ What's New
- 👥 **Customer Registration** - Register and manage customer profiles
- 🔗 **Referral System** - Built-in referral tracking and management
- 📊 **Event Tracking** - Track user actions and behaviors
- 🎨 **Profile Widget** - Beautiful customer profile display widget

*Ready to engage your customers like never before!* 🚀
