import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/gameball_widget_view.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Stands in for the platform WebView: nothing loads, but the channels the game
/// view opens are kept, so a test can post to them the way the page would.
class _FakeWebViewPlatform extends WebViewPlatform {
  final List<_FakeController> controllers = <_FakeController>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final controller = _FakeController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _FakeWebViewWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  final Map<String, JavaScriptChannelParams> _channels =
      <String, JavaScriptChannelParams>{};

  /// Posts [message] on the channel the page would use.
  void post(String channel, String message) => _channels[channel]!
      .onMessageReceived(JavaScriptMessage(message: message));

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async =>
      _channels[params.name] = params;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
      WebResourceErrorCallback onWebResourceError) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// What the view reported, counted.
class _Outcome {
  int shown = 0;
  int takenAway = 0;
  final List<String> events = <String>[];
}

void main() {
  late _FakeWebViewPlatform platform;

  setUp(() {
    platform = _FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  Future<(_FakeController, _Outcome)> openGame(WidgetTester tester) async {
    final outcome = _Outcome();
    await tester.pumpWidget(GameballWidgetView(
      url: 'https://example.invalid/game',
      onReady: () => outcome.shown++,
      onFailed: () => outcome.takenAway++,
      onCloseRequested: () {},
      onEvent: outcome.events.add,
    ));
    return (platform.controllers.single, outcome);
  }

  String gameReady([Map<String, dynamic>? metadata]) => jsonEncode(
      {'type': 'gameReady', if (metadata != null) 'metadata': metadata});

  testWidgets('a game is shown when the page says it is on screen',
      (tester) async {
    final (page, outcome) = await openGame(tester);

    page.post('GBIamEvent', gameReady({'page': 'wheel', 'playable': true}));

    expect(outcome.shown, 1);
    expect(outcome.takenAway, 0);
  });

  testWidgets('a game the page says cannot be played is taken away unseen',
      (tester) async {
    // "You've already played today!", an ended campaign or the widget's error
    // screen: never something to put over the app unasked.
    final (page, outcome) = await openGame(tester);

    page.post(
        'GBIamEvent',
        gameReady(
            {'page': 'wheel', 'playable': false, 'reason': 'unplayable'}));

    expect(outcome.takenAway, 1);
    expect(outcome.shown, 0);
  });

  testWidgets('a page that says nothing about playing is shown',
      (tester) async {
    // Only an explicit playable:false holds a game back.
    final (page, outcome) = await openGame(tester);

    page.post('GBIamEvent', gameReady());

    expect(outcome.shown, 1);
    expect(outcome.takenAway, 0);
  });

  testWidgets("the page's first word stands", (tester) async {
    final (page, outcome) = await openGame(tester);

    page.post('GBIamEvent', gameReady({'page': 'wheel', 'playable': true}));
    page.post('GBIamEvent',
        gameReady({'page': 'wheel', 'playable': false, 'reason': 'error'}));
    page.post('GBIamReady', 'timeout');
    await tester.pump(widgetReadyTimeout + const Duration(seconds: 1));

    expect(outcome.shown, 1);
    expect(outcome.takenAway, 0);
  });

  testWidgets('the guess from the page still shows a game when no word comes',
      (tester) async {
    // A widget that predates gameReady.
    final (page, outcome) = await openGame(tester);

    page.post('GBIamReady', 'ready');

    expect(outcome.shown, 1);
    expect(outcome.takenAway, 0);
  });

  testWidgets('every event the page posts still reaches the host',
      (tester) async {
    final (page, outcome) = await openGame(tester);
    const played = '{"type":"gameCompleted","metadata":{"points":100}}';

    page.post('GBIamEvent', gameReady({'page': 'wheel', 'playable': true}));
    page.post('GBIamEvent', played);

    expect(outcome.events, [
      gameReady({'page': 'wheel', 'playable': true}),
      played,
    ]);
  });
}
