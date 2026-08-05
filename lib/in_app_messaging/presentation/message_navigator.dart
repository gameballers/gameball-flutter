import 'package:flutter/widgets.dart';

import '../iam_log.dart';

/// Routes the host app, so a campaign can send someone to a screen.
///
/// A seam like the presenter and analytics interfaces: it keeps the service free
/// of any `Navigator` dependency and lets tests assert routing without pumping a
/// widget tree.
abstract class MessageNavigator {
  /// Pushes [route]. Returns false when there is nothing to route with, so the
  /// caller can log rather than assume it worked.
  bool pushNamed(String route, {Object? arguments});
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
    navigator.pushNamed(route, arguments: arguments);
    return true;
  }
}
