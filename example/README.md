# Gameball Flutter SDK Example

This is a demo application showcasing the Gameball Flutter SDK v4.0.0 with builder pattern architecture.

## Features Demonstrated

- **SDK Initialization** with GameballConfig builder
- **Customer Registration** with InitializeCustomerRequest builder
- **Event Tracking** with Event builder
- **Profile Widget** display with ShowProfileRequest builder
- **Guest Mode** support for profile widget (v3.1.1+)
- **Widget Events & Dismissal** - react to events the widget posts, e.g. game completion (v3.2.0+)
- **Language Control** - per-call widget language and global language switch (v3.3.0+)
- **Push Click Tracking** - report taps on Gameball push notifications (v3.3.0+)
- **In-App Messaging** - display dashboard campaigns with `startInAppMessaging`, observe them on `onInAppMessage` and stop on logout (v4.0.0+)
- **Purchase Logging** - send purchase events with `logPurchase` for purchase-triggered campaigns (v4.0.0+)
- **Session Token Authentication** (optional, v3.1.0+)
- **Push Notifications** setup (Firebase & Huawei)

## Getting Started

### 1. Configure Your API Key

Open `lib/main.dart` and replace the placeholder values:

```dart
final config = GameballConfigBuilder()
    .apiKey("{your_api_key}")        // Replace with your API key
    .lang("en")
    .platform("{your_platform}")      // Replace with your platform
    .shop("{your_shop}")              // Replace with your shop
    .build();
```

### 2. (Optional) Enable Session Token Authentication

Uncomment and configure the session token for enhanced security:

```dart
final config = GameballConfigBuilder()
    .apiKey("{your_api_key}")
    .lang("en")
    .sessionToken("your-session-token")  // Enable secure authentication
    .build();
```

### 3. Run the Example

```bash
flutter pub get
flutter run
```

### 4. Test the SDK

Click the play button (▶) in the app to test:
- Customer initialization
- Event tracking
- Profile widget display
- In-app messaging (a session-start campaign appears if one is live for your account)
- Purchase logging

### 5. In-App Messaging (v4.0.0+)

The SDK draws messages through your app's navigator, so the example passes the same key to `MaterialApp` and to `startInAppMessaging`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(navigatorKey: navigatorKey, home: ...);

gameballApp.startInAppMessaging(
  customerId: "demo_customer_123",
  navigatorKey: navigatorKey,
);
```

Campaigns are created in the Gameball dashboard, and in-app messaging must be enabled for your account. The example turns on `gameballInAppMessagingLogging`, so the console shows why each campaign was shown or skipped.

## Firebase Setup (Optional)

To test push notifications:

1. Generate `lib/firebase_options.dart` for your Firebase project with `flutterfire configure`
2. Uncomment the `firebase_core` and `firebase_options.dart` imports and the `Firebase.initializeApp` call in `main.dart`
3. Add your device token and push provider to the customer request

## Requirements

- Flutter 1.17.0+ (Recommended: 3.0+)
- Dart 3.4.4+
- Android API level 24+ (Android 7.0)
- iOS 15.0+

## Documentation

For complete documentation, visit:
- [Main README](../README.md)
- [API Documentation](https://developer.gameball.co/)
- [Migration Guide](../MIGRATION.md)

## Support

- Email: support@gameball.co
- Issues: [GitHub Issues](https://github.com/gameballers/gameball-flutter/issues)
