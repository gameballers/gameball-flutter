# 📋 Changelog

All notable changes to the Gameball Flutter SDK are documented here.

---

## [4.0.0] - 2026-10-22 🎉

> **Major Release**: Raised minimum platform versions to iOS 15.0 and Android API 24, and added in-app messaging — an opt-in module that displays campaigns authored in the Gameball dashboard inside your app

### ✨ Added
- 🏗️ **In-App Messaging**: Added `startInAppMessaging(customerId:, navigatorKey:)` to opt in and `stopInAppMessaging()` to stop and clear state on logout. Nothing runs until `startInAppMessaging` is called — no requests, no timers, no overlay and no stored state — so upgrading without calling it changes nothing
- 🎁 **Three Message Types**: Added modal (a centred card over a dimmed background, up to two buttons), slideup (a non-blocking banner at the top or bottom edge, dismissed by swiping toward its edge) and fullscreen (edge to edge, image over copy or artwork only) messages, chosen per campaign in the dashboard
- 🎁 **Triggers**: Added session-start triggers, fired on launch and when the app returns to the foreground after the session timeout (30 seconds by default), and custom-event triggers matched on the event name and optionally filtered on its metadata
- 🎁 **Purchase Logging**: Added `logPurchase(customerId:, productId:, price:, currency:, ...)`, which sends a `purchase` event to Gameball whose `productId`, `price`, `currency` and `quantity` are available to campaign filters
- 🎁 **Display Rules**: Added per-campaign frequency caps that persist across restarts, a backend-controlled minimum interval between any two displays, campaign expiry, priority ordering and quiet hours. A message that can't be shown yet — because the Gameball widget or another message is open — waits for the next opportunity instead of being lost
- 🔧 **Host Hooks**: Added `beforeDisplay` to show, postpone or discard a message, `onAction` to handle a tap yourself, `onNavigate` to route through go_router or any other Navigator 2.0 router, and the `onInAppMessage` stream of every message the SDK selects
- 🏗️ **Message Analytics**: Added automatic impression, click and dismissal reporting. Events are batched and kept on the device until delivered, so events logged just before the app is closed are sent on the next launch
- 🎁 **Personalisation**: Added `{token}` placeholders in campaign text, filled with the customer's current values fetched just before a message is shown. The fetch waits at most two seconds; if the values don't arrive, the placeholders are removed and the message still shows
- 🏗️ **Offline Campaigns**: Added a per-customer campaign cache, so a failed sync falls back to the last unexpired campaigns
- ⚙️ **Diagnostic Logging Switch**: Added `gameballInAppMessagingLogging` to control in-app messaging console logs; it defaults to on in debug builds and off in release builds

### 🔄 Changed
- 💥 **BREAKING**: **Minimum iOS Version**: Raised the minimum supported iOS version from 12.0 to 15.0
- 💥 **BREAKING**: **Minimum Android Version**: Raised the minimum supported Android version from API 21 (Android 5.0) to API 24 (Android 7.0)
- 🔧 **Published Package**: The package published to pub.dev now contains only the SDK sources; tests, the example app and internal docs are excluded

---

## [3.3.1] - 2026-10-19 🔧

> **Patch Release**: Widget close button direction, runtime language switching, supported language fallback, widget URL encoding and callback fixes

### 🐛 Fixed
- 🔧 **Widget Close Button Direction**: the close button is now positioned from the widget's own language alone — left for Arabic, right for every other language. Codes missing from the SDK's old left-to-right list (e.g. `"tr"`) previously got no explicit side, so the button followed the host app's text direction and could land on the wrong side
- 🌐 **Runtime Language Switching**: `setLanguage(lang)` is no longer outranked by a preferred language passed to an earlier `initializeCustomer` — it now takes effect for `showProfile` presentations that don't pass their own `lang` and for subsequent `initializeCustomer`/`sendEvent` requests
- ⚠️ **Customer Initialization Errors**: `initializeCustomer` now reports a failed request to its callback as `(null, error)`; previously the failure never reached the callback and surfaced as an unhandled async error
- 🌐 **Unsupported Language Codes**: any two-character code used to be accepted, so one that isn't a real language code (e.g. `"عر"`) could make SDK requests fail until the language was changed again or the app restarted
- 🔗 **Widget URL Encoding**: the customer ID, session token, `openDetail`, platform, shop and API key are now encoded in the widget URL — they were added as-is, so a `+` arrived as a space, an `&` split the value into an extra parameter, and a `#` cut off every parameter after it
- 📨 **Event Callback**: `sendEvent` now reports any accepted (2xx) response as `true` — it reported `false` unless the status was exactly 200, so events accepted with `202` looked failed — and passes failed requests to its callback as `(null, error)` instead of surfacing them as unhandled async errors
- 🧩 **Calls Without a Callback**: `initializeCustomer` and `sendEvent` no longer throw `Null check operator used on a null value` when called without a callback; the call goes through and its result simply isn't reported

### 🔄 Changed
- 🌐 **Preferred Language Sync**: `setLanguage(lang)` now also mirrors the new language onto the customer's Gameball profile, so server-driven communications follow it too; the update goes to the most recently initialized customer (remembered across app launches) and is skipped until one has been initialized
- 🌐 **Supported Languages**: language codes from `init`, `setLanguage`, `initializeCustomer` and a per-call `lang` are now matched case-insensitively against the supported languages (`en`, `ar`, `fr`, `es`, `de`, `pt`, `pl`, `it`, `hu`, `zh-tw`, `nl`, `sv`, `no`, `dk`, `ja`); any other code falls back to `en`; regional variants (e.g. `ar-EG`) and three-letter codes (e.g. `ara`) aren't mapped, and `initializeCustomer` still sends `preferredLanguage` to Gameball as passed
- 👤 **Registered Customers Only**: the SDK now always initializes customers as registered — `initializeCustomer` sends `guest` as `false`, and `InitializeCustomerRequestBuilder().isGuest(...)` is ignored
- 📊 **Diagnostic Logging**: internal diagnostic logging now only records widget usage

### 🗑️ Removed
- 🧹 **Internal Direction Helper**: removed the undocumented `isLtr` helper from `utils/language_utils.dart`, which only served the old close-button placement

---

## [3.3.0] - 2026-09-02 📱

> **Minor Release**: Per-call and global language control, and push notification click tracking

### ✨ Added
- 🌐 **Per-Call Widget Language**: `ShowProfileRequestBuilder` now accepts an optional `lang` (2-letter code, e.g. `"en"`, `"ar"`) to present that one widget in a specific language; when omitted, the SDK's existing language resolution applies (customer preferred language, then global preferred language, then `"en"`)
- 🌐 **Global Language Switch**: new `GameballApp.setLanguage(lang)` changes the SDK's global language on demand without re-calling `init` — affects future `showProfile` presentations that don't pass their own `lang` and `initializeCustomer`/`sendEvent` requests
- 📣 **Push Click Tracking**: new `GameballApp.handlePushClick(payload, {callback, sessionToken})` — call it from your notification-tap handler with the notification's data payload (e.g. `RemoteMessage.data`); returns `true` when the notification is a Gameball one and reports the campaign click to Gameball when a click token is present

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
