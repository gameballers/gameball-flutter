# Migration Guide: Gameball Flutter SDK

This guide provides migration instructions for upgrading between major versions of the Gameball Flutter SDK.

---

## Table of Contents

- [v3.1.0 → v3.1.1](#migration-guide-v310--v311)
- [v3.0.0 → v3.1.0](#migration-guide-v300--v310)
- [v2.x → v3.0.0](#migration-guide-v2x--v300)

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