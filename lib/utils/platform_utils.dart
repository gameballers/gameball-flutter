import 'dart:io';

/// Determines the device platform.
///
/// Returns the device platform as a string (iOS, Android, or Unknown).
String getDevicePlatform() {
  if (Platform.isIOS) {
    return 'iOS';
  } else if (Platform.isAndroid) {
    return 'Android';
  } else {
    return 'Unknown';
  }
}

/// The device platform as the backend's numeric enum: 1 iOS, 2 Android.
///
/// Zero for anything else, which is neither and is what an unsupported host
/// should report rather than guessing.
int getDevicePlatformCode() {
  return switch (getDevicePlatform()) {
    'iOS' => 1,
    'Android' => 2,
    _ => 0,
  };
}
