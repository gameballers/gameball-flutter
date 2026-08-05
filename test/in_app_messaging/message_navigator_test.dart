import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_navigator.dart';

Future<GlobalKey<NavigatorState>> pumpHost(WidgetTester tester) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: key,
    home: const Scaffold(body: Text('host')),
    routes: <String, WidgetBuilder>{
      '/cart': (_) => const Scaffold(body: Text('cart screen')),
    },
  ));
  return key;
}

void main() {
  testWidgets('pushes a route the host registered', (tester) async {
    final key = await pumpHost(tester);

    final pushed = NavigatorKeyNavigator(key).pushNamed('/cart');
    await tester.pumpAndSettle();

    expect(pushed, isTrue);
    expect(find.text('cart screen'), findsOneWidget);
  });

  testWidgets('passes arguments through', (tester) async {
    final key = GlobalKey<NavigatorState>();
    Object? received;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: Text('host')),
      onGenerateRoute: (settings) {
        received = settings.arguments;
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('target')),
        );
      },
    ));

    NavigatorKeyNavigator(key).pushNamed('/x', arguments: {'from': 'campaign'});
    await tester.pumpAndSettle();

    expect(received, {'from': 'campaign'});
  });

  testWidgets('an unregistered route is reported, not thrown', (tester) async {
    final key = await pumpHost(tester);

    final pushed =
        NavigatorKeyNavigator(key).pushNamed('/typo-by-a-marketer');
    await tester.pump();

    expect(pushed, isFalse);
    expect(tester.takeException(), isNull,
        reason: 'a campaign is authored outside the app, so a bad route name is '
            'routine content error — it must not escape into the host');
    expect(find.text('host'), findsOneWidget);
  });

  testWidgets('a missing navigator is reported, not thrown', (tester) async {
    final navigator = NavigatorKeyNavigator(GlobalKey<NavigatorState>());

    expect(navigator.pushNamed('/cart'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
