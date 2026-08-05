import 'dart:developer' as developer;

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from `GameballLogger`, which posts telemetry to the
/// Gameball backend. Parse and evaluation diagnostics belong in the
/// integrator's console, not in a network request.
void iamLog(String message) {
  developer.log(message, name: 'GameballIAM');
}
