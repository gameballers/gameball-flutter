# Migration Guide: Gameball Flutter SDK v2.x → v3.0.0

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
For additional migration support, contact support@gameball.co or visit our documentation at https://docs.gameball.co

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