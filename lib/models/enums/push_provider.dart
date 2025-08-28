/// Push notification service provider types supported by the Gameball SDK.
///
/// This enum provides type-safe push provider management to replace string-based
/// provider handling and ensures consistent provider identification across the SDK.
enum PushProvider {
  /// Firebase Cloud Messaging (FCM) for push notifications.
  ///
  /// Used for Android and iOS devices that support Google Play Services.
  Firebase,

  /// Huawei Push Kit (HMS) for push notifications.
  ///
  /// Used for Huawei devices that don't have Google Play Services,
  /// particularly in regions where Google services are not available.
  Huawei;

  /// Returns the string representation of the push provider.
  ///
  /// This method provides the exact string values expected by the Gameball API:
  /// - [PushProvider.Firebase] returns "Firebase"
  /// - [PushProvider.Huawei] returns "Huawei"
  String get value {
    switch (this) {
      case PushProvider.Firebase:
        return 'Firebase';
      case PushProvider.Huawei:
        return 'Huawei';
    }
  }
}