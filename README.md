# Gameball Flutter SDK
## `Gameball Flutter SDK` is a library that allows you to integrate the Gameball platform's features into your Flutter applications. It enables you to:

  * Register customers and track their activities.
* Send personalized events to trigger Gameball campaigns.
* Display the Gameball user interface within your app.

# Installation
1 Add the `Gameball Flutter SDK` dependency to your pubspec.yaml file or the flutter add command directly:
```
YAML

dependencies:
  gameball_sdk: ^latest
```
```
Bash

$ flutter pub add gameball_sdk
```
2. Import the library in your Dart code:
```
Dart

import 'package:gameball_sdk/gameball_sdk.dart';
```

# Usage
1. Initialization
* Create an instance of `GameballApp`:
```
Dart

GameballApp gameballApp = GameballApp.getInstance();
```
* Initialize the Gameball SDK with your API key, language, platform, and shop information:
```
Dart

gameballApp.init("{api_key}", "{lang}", "{platform}", "{shop}");
```
2. Firebase Initialization (for referral handling):
* Ensure Firebase is initialized in your app before using referral features:
```
Dart

import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // ... rest of your app
}
```
3. Customer Registration:
* Register a customer with their unique identifier, email (optional), mobile number (optional), and custom attributes:
```
Dart

CustomerAttributes customerAttributes = CustomerAttributes(
  displayName: "John Doe",
  firstName: "John",
  lastName: "Doe",
  mobileNumber: "0123456789",
  preferredLanguage: "en",
  customAttributes: {
    "{key}": "{value}",
  },
);

gameballApp.registerCustomer(
  "{customerId}",
  "{customerEmail}",
  "{customerMobile}",
  false, //isGuest = false
  CustomerAttributes,
  (response, error) {
    // Handle registration response
  },
);
```
4. Sending Events:
* Define an `Event` object with the customer's unique identifier and event details:
```
Dart

Event eventBody = Event(
  customerId: "{customerId}",
  events: {
    "{eventName}": {
      "{prop1}": "{value1}",
    },
  },
);

gameballApp.sendEvent(eventBody, (success, error) {
  // Handle event sending response
});
```
5. Showing Gameball Profile:
* Display the Gameball user interface within your app using `showProfile`:
```
Dart

gameballApp.showProfile(context, "{customerId}", "{openDetail}", "{hideNavigation}", "{showCloseButton}");
```
* Replace `context` with the current build context.
* Use placeholders for `customerId`, `openDetail` (optional URL to open within the profile), `hideNavigation` (optional boolean to hide/show navigation arrow), `showCloseButton` (optional boolean to hide/show close button).
  Note: Replace all instances of `"{...}"` placeholders with your actual values.

# Additional Resources
* For detailed API reference and comprehensive documentation, visit the official Gameball developer website: https://developer.gameball.co/
* Explore the Gameball platform and its features at the Gameball website: https://www.gameball.co/
* Feel free to contact Gameball support for any further assistance.