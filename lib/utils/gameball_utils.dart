import 'package:package_info_plus/package_info_plus.dart';

/// Checks whether a string is null or empty or not.
bool isNullOrEmpty(String? str) {
  return str == null || str.isEmpty;
}

/// Retrieves package information asynchronously.
///
/// Fetches package information from the platform and returns it as a `PackageInfo` object.
///
/// Returns:
///   A `PackageInfo` object containing package details, or null if not available yet.
PackageInfo? getPckageInfo() {
  PackageInfo? packageInfo;

  PackageInfo.fromPlatform().then((response) {
    packageInfo = response;
  });

  return packageInfo;
}

/// A function that returns the SDK version as a string.
String getSdkVersion() {
  return "2.0.0";
}
