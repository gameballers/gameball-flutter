import 'package:flutter/foundation.dart';

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from `GameballLogger`, which posts telemetry to the
/// Gameball backend. Parse and evaluation diagnostics belong in the
/// integrator's console, not in a network request.
///
/// Uses [debugPrint] rather than `dart:developer`'s `log()`: the latter routes
/// to the VM service and does **not** appear in `flutter run` output, which
/// made every diagnostic here invisible in the one place a developer actually
/// looks. Verified against a live simulator run.
void iamLog(String message) {
  debugPrint('[GameballIAM] $message');
}
