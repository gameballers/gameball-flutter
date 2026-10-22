# Gameball Flutter SDK

[![Version](https://img.shields.io/badge/version-4.0.0-blue.svg)](https://github.com/gameballers/gameball-flutter)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-1.17%2B-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.4.4%2B-blue.svg)](https://dart.dev)

Gameball Flutter SDK allows you to integrate customer engagement and loyalty features into your Flutter applications with modern builder patterns and immutable request models.

## Features

- 🎯 **Customer Management** - Initialize and manage customer profiles with builder pattern
- 📊 **Event Tracking** - Track user actions and behaviors with flexible metadata
- 🎁 **Profile Widget** - Display customer loyalty information in customizable UI
- 💬 **In-App Messaging** - Show dashboard-authored campaigns in your app, opt-in and additive
- 🔧 **Modern Architecture** - Built with Flutter best practices and null safety
- 🛡️ **Type Safety** - Compile-time validation with Dart's type system
- ⚡ **Async/Await Ready** - Modern async architecture with proper error handling

## Requirements

- **Minimum Flutter Version**: 1.17.0
- **Dart**: 3.4.4+
- **Android**: API level 24+ (Android 7.0)
- **iOS**: 15.0+

> **Note**: Set your app's `minSdkVersion` to 24 or higher and its iOS deployment target
> (`IPHONEOS_DEPLOYMENT_TARGET` and the Podfile `platform :ios`) to 15.0 or higher. As of v4.0.0,
> earlier versions aren't supported.

> **Note**: The `environment` constraint in `pubspec.yaml` permits older Flutter and Dart versions,
> and `pub` will resolve older dependency versions to satisfy them. A current resolution needs
> Flutter 3.44+ / Dart 3.12+, so that is what to expect on a fresh `pub get`.

## Installation

### pubspec.yaml
```yaml
dependencies:
  gameball_sdk: ^4.0.0
```

### Flutter CLI
```bash
flutter pub add gameball_sdk
```

## Quick Start

### 1. Initialize the SDK
```dart
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';

final gameballApp = GameballApp.getInstance();

final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .platform("your_platform")
    .shop("your_shop")
    .build();

gameballApp.init(config);
```

### 2. Initialize Customer
```dart
import 'package:gameball_sdk/models/requests/initialize_customer_request.dart';
import 'package:gameball_sdk/models/requests/customer_attributes.dart';

final request = InitializeCustomerRequestBuilder()
    .customerId("unique_customer_id")
    .email("customer@example.com")
    .mobile("1234567890")
    .customerAttributes(
        CustomerAttributesBuilder()
            .displayName("John Doe")
            .firstName("John")
            .lastName("Doe")
            .addCustomAttribute("city", "New York")
            .build()
    )
    .build();

await gameballApp.initializeCustomer(request, (response, error) {
    if (error == null) {
        print('Customer initialized successfully');
    } else {
        print('Error: ${error.toString()}');
    }
});
```

### 3. Track Events
```dart
import 'package:gameball_sdk/models/requests/event.dart';

final event = EventBuilder()
    .customerId("unique_customer_id")
    .eventName("purchase")
    .eventMetaData("amount", "100.00")
    .eventMetaData("currency", "USD")
    .build();

gameballApp.sendEvent(event, (success, error) {
    if (success == true) {
        print('Event sent successfully');
    } else {
        print('Error sending event: ${error?.toString()}');
    }
});
```

### 4. Show Profile Widget

```dart
import 'package:gameball_sdk/models/requests/show_profile_request.dart';

// Authenticated mode
final profileRequest = ShowProfileRequestBuilder()
    .customerId("unique_customer_id")
    .showCloseButton(true)
    .closeButtonColor("#FF0000")
    .build();

gameballApp.showProfile(context, profileRequest);
```

#### Guest Mode (v3.1.1+)

Display the profile widget without customer authentication:

```dart
// Guest mode - no customer ID required
final guestRequest = ShowProfileRequestBuilder()
    .showCloseButton(true)
    .closeButtonColor("#4CAF50")
    .build();

gameballApp.showProfile(context, guestRequest);
```

### Widget Events & Dismissal (v3.2.0+)

Pass `widgetEventCallback` to react to events the widget posts (e.g. game completion). Each event is a `Map<String, dynamic>` with a top-level `type` and a nested `metadata`; on a parse failure the callback is invoked with `(null, exception)`:

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
        final campaignId = metadata?['campaignId'] as String?;     // e.g. "90340"
        final campaignType = metadata?['campaignType'] as String?; // "spinTheWheel", "scratchCard"…
        if (hasWon) { /* refresh balance, show win UI… */ }
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

Dismiss the widget programmatically from your app (no-op when nothing is shown):

```dart
GameballApp.getInstance().hideProfile();
```

The widget can also dismiss itself by calling `window.GameballWidget.closeWidget()`.

### Channel Merging & Diagnostic Logging (v3.2.0+)

`ShowProfileRequestBuilder` also accepts optional `mobile` and `email` for channel merging:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .mobile("+201234567890")
    .email("customer@example.com")
    .build();

GameballApp.getInstance().showProfile(context, request);
```

You can also intercept links the widget flags with `gbExternalBrowser=true` instead of letting the SDK open them in the system browser:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .externalLinkCallback((url) {
      // open `url` your own way — in-app browser, router, etc.
    })
    .build();
```

The SDK also records internal diagnostic logs automatically to aid troubleshooting. This requires no integration changes.

### Language Control (v3.3.0+)

Present a single widget in a specific language with `ShowProfileRequestBuilder().lang(...)` (a supported language code, e.g. `"en"`, `"ar"`):

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .lang("ar")
    .build();

GameballApp.getInstance().showProfile(context, request);
```

When `lang` is omitted, the SDK's existing resolution applies: customer preferred language, then global preferred language, then `"en"`.

Or switch the SDK's global language on demand — no re-`init` needed:

```dart
GameballApp.getInstance().setLanguage("ar");
```

This changes the fallback used by future `showProfile` presentations (a per-call `lang` still wins) and `initializeCustomer`/`sendEvent` requests.

As of v3.3.1 it also becomes the customer's preferred language, taking precedence over one set earlier through `initializeCustomer`, and is mirrored onto the customer's Gameball profile so server-driven communications follow it too. The profile update goes to the most recently initialized customer (remembered across app launches) and is skipped until one has been initialized — to set the language before that, pass it as `preferredLanguage` to `initializeCustomer`.

**Supported languages:** `en`, `ar`, `fr`, `es`, `de`, `pt`, `pl`, `it`, `hu`, `zh-tw`, `nl`, `sv`, `no`, `dk`, `ja`, matched case-insensitively. As of v3.3.1, any other code passed to `init`, `setLanguage`, `initializeCustomer` or `ShowProfileRequestBuilder().lang(...)` falls back to `en` (earlier versions ignored codes that weren't 2 characters long). Codes must match one of these exactly (letter case doesn't matter): regional variants such as `ar-EG` and three-letter codes such as `ara` aren't mapped and fall back to `en`. `initializeCustomer` still sends `preferredLanguage` to Gameball exactly as passed; only the language the SDK itself uses falls back to `en`.

### Push Click Tracking (v3.3.0+)

Report taps on Gameball push notifications so campaign clicks are counted. Call `handlePushClick` from your notification-tap handler with the notification's data payload (e.g. `RemoteMessage.data` from `onMessageOpenedApp` / `getInitialMessage`):

> **Call this from wherever your app handles the notification tap — not on receive/delivery.** If you call it as soon as the notification arrives, you'll count every delivery as a click; call it from the tap handler so it only counts when the user actually opens it.

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

It returns `true` when the notification is a Gameball one; the tap is reported to Gameball when the payload carries a click token. An optional `sessionToken` parameter overrides the global session token for this request.

## In-App Messaging (v4.0.0+)

Displays campaigns you author in the Gameball dashboard — modals, slideup banners and fullscreen posters — inside your app.

It is **opt-in and additive**. Until you call `startInAppMessaging`, the module makes no requests, starts no timers, draws nothing and stores nothing, so upgrading without calling it changes nothing about how your app behaves.

> In-app messaging needs the `integrations/inapp-messages` endpoints enabled for your account. Where they are not, the SDK records the 404 in its diagnostic log and stays silent.

### Opting in

The SDK draws above your routes, so it needs the same navigator key your app uses:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  home: const HomeScreen(),
);

GameballApp.getInstance().startInAppMessaging(
  customerId: "customer_123",
  navigatorKey: navigatorKey,
);
```

Call `stopInAppMessaging()` on logout. It dismisses anything on screen, sends pending telemetry and clears state.

### What triggers a message

**Session start** — on launch, and again when the app returns to the foreground after more than `sessionTimeout` (30 seconds by default).

**Custom events** — a campaign can target an event by name and filter on its metadata:

```dart
GameballApp.getInstance().sendEvent(
  EventBuilder()
      .customerId("customer_123")
      .eventName("add_to_cart")
      .eventMetaData("productId", "sku-001")
      .build(),
  (success, error) {},
);
```

A campaign on `add_to_cart` can require `productId` to equal `sku-001`, or `price` to be above a number, and so on. A purchase logged through `logPurchase` reaches campaigns as an event named `purchase` whose `productId`, `price`, `currency` and `quantity` are available to filters.

Whether a matching campaign actually appears also depends on its frequency cap, the minimum interval between any two displays, its expiry and its priority — all set in the dashboard.

### Controlling display

```dart
GameballApp.getInstance().startInAppMessaging(
  customerId: "customer_123",
  navigatorKey: navigatorKey,

  // Show it, hold it for the next opportunity, or drop it.
  beforeDisplay: (message) => isCheckingOut
      ? GameballDisplayDecision.later
      : GameballDisplayDecision.show,

  // Return true if you handled the tap; false lets the SDK act.
  // `button` is null when the message surface itself was tapped.
  onAction: (message, button, action) => false,

  // Needed for go_router and other Navigator 2.0 routers; without it the
  // SDK falls back to named routes.
  onNavigate: (String route, Map<String, Object>? arguments) {
    // route your own way
  },
);
```

`onInAppMessage` is a stream of every message the SDK selects, whatever happens to it afterwards:

```dart
GameballApp.getInstance().onInAppMessage.listen((message) {
  debugPrint("selected ${message.id}");
});
```

### Personalisation

Campaign text can contain `{token}` placeholders. Just before a message with placeholders is shown, the SDK fetches the customer's current values and fills them in, so a points balance is current at the moment it appears. The fetch waits at most two seconds and its result is cached for a minute. If the values don't arrive in time, the placeholders are removed rather than shown as raw `{braces}`, and the message still appears. Messages with no placeholders skip the fetch entirely.

> Requires `integrations/inapp-messages/variables` to be enabled for your account. Until then, placeholders are removed from the text.

### Analytics

Impressions, clicks and dismissals are reported automatically — no integration required. A button tap is reported as a click carrying that button's id. Events are batched and persisted to device storage, so telemetry logged just before the app is killed still arrives on the next launch.

## API Methods

The SDK provides the following public methods:
- `init(config)` - Initialize the SDK with GameballConfig
- `initializeCustomer(request, callback, {sessionToken})` - Register/initialize customer with builder pattern
- `sendEvent(event, callback, {sessionToken})` - Track events with Event builder
- `showProfile(context, request, {sessionToken})` - Show profile widget with ShowProfileRequest
- `hideProfile()` - Dismiss the currently shown profile widget (no-op when nothing is shown)
- `setLanguage(lang)` - Change the SDK's global language on demand without re-calling `init`
- `handlePushClick(payload, {callback, sessionToken})` - Report a tap on a Gameball push notification for click tracking
- `logPurchase(...)` - Report a purchase, which in-app messaging campaigns can target and filter on
- `startInAppMessaging(customerId:, navigatorKey:, ...)` - Opt in to in-app messaging
- `stopInAppMessaging()` - Stop it and clear state; call on logout
- `isInAppMessagingStarted` - Whether in-app messaging is currently running
- `onInAppMessage` - Stream of every in-app message the SDK selects

### Session Token Per-Request Override

All SDK methods (`initializeCustomer`, `sendEvent`, `showProfile`) support an optional `sessionToken` parameter that allows you to override or nullify the global sessionToken on a per-request basis:

**Behavior:**
- **If provided**: The provided sessionToken overrides the global sessionToken set in `init()` for that specific request
- **If not provided (null)**: Nullifies the global sessionToken for that specific request
- **If omitted entirely**: Uses the global sessionToken from `init()`

**Example:**
```dart
// Set global sessionToken via init
final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .sessionToken("global-token")
    .build();
gameballApp.init(config);

// Use global sessionToken (from init)
await gameballApp.initializeCustomer(request, callback);

// Override with a different sessionToken for this request only
await gameballApp.initializeCustomer(request, callback, sessionToken: "specific-token");

// Nullify sessionToken for this request only
await gameballApp.initializeCustomer(request, callback, sessionToken: null);

// The next request will use whatever sessionToken was last set
await gameballApp.sendEvent(event, callback); // Uses "specific-token" from previous override
```

**Important Notes:**
- Each method call updates the global `_sessionToken` value. Subsequent calls will use the most recently set value unless explicitly overridden again.
- The `sessionToken` parameter must be explicitly passed to **every method call** where you want to use a specific token. If you want to use the same custom token across multiple calls, you must pass it to each call individually or set it globally via `init()`.

## ⚠️ Migration from v3.x

**Version 4.0.0 is a major release** that adds in-app messaging. Every v3.x call keeps its signature and behaviour; the breaking change is the raised platform minimums — **iOS 15.0+** (was 12.0) and **Android API 24+** (was API 21). See the [Migration Guide](MIGRATION.md#migration-guide-v3x--v400) for details.

## ⚠️ Migration from v2.x

**Version 3.0.0 contains breaking changes**. See [Migration Guide](MIGRATION.md) for detailed upgrade instructions.

### Key Changes in v3.0.0:
- All request models now use builder pattern
- Immutable request objects with compile-time validation
- Enhanced API key validation
- Simplified architecture with cleaner data flow

## Configuration Options

### GameballConfig
Configuration object for initializing the Gameball SDK.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `apiKey` | String | ✅ | Your Gameball API key |
| `lang` | String | ✅ | Language code (e.g., "en", "ar") |
| `platform` | String | ❌ | Platform identifier |
| `shop` | String | ❌ | Shop identifier |
| `sessionToken` | String | ❌ | Session Token for secure authentication (enables automatic v4.1 endpoint routing) |
| `apiPrefix` | String | ❌ | Custom API prefix |

**Validation Rules:**
- `apiKey` cannot be null or empty
- `lang` cannot be null or empty

**Builder Methods:**
- `apiKey(String apiKey)` - Sets the API key
- `lang(String lang)` - Sets the language
- `platform(String platform)` - Sets the platform identifier
- `shop(String shop)` - Sets the shop identifier
- `sessionToken(String sessionToken)` - Sets Session Token for secure authentication
- `apiPrefix(String apiPrefix)` - Sets custom API prefix

**Example:**
```dart
import 'package:gameball_sdk/models/requests/gameball_config.dart';

final config = GameballConfigBuilder()
    .apiKey("your_api_key_here")
    .lang("en")
    .platform("mobile")
    .shop("your_shop")
    .build();
```

### InitializeCustomerRequest
Request object for initializing/registering customers with the Gameball platform.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Unique customer identifier |
| `deviceToken` | String | ❌ | Push notification token |
| `customerAttributes` | CustomerAttributes | ❌ | Additional customer data |
| `referralCode` | String | ❌ | Referral code for attribution |
| `email` | String | ❌ | Customer email address |
| `mobile` | String | ❌ | Customer mobile number |
| `isGuest` | bool | ❌ | Ignored as of v3.3.1 — customers are always initialized as registered |
| `pushProvider` | PushProvider | ❌ | Push notification provider (Firebase/Huawei) |

**Validation Rules:**
- `customerId` cannot be null or empty
- If `pushProvider` is set, `deviceToken` must also be provided
- If `deviceToken` is provided, `pushProvider` must be specified
- `email` must be valid email format if provided
- `mobile` must be valid phone number if provided

**Builder Methods:**
- `customerId(String customerId)` - Sets the unique customer identifier
- `deviceToken(String deviceToken)` - Sets the push notification token
- `customerAttributes(CustomerAttributes attributes)` - Sets customer attributes
- `referralCode(String referralCode)` - Sets referral code
- `email(String email)` - Sets customer email
- `mobile(String mobile)` - Sets customer mobile number
- `isGuest(bool isGuest)` - Ignored as of v3.3.1 — customers are always initialized as registered
- `pushProvider(PushProvider provider)` - Sets push provider (Firebase/Huawei)

**Example:**
```dart
import 'package:gameball_sdk/models/requests/initialize_customer_request.dart';
import 'package:gameball_sdk/models/enums/push_provider.dart';

final request = InitializeCustomerRequestBuilder()
    .customerId("customer_123")
    .email("john@example.com")
    .mobile("1234567890")
    .deviceToken("firebase_token")
    .pushProvider(PushProvider.Firebase)
    .referralCode("REF123")
    .customerAttributes(attributes)
    .build();
```

### CustomerAttributes
Additional customer information for enriching customer profiles and personalization.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `displayName` | String | ❌ | Customer display name |
| `firstName` | String | ❌ | Customer first name |
| `lastName` | String | ❌ | Customer last name |
| `email` | String | ❌ | Customer email |
| `gender` | String | ❌ | Customer gender |
| `mobile` | String | ❌ | Customer mobile number |
| `dateOfBirth` | String | ❌ | Date of birth (YYYY-MM-DD format) |
| `joinDate` | String | ❌ | Join date (YYYY-MM-DD format) |
| `preferredLanguage` | String | ❌ | Preferred language (supported language code) |
| `customAttributes` | Map<String, String> | ❌ | Custom key-value pairs |
| `additionalAttributes` | Map<String, String> | ❌ | Additional flexible attributes |
| `channel` | String | 🔒 | Channel identifier (automatically set to "mobile") |

**Validation Rules:**
- `preferredLanguage` should be a supported language code; the SDK uses `en` for any other code
- `email` must be valid email format if provided
- `dateOfBirth` and `joinDate` should be in YYYY-MM-DD format
- `channel` is automatically set to "mobile" and cannot be modified

**Builder Methods:**
- `displayName(String displayName)` - Sets display name
- `firstName(String firstName)` - Sets first name
- `lastName(String lastName)` - Sets last name
- `email(String email)` - Sets email address
- `gender(String gender)` - Sets gender
- `mobile(String mobile)` - Sets mobile number
- `dateOfBirth(String dateOfBirth)` - Sets date of birth
- `joinDate(String joinDate)` - Sets join date
- `preferredLanguage(String language)` - Sets preferred language
- `addCustomAttribute(String key, String value)` - Adds custom attribute
- `customAttributes(Map<String, String> attributes)` - Sets all custom attributes
- `addAdditionalAttribute(String key, String value)` - Adds additional attribute
- `additionalAttributes(Map<String, String> attributes)` - Sets all additional attributes

**Example:**
```dart
import 'package:gameball_sdk/models/requests/customer_attributes.dart';

final attributes = CustomerAttributesBuilder()
    .displayName("John Doe")
    .firstName("John")
    .lastName("Doe")
    .email("john@example.com")
    .mobile("1234567890")
    .gender("male")
    .dateOfBirth("1990-01-15")
    .preferredLanguage("en")
    .addCustomAttribute("tier", "premium")
    .addCustomAttribute("city", "New York")
    .addAdditionalAttribute("segment", "vip")
    .addAdditionalAttribute("source", "mobile_app")
    .build();
```

### Event
Event objects for tracking customer actions and behaviors for analytics and campaign triggers.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Customer identifier |
| `events` | Map<String, Map<String, Object>> | ✅ | Event data with metadata |
| `email` | String | ❌ | Customer email |
| `mobile` | String | ❌ | Customer mobile number |

**Validation Rules:**
- `customerId` cannot be null or empty
- At least one event must be specified
- Event names should be meaningful and descriptive
- Event metadata values can be String, Number, or Boolean

**Builder Methods:**
- `customerId(String customerId)` - Sets the customer identifier
- `email(String email)` - Sets customer email
- `mobile(String mobile)` - Sets customer mobile number
- `eventName(String eventName)` - Sets current event name (must be called before adding metadata)
- `eventMetaData(String key, Object value)` - Adds metadata to current event

**Example:**
```dart
import 'package:gameball_sdk/models/requests/event.dart';

final event = EventBuilder()
    .customerId("customer_123")
    .email("john@example.com")
    .mobile("1234567890")
    .eventName("purchase")
    .eventMetaData("amount", 99.99)
    .eventMetaData("currency", "USD")
    .eventMetaData("product_id", "prod_123")
    .eventMetaData("category", "electronics")
    .build();

// Multiple events example
final multipleEvents = EventBuilder()
    .customerId("customer_123")
    .eventName("page_view")
    .eventMetaData("page", "product_detail")
    .eventMetaData("product_id", "prod_123")
    .eventName("add_to_cart")
    .eventMetaData("product_id", "prod_123")
    .eventMetaData("quantity", 1)
    .build();
```

### ShowProfileRequest
Request object for displaying the Gameball customer profile widget with customization options.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Customer identifier |
| `openDetail` | String | ❌ | Specific detail to open in the profile |
| `hideNavigation` | bool | ❌ | Hide navigation elements |
| `showCloseButton` | bool | ❌ | Show close button (defaults to true) |
| `closeButtonColor` | String | ❌ | Close button color (hex format like "#FF0000") |
| `widgetUrlPrefix` | String | ❌ | Custom widget URL prefix |
| `mobile` | String | ❌ | Customer mobile number (for channel merging) |
| `email` | String | ❌ | Customer email address (for channel merging) |
| `lang` | String | ❌ | Supported language code for this presentation only (v3.3.0+) |
| `externalLinkCallback` | void Function(String) | ❌ | Handler for links tagged `gbExternalBrowser=true`. When provided, the link is delegated to it; otherwise the SDK opens it in the system browser |
| `widgetEventCallback` | void Function(Map<String, dynamic>?, Exception?) | ❌ | Receives events the widget posts (e.g. game completion) as a `{type, metadata}` map; called with `(null, exception)` on a parse failure |

**Validation Rules:**
- `customerId` cannot be null or empty
- `closeButtonColor` must be in hex format (#RRGGBB) if provided

**Builder Methods:**
- `customerId(String customerId)` - Sets the customer identifier
- `openDetail(String openDetail)` - Sets specific detail to open
- `hideNavigation(bool hideNavigation)` - Sets navigation visibility
- `showCloseButton(bool showCloseButton)` - Sets close button visibility
- `closeButtonColor(String closeButtonColor)` - Sets close button color
- `widgetUrlPrefix(String widgetUrlPrefix)` - Sets custom widget URL prefix
- `mobile(String mobile)` - Sets customer mobile number (channel merging)
- `email(String email)` - Sets customer email address (channel merging)
- `lang(String? lang)` - Sets a supported language code for this presentation only (v3.3.0+)
- `externalLinkCallback(void Function(String) callback)` - Sets handler for links tagged `gbExternalBrowser=true`
- `widgetEventCallback(void Function(Map<String, dynamic>?, Exception?) callback)` - Registers a listener for widget events

**Example:**
```dart
import 'package:gameball_sdk/models/requests/show_profile_request.dart';

final profileRequest = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .openDetail("rewards")
    .hideNavigation(false)
    .showCloseButton(true)
    .closeButtonColor("#FF6B6B")
    .widgetUrlPrefix("https://custom.example.com/widget")
    .build();

gameballApp.showProfile(context, profileRequest);
```

### startInAppMessaging
Opts in to in-app messaging for a customer (v4.0.0+).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Customer identifier the campaigns are fetched for |
| `navigatorKey` | GlobalKey<NavigatorState> | ✅ | The key assigned to your `MaterialApp.navigatorKey`; messages are drawn through it |
| `beforeDisplay` | GameballBeforeDisplay | ❌ | Called before each message; return `GameballDisplayDecision.show`, `.later` or `.discard`. Shows every message when omitted |
| `onAction` | GameballOnAction | ❌ | Called on a tap with `(message, button, action)`; return `true` if you handled it, `false` to let the SDK act. `button` is null when the message itself was tapped |
| `onNavigate` | GameballOnNavigate | ❌ | Called with `(route, arguments)` when a campaign navigates; needed for go_router and other Navigator 2.0 routers. Falls back to `Navigator.pushNamed` when omitted |
| `sessionTimeout` | Duration | ❌ | Time in the background after which returning starts a new session (defaults to 30 seconds). Applies when messaging first starts |

**Validation Rules:**
- Ignored, with a debug log, when `init()` hasn't been called
- Calling it again for the same `customerId` does nothing; a different `customerId` fetches that customer's campaigns

### logPurchase
Sends a `purchase` event that in-app messaging campaigns can target (v4.0.0+).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Customer who made the purchase |
| `productId` | String | ✅ | Identifier of the purchased item |
| `price` | double | ✅ | Unit price |
| `currency` | String | ✅ | ISO currency code, e.g. `"USD"` |
| `quantity` | int | ❌ | Number of units (defaults to 1) |
| `properties` | Map<String, Object> | ❌ | Extra metadata, also available to campaign filters |
| `callback` | SendEventCallback | ❌ | Receives the result, as with `sendEvent` |
| `sessionToken` | String | ❌ | Overrides the global session token for this request |

**Example:**
```dart
GameballApp.getInstance().logPurchase(
  customerId: "customer_123",
  productId: "sku-001",
  price: 49.99,
  currency: "USD",
  quantity: 2,
  callback: (success, error) {},
);
```

## Advanced Usage

### Customer Attributes with Builder
```dart
import 'package:gameball_sdk/models/requests/customer_attributes.dart';

final attributes = CustomerAttributesBuilder()
    .displayName("John Doe")
    .email("john@example.com")
    .mobile("1234567890")
    .preferredLanguage("en")
    .addCustomAttribute("tier", "premium")
    .addCustomAttribute("city", "New York")
    .addAdditionalAttribute("segment", "vip")
    .build();
```

### Push Notifications
```dart
import 'package:gameball_sdk/models/requests/initialize_customer_request.dart';
import 'package:gameball_sdk/models/enums/push_provider.dart';

// Firebase FCM
final request = InitializeCustomerRequestBuilder()
    .customerId("customer_id")
    .deviceToken("fcm_token")
    .pushProvider(PushProvider.Firebase)
    .build();

// Huawei Push Kit
final request = InitializeCustomerRequestBuilder()
    .customerId("customer_id")
    .deviceToken("hms_token")
    .pushProvider(PushProvider.Huawei)
    .build();
```

### Error Handling
```dart
try {
    await gameballApp.initializeCustomer(request, (response, error) {
        if (error != null) {
            // Handle API errors
            print('API Error: ${error.toString()}');
        } else {
            // Handle success
            print('Customer initialized: ${response?.toString()}');
        }
    });
} catch (e) {
    // Handle SDK exceptions
    print('SDK Exception: ${e.toString()}');
}
```

## Troubleshooting

### Common Issues

**1. API Key Not Initialized**
```
Error: API key is not initialized. Call init() first
```
**Solution**: Ensure you call `gameballApp.init(config)` before any other SDK methods.

**2. Invalid Customer ID**
```
Error: Customer ID cannot be empty
```
**Solution**: Provide a valid, non-empty customer ID in your requests.

**3. Push Provider Validation**
```
Error: Device token is required when push provider is set
```
**Solution**: When setting a push provider, ensure you also provide a valid device token.

### Debug Logging
Enable Flutter's debug logging to see detailed SDK operation logs:
```dart
flutter run --verbose
```

In-app messaging logs why a campaign was shown or skipped. These logs are on in debug builds and off in release builds; to turn them on in a release build while reproducing an issue:
```dart
gameballInAppMessagingLogging = true;
```

## Documentation

- 📋 **[Changelog](CHANGELOG.md)** - Version history and changes
- 🔄 **[Migration Guide](MIGRATION.md)** - Upgrade instructions, including v3.x to v4.0.0
- 📝 **[Release Notes](RELEASE_NOTES.md)** - Latest release details

## Support

- 📧 **Email**: support@gameball.co
- 📖 **Documentation**: [https://developer.gameball.co/](https://developer.gameball.co/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/gameballers/gameball-flutter/issues)

## License

MIT License

Copyright (c) 2024 Gameball

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.