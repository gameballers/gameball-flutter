import 'package:flutter/widgets.dart';

import '../iam_log.dart';

/// Called when a campaign asks to navigate, so the host can route however it
/// likes.
///
/// Supply this when the app does not use Navigator 1.0 named routes — go_router,
/// Navigator 2.0 and hand-rolled routers all resolve names their own way, and
/// `Navigator.pushNamed` cannot see their routes.
typedef GameballOnNavigate = void Function(
  String route,
  Map<String, Object>? arguments,
);

/// Routes the host app, so a campaign can send someone to a screen.
///
/// A seam like the presenter and analytics interfaces: it keeps the service free
/// of any `Navigator` dependency and lets tests assert routing without pumping a
/// widget tree.
abstract class MessageNavigator {
  /// Sends the user to [route]. Returns false when routing was not possible, so
  /// the caller can log rather than assume it worked.
  bool pushNamed(String route, {Object? arguments});
}

/// Hands routing to the host.
///
/// The campaign still names the destination; the host decides how to get there.
/// That keeps the feature router-agnostic — the point of a named destination is
/// that a marketer picks from a list the app publishes, not that the SDK knows
/// which routing package you use.
class CallbackNavigator implements MessageNavigator {
  CallbackNavigator(this.onNavigate);

  final GameballOnNavigate onNavigate;

  @override
  bool pushNamed(String route, {Object? arguments}) {
    try {
      onNavigate(route, arguments as Map<String, Object>?);
      return true;
    } catch (error) {
      // A throwing host callback must not escape into the SDK's action handling.
      iamLog('onNavigate threw for route "$route": $error');
      return false;
    }
  }
}

/// Routes through the navigator key the host already gave the SDK.
///
/// This is what Braze cannot do. It has no handle on the host's router, so its
/// deep links go out to the OS and come back through native code and a
/// hand-written channel. Holding the key means simply pushing the route.
class NavigatorKeyNavigator implements MessageNavigator {
  NavigatorKeyNavigator(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  bool pushNamed(String route, {Object? arguments}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      iamLog('cannot navigate to "$route": no navigator available yet');
      return false;
    }

    try {
      navigator.pushNamed(route, arguments: arguments);
      return true;
    } catch (error) {
      // Flutter throws "Could not find a generator for route" when the host has
      // not registered the name. A campaign is authored outside the app, so a
      // route that does not exist is a routine content mistake — it must not be
      // able to throw out of the SDK and into the host's error handling.
      iamLog('cannot navigate to "$route": the host has not registered that '
          'route ($error)');
      return false;
    }
  }
}
