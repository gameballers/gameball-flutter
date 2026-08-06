# Gameball Flutter SDK Example

This is a demo application showcasing the Gameball Flutter SDK v3.2.1 with builder pattern architecture.

## Features Demonstrated

- **SDK Initialization** with GameballConfig builder
- **Customer Registration** with InitializeCustomerRequest builder
- **Event Tracking** with Event builder
- **Profile Widget** display with ShowProfileRequest builder
- **Guest Mode** support for profile widget (v3.1.1+)
- **Widget Events & Dismissal** - react to events the widget posts, e.g. game completion (v3.2.0+)
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

## Firebase Setup (Optional)

To test push notifications:

1. Add your Firebase configuration to the project
2. Uncomment the Firebase initialization code in `main.dart`
3. Add your device token and push provider to the customer request

## Requirements

- Flutter 1.17.0+ (Recommended: 3.0+)
- Dart 3.4.4+
- Android API level 21+
- iOS 12.0+

## Documentation

For complete documentation, visit:
- [Main README](../README.md)
- [API Documentation](https://developer.gameball.co/)
- [Migration Guide](../MIGRATION.md)

## Support

- Email: support@gameball.co
- Issues: [GitHub Issues](https://github.com/gameballers/gameball-flutter/issues)
