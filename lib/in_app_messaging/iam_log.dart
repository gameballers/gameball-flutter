import 'package:flutter/foundation.dart';

/// Whether the in-app messaging module writes diagnostics to the console.
///
/// Defaults to [kDebugMode]: on while the integrator is building, silent in a
/// release build, where these lines reach the device log of every end user and
/// say nothing that user or the host app can act on. Set it to true in a release
/// build only to reproduce a reported problem.
bool gameballInAppMessagingLogging = kDebugMode;

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from `GameballLogger`, which posts telemetry to the
/// Gameball backend. Parse and evaluation diagnostics belong in the
/// integrator's console, not in a network request.
///
/// Uses [debugPrint] rather than `dart:developer`'s `log()`: the latter routes
/// to the VM service and does **not** appear in `flutter run` output, which is
/// the one place a developer looks for these.
void iamLog(String message) {
  if (!gameballInAppMessagingLogging) return;
  debugPrint('[GameballIAM] $message');
}
