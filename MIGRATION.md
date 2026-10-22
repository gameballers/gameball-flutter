# Migration Guide: Gameball Flutter SDK

This guide provides migration instructions for upgrading between major versions of the Gameball Flutter SDK.

---

## Table of Contents

- [v3.x → v4.0.0](#migration-guide-v3x--v400)
- [v3.2.x → v3.3.0](#migration-guide-v32x--v330)
- [v3.1.1 → v3.2.0](#migration-guide-v311--v320)
- [v3.1.0 → v3.1.1](#migration-guide-v310--v311)
- [v3.0.0 → v3.1.0](#migration-guide-v300--v310)
- [v2.x → v3.0.0](#migration-guide-v2x--v300)

---

## Migration Guide: v3.x → v4.0.0

Version 4.0.0 adds in-app messaging: campaigns authored in the Gameball dashboard, displayed inside your app. It is a **major release** because it raises the minimum supported platform versions to **iOS 15.0** and **Android API 24 (Android 7.0)**. Every v3.x call keeps its signature and behaviour, so no Dart code changes are required.

### Overview of Changes

#### ✨ What's New
- **In-app messaging** - `startInAppMessaging(customerId:, navigatorKey:)` displays dashboard campaigns; `stopInAppMessaging()` stops it and clears state on logout
- **Three message types** - modal, slideup and fullscreen, chosen per campaign in the dashboard rather than in code
- **Triggers** - session start, and custom events matched by name and optionally filtered on their metadata
- **Purchase logging** - `logPurchase(...)` sends a `purchase` event that campaigns can target and filter on
- **Host hooks** - `beforeDisplay`, `onAction`, `onNavigate`, and the `onInAppMessage` stream
- **Automatic message analytics** - impressions, clicks and dismissals, batched and kept on the device until sent

#### ⚠️ Breaking Changes
- **Minimum iOS version raised to 15.0** (was 12.0)
- **Minimum Android version raised to API 24 / Android 7.0** (was API 21 / Android 5.0)
- No changes to the public API. In-app messaging is opt-in: until you call `startInAppMessaging`, the module makes no requests, starts no timers, draws nothing and stores nothing.

### 1. Update Dependencies

**Before (v3.x):**
```yaml
dependencies:
  gameball_sdk: ^3.3.1
```

**After (v4.0.0):**
```yaml
dependencies:
  gameball_sdk: ^4.0.0
```

Run `flutter pub get` to update.

### 2. Raise Platform Minimums

**Before (v3.x):**
```groovy
// android/app/build.gradle
minSdk = 21
```
```ruby
# ios/Podfile
platform :ios, '12.0'
```

**After (v4.0.0):**
```groovy
// android/app/build.gradle
minSdk = 24
```
```ruby
# ios/Podfile
platform :ios, '15.0'
```

Also set `IPHONEOS_DEPLOYMENT_TARGET = 15.0` for the Runner target in Xcode, then run `pod install` in `ios/`.

### 3. Adopt In-App Messaging (Optional)

**Before (v3.x):** not available.

**After (v4.0.0):**
```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  home: const HomeScreen(),
);

// After init() and once the customer is known
GameballApp.getInstance().startInAppMessaging(
  customerId: "customer_123",
  navigatorKey: navigatorKey,
);

// On logout
GameballApp.getInstance().stopInAppMessaging();
```

Three things are worth knowing before you wire it up:

- **The navigator key must be your app's.** The SDK draws above your routes through it, so pass the same `GlobalKey<NavigatorState>` your `MaterialApp` or `CupertinoApp` uses. A key that isn't attached to your app's navigator means messages are selected but never appear.
- **Call `stopInAppMessaging()` on logout.** It dismisses anything on screen, sends pending analytics for the customer who produced them and clears state.
- **If you use go_router or another Navigator 2.0 router, pass `onNavigate`.** Without it the SDK falls back to `Navigator.pushNamed`, which can't see those routes.

### 4. Log Purchases (Optional)

**Before (v3.x):**
```dart
GameballApp.getInstance().sendEvent(
  EventBuilder()
      .customerId("customer_123")
      .eventName("purchase")
      .eventMetaData("productId", "sku-001")
      .build(),
  (success, error) {},
);
```

**After (v4.0.0):**
```dart
GameballApp.getInstance().logPurchase(
  customerId: "customer_123",
  productId: "sku-001",
  price: 49.99,
  currency: "USD",
);
```

`logPurchase` sends the same kind of event through `sendEvent`, with `productId`, `price`, `currency` and `quantity` as metadata, so purchase-triggered campaigns can filter on them.

### Availability

In-app messaging needs the `integrations/inapp-messages` endpoints enabled for your account. Where they aren't, the SDK records the 404 in its debug log and stays silent — nothing surfaces to your app.

### Migration Checklist

#### Pre-Migration
- [ ] Confirm your app can drop support for iOS versions below 15.0 and Android versions below 7.0 (API 24)

#### During Migration
- [ ] Update `gameball_sdk` to `^4.0.0` and run `flutter pub get`
- [ ] Set `minSdk` to 24 in `android/app/build.gradle`
- [ ] Set the iOS deployment target to 15.0 in the Podfile and Xcode, then run `pod install`
- [ ] (Optional) Pass your `MaterialApp`'s navigator key to `startInAppMessaging`
- [ ] (Optional) Call `stopInAppMessaging()` on logout
- [ ] (Optional) Pass `onNavigate` if you use go_router or another Navigator 2.0 router
- [ ] (Optional) Replace hand-built purchase events with `logPurchase`

#### Post-Migration
- [ ] Verify `initializeCustomer`, `sendEvent` and `showProfile` behave as before
- [ ] If adopted, confirm a session-start campaign appears on launch

### Troubleshooting

1. **Build fails after the update**
   ```
   uses-sdk:minSdkVersion 21 cannot be smaller than version 24 declared in library
   ```
   **Solution**: Raise `minSdk` to 24 in `android/app/build.gradle`, and the iOS deployment target to 15.0.

2. **Campaigns never appear**

   **Solution**: Check that the `navigatorKey` passed to `startInAppMessaging` is the one assigned to your `MaterialApp`, that `startInAppMessaging` runs after `init`, and that in-app messaging is enabled for your account. Set `gameballInAppMessagingLogging = true` to see why a campaign was skipped.

---

## Migration Guide: v3.2.x → v3.3.0

Version 3.3.0 adds per-call and global language control, and push notification click tracking. This is a **minor update** with no breaking changes — all v3.2.x and v3.1.x code continues to work.

### Overview of Changes

#### ✨ What's New
- **Per-call widget language** - `ShowProfileRequestBuilder().lang("ar")` presents that one widget in a specific language (2-letter code)
- **Global language switch** - `GameballApp.getInstance().setLanguage("ar")` changes the SDK's global language on demand, without re-calling `init`
- **Push click tracking** - `GameballApp.getInstance().handlePushClick(payload)` reports Gameball push notification taps for campaign click counting

### Update Dependencies

Update your dependency to v3.3.0:

```yaml
dependencies:
  gameball_sdk: ^3.3.0
```

Run `flutter pub get` to update.

### Action Required

None. To adopt the new features, use the optional APIs:

```dart
// Per-call language
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .lang("ar")
    .build();
GameballApp.getInstance().showProfile(context, request);

// Push click tracking — from your notification-tap handler
GameballApp.getInstance().handlePushClick(message.data);
```

---

## Migration Guide: v3.1.1 → v3.2.0

Version 3.2.0 adds a widget event channel, widget dismissal controls, and external-link handling. This is a **minor update** with no breaking changes — all v3.1.x and v3.0.0 code continues to work.

### Overview of Changes

#### ✨ What's New
- **Widget event channel** - pass `widgetEventCallback` to `ShowProfileRequestBuilder` to receive widget events as a `Map<String, dynamic>` `{type, metadata}`; `gameCompleted` includes `hasWon`, `rewardType`, `discountType`, `rewardName`, `campaignId`, `campaignType`
- **Widget dismissal** - the widget can close itself via `window.GameballWidget.closeWidget()`; the host can dismiss it via `GameballApp.getInstance().hideProfile()`
- **External links** - pass `externalLinkCallback` to intercept links the widget flags with `gbExternalBrowser=true`
- **Channel merging** - `ShowProfileRequestBuilder` accepts optional `mobile` and `email`
- **Diagnostic logging** - the SDK now records internal diagnostic logs (automatic, no integration change required)
- **Header** - the `x-gb-agent` header format is now `GB/flutter/<version>`

### Update Dependencies

Update your dependency to v3.2.0:

```yaml
dependencies:
  gameball_sdk: ^3.2.0
```

Run `flutter pub get` to update.

### Action Required

None. To adopt the new features, add the optional callbacks to your existing `ShowProfileRequestBuilder`:

```dart
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")
    .widgetEventCallback((event, error) {
      if (error != null) return;
      // handle the {type, metadata} map
    })
    .build();

GameballApp.getInstance().showProfile(context, request);
```

---

## Migration Guide: v3.1.0 → v3.1.1

Version 3.1.1 adds guest mode support for the profile widget. This is a **patch update** with no breaking changes.

### Overview of Changes

#### 🐛 What's Fixed
- **Guest mode support** - Profile widget can now be displayed without customer authentication
- **Optional customer ID** - `ShowProfileRequest` builder no longer requires customer ID

### Update Dependencies

Update your dependency to v3.1.1:

```yaml
dependencies:
  gameball_sdk: ^3.1.1
```

Run `flutter pub get` to update.

### No Migration Required

Your existing v3.1.0 and v3.0.0 code continues to work without any changes.

### Guest Mode Enhancement (Optional)

#### Before (v3.1.0)
```dart
// Customer ID was required
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")  // Required
    .build();
```

#### After (v3.1.1)
```dart
// Customer ID is now optional

// Authenticated mode
final request = ShowProfileRequestBuilder()
    .customerId("customer_123")  // Optional
    .build();

// Guest mode - no customer ID
final guestRequest = ShowProfileRequestBuilder().build();
```

#### Conditional Widget Display

Show guest mode for unauthenticated users:

```dart
void showLoyaltyWidget(BuildContext context) {
  final customerId = getCustomerId(); // Your method to get customer ID

  final profileRequest = customerId != null
      ? ShowProfileRequestBuilder()
          .customerId(customerId)
          .build()
      : ShowProfileRequestBuilder().build(); // Guest mode

  gameballApp.showProfile(context, profileRequest);
}
```

---

## Migration Guide: v3.0.0 → v3.1.0

Version 3.1.0 introduces security enhancements. This is a **minor update** with no breaking changes.

### Overview of Changes

#### 🔒 What's New
- **Optional Session Token authentication** for enhanced API security
- **Automatic secure endpoint routing** when Session Token is provided

### Update Dependencies

Update your dependency to v3.1.0:

```yaml
dependencies:
  gameball_sdk: ^3.1.0
```

### Optional: Enable Session Token Authentication

If you want to use Session Token authentication, simply add it to your configuration:

```dart
final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .sessionToken("your-secure-session-token")  // Optional: Add for secure authentication
    .build();
```

When Session Token is provided:
- API requests automatically route to secure v4.1 endpoints
- `X-GB-TOKEN` header is included in authenticated requests
- Enhanced security for customer data

### Per-Request Session Token Override

All SDK methods now support an optional `sessionToken` parameter:

```dart
// Use global sessionToken from init()
await gameballApp.initializeCustomer(request, callback);

// Override with a specific token for this request
await gameballApp.initializeCustomer(request, callback, sessionToken: "session-token");

// Nullify sessionToken for this request
await gameballApp.sendEvent(event, callback, sessionToken: null);

// Show profile with custom token
gameballApp.showProfile(context, request, sessionToken: "session-token");
```

**Behavior:**
- **If provided (non-null)**: Overrides and updates the global sessionToken for this and subsequent requests
- **If provided (null)**: Clears the global sessionToken for this and subsequent requests
- **If omitted entirely**: Uses the current global sessionToken from `init()` or last override

**Important Note:** The `sessionToken` parameter must be explicitly passed to **every method call** where you want to use a specific token. If you want consistent authentication across multiple calls, either set it globally via `init()` or pass it to each individual call.

**Use Cases:**
- **Multi-user scenarios**: Switch authentication tokens when users change
- **Anonymous actions**: Clear tokens temporarily for unauthenticated operations
- **Temporary authentication overrides**: Use different tokens for specific operations

### Migration Checklist

- [ ] Update pubspec.yaml dependency to ^3.1.0
- [ ] Run `flutter pub get`
- [ ] (Optional) Add `sessionToken` to your GameballConfig if needed
- [ ] Verify all SDK functionality works correctly
- [ ] Test event tracking
- [ ] Test profile widget displays correctly

### Benefits After Migration

After upgrading to v3.1.0, you'll benefit from:

✅ **Optional Enhanced Security**: GB Token authentication when needed

✅ **Automatic Secure Routing**: SDK automatically uses secure endpoints when token is provided

✅ **Backward Compatible**: Existing code continues to work without changes

---

## Migration Guide: v2.x → v3.0.0

This guide helps you migrate from v2.x to v3.0.0 with modern Flutter architecture, builder patterns, and enhanced type safety.

## Overview of Changes

### 🔧 What's New
- **Builder Pattern Architecture** with enhanced Flutter type safety support
- **Immutable Request Models** with compile-time validation for better developer experience
- **Enhanced API Validation** for better error handling and debugging
- **Simplified Data Flow** for improved performance and maintainability

### ⚠️ Breaking Changes
- Migration from direct object construction to builder pattern
- New immutable models for all requests
- Method signature changes across all SDK methods
- Updated configuration approach with GameballConfig

---

## Step-by-Step Migration

### 1. Update Dependencies

**Before (v2.x):**
```yaml
dependencies:
  gameball_sdk: ^2.2.3
```

**After (v3.0.0):**
```yaml
dependencies:
  gameball_sdk: ^3.0.0
```

### 2. SDK Initialization

**Before (v2.x):**
```dart
gameballApp.init("{api_key}", "{lang}", "{platform}", "{shop}");
```

**After (v3.0.0):**
```dart
import 'package:gameball_sdk/models/requests/gameball_config.dart';

final config = GameballConfigBuilder()
    .apiKey("your_api_key")
    .lang("en")
    .platform("your_platform")
    .shop("your_shop")
    .build();

gameballApp.init(config);
```

### 3. Customer Registration/Initialization

**Before (v2.x):**
```dart
CustomerAttributes customerAttributes = CustomerAttributes(
  displayName: "John Doe",
  firstName: "John",
  lastName: "Doe",
  mobileNumber: "0123456789", // Note: was mobileNumber
  preferredLanguage: "en",
  customAttributes: {
    "city": "New York",
  },
);

gameballApp.registerCustomer(
  "customerId",
  "customer@example.com",
  "1234567890",
  "abc123", // referralCode
  false, // isGuest
  customerAttributes,
  (response, error) {
    // Handle response
  },
);
```

**After (v3.0.0):**
```dart
import 'package:gameball_sdk/models/requests/initialize_customer_request.dart';
import 'package:gameball_sdk/models/requests/customer_attributes.dart';

final request = InitializeCustomerRequestBuilder()
    .customerId("customerId")
    .email("customer@example.com")
    .mobile("1234567890") // Now: mobile
    .referralCode("abc123")
    .isGuest(false)
    .customerAttributes(
        CustomerAttributesBuilder()
            .displayName("John Doe")
            .firstName("John")
            .lastName("Doe")
            .mobile("0123456789") // Now: mobile
            .preferredLanguage("en")
            .addCustomAttribute("city", "New York")
            .build()
    )
    .build();

await gameballApp.initializeCustomer(request, (response, error) {
    // Handle response
});
```

### 4. Customer Attributes

**Before (v2.x):**
```dart
CustomerAttributes customerAttributes = CustomerAttributes(
  displayName: "John Doe",
  mobileNumber: "0123456789",
  customAttributes: {"key": "value"},
);
```

**After (v3.0.0):**
```dart
import 'package:gameball_sdk/models/requests/customer_attributes.dart';

final attributes = CustomerAttributesBuilder()
    .displayName("John Doe")
    .mobile("0123456789")
    .addCustomAttribute("key", "value")
    .addAdditionalAttribute("flexible_field", "value") // New feature
    .build();
```

### 5. Event Tracking

**Before (v2.x):**
```dart
Event eventBody = Event(
  customerId: "customerId",
  events: {
    "purchase": {
      "amount": "100.00",
    },
  },
);

gameballApp.sendEvent(eventBody, (success, error) {
  // Handle response
});
```

**After (v3.0.0):**
```dart
import 'package:gameball_sdk/models/requests/event.dart';

final event = EventBuilder()
    .customerId("customerId")
    .eventName("purchase")
    .eventMetaData("amount", "100.00")
    .eventMetaData("currency", "USD")
    .build();

gameballApp.sendEvent(event, (success, error) {
    // Handle response
});
```

### 6. Profile Widget

**Before (v2.x):**
```dart
gameballApp.showProfile(
  context,
  "customerId",
  "openDetail",
  hideNavigation,
  showCloseButton
);
```

**After (v3.0.0):**
```dart
import 'package:gameball_sdk/models/requests/show_profile_request.dart';

final profileRequest = ShowProfileRequestBuilder()
    .customerId("customerId")
    .openDetail("openDetail")
    .hideNavigation(hideNavigation)
    .showCloseButton(showCloseButton)
    .closeButtonColor("#FF0000") // New feature
    .build();

gameballApp.showProfile(context, profileRequest);
```

### 7. Push Notifications

**Before (v2.x):**
```dart
// Firebase FCM
gameballApp.initializeFirebase();

// Huawei Push Kit
String token = "hms_token";
gameballApp.initalizeHuawei(token);
```

**After (v3.0.0):**
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

---

## Common Migration Patterns

### Error Handling Migration
**Before (v2.x):**
```dart
gameballApp.registerCustomer(/*params*/, (response, error) {
  if (error == null && response != null) {
    // Success
  } else {
    // Handle error
  }
});
```

**After (v3.0.0):**
```dart
try {
  await gameballApp.initializeCustomer(request, (response, error) {
    if (error != null) {
      // Handle API errors with better validation
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

### Field Name Changes
- `mobileNumber` → `mobile` (in both CustomerAttributes and requests)
- `registerCustomer()` → `initializeCustomer()`
- Direct constructor parameters → Builder pattern methods

---

## Migration Checklist

### Pre-Migration
- [ ] Review current SDK usage in your app
- [ ] Identify all SDK method calls
- [ ] Plan for testing after migration
- [ ] Backup current implementation

### During Migration
- [ ] Update Flutter dependency to v3.0.0
- [ ] Convert initialization to use GameballConfig builder
- [ ] Replace registerCustomer calls with initializeCustomer + builder
- [ ] Update customer attributes to use CustomerAttributesBuilder
- [ ] Migrate event tracking to new EventBuilder pattern
- [ ] Update profile widget calls to use ShowProfileRequestBuilder
- [ ] Update push notification handling to use new pattern
- [ ] Change all `mobileNumber` references to `mobile`

### Post-Migration
- [ ] Test all SDK functionality
- [ ] Verify error handling works correctly
- [ ] Test push notifications
- [ ] Verify profile widget displays correctly
- [ ] Test event tracking
- [ ] Run full integration tests

---

## Troubleshooting

### Common Issues

1. **Build Errors After Update**
   ```
   Error: The method 'registerCustomer' isn't defined for the type 'GameballApp'
   ```
   **Solution**: Replace `registerCustomer()` with `initializeCustomer()` and use builder pattern.

2. **Type Mismatch Errors**
   ```
   Error: The argument type 'CustomerAttributes' can't be assigned to the parameter type 'CustomerAttributes'
   ```
   **Solution**: Use `CustomerAttributesBuilder().build()` to create CustomerAttributes objects.

3. **Missing Required Fields**
   ```
   Error: Customer ID cannot be empty
   ```
   **Solution**: Ensure all required fields are set using builder methods before calling `build()`.

4. **MobileNumber Field Not Found**
   ```
   Error: The method 'mobileNumber' isn't defined for the type 'CustomerAttributesBuilder'
   ```
   **Solution**: Replace `mobileNumber()` with `mobile()` in builder calls.

### Getting Help
For additional migration support, contact support@gameball.co or visit our documentation at https://developer.gameball.co/

---

## Benefits After Migration

✅ **Better Type Safety**: Dart's type system prevents common integration errors
✅ **Improved Developer Experience**: Builder pattern with IDE auto-completion support
✅ **Better Error Handling**: Enhanced validation with clear error messages
✅ **Enhanced Performance**: Optimized internal architecture with reduced memory usage
✅ **Future-Proof**: Modern foundation ready for upcoming Flutter features
✅ **Consistent API**: Unified design patterns across all SDK methods

---

*For additional help with migration, contact support@gameball.co*