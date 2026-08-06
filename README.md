# Gameball Flutter SDK

[![Version](https://img.shields.io/badge/version-3.2.1-blue.svg)](https://github.com/gameballers/gameball-flutter)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-1.17%2B-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.4.4%2B-blue.svg)](https://dart.dev)

Gameball Flutter SDK allows you to integrate customer engagement and loyalty features into your Flutter applications with modern builder patterns and immutable request models.

## Features

- 🎯 **Customer Management** - Initialize and manage customer profiles with builder pattern
- 📊 **Event Tracking** - Track user actions and behaviors with flexible metadata
- 🎁 **Profile Widget** - Display customer loyalty information in customizable UI
- 🔧 **Modern Architecture** - Built with Flutter best practices and null safety
- 🛡️ **Type Safety** - Compile-time validation with Dart's type system
- ⚡ **Async/Await Ready** - Modern async architecture with proper error handling

## Requirements

- **Minimum Flutter Version**: 1.17.0
- **Dart**: 3.4.4+
- **Android**: API level 21+
- **iOS**: 12.0+

> **Note**: While the SDK supports Flutter 1.17.0+, we recommend using Flutter 3.0+ for the best development experience with modern features like null safety and enhanced tooling.

## Installation

### pubspec.yaml
```yaml
dependencies:
  gameball_sdk: ^3.2.1
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

## API Methods

The SDK provides the following public methods:
- `init(config)` - Initialize the SDK with GameballConfig
- `initializeCustomer(request, callback, {sessionToken})` - Register/initialize customer with builder pattern
- `sendEvent(event, callback, {sessionToken})` - Track events with Event builder
- `showProfile(context, request, {sessionToken})` - Show profile widget with ShowProfileRequest
- `hideProfile()` - Dismiss the currently shown profile widget (no-op when nothing is shown)

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
| `isGuest` | bool | ❌ | Guest status (defaults to false) |
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
- `isGuest(bool isGuest)` - Sets guest status
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
    .isGuest(false)
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
| `preferredLanguage` | String | ❌ | Preferred language (2-letter ISO code) |
| `customAttributes` | Map<String, String> | ❌ | Custom key-value pairs |
| `additionalAttributes` | Map<String, String> | ❌ | Additional flexible attributes |
| `channel` | String | 🔒 | Channel identifier (automatically set to "mobile") |

**Validation Rules:**
- `preferredLanguage` must be 2-letter ISO language code if provided
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

## Documentation

- 📋 **[Changelog](CHANGELOG.md)** - Version history and changes
- 🔄 **[Migration Guide](MIGRATION.md)** - v2.x to v3.0.0 upgrade instructions
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