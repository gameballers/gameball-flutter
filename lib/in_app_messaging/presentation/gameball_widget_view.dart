import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../iam_log.dart';

/// How long the widget has to become ready before the message is abandoned.
///
/// Measured rather than guessed: on a warm simulator load the DOM settles
/// between 4.2s and 5.2s, and a cold first load was still drawing a skeleton at
/// 5s and complete by 10s. Twelve seconds clears the cold case with room for a
/// slow network, and a customer who would have waited longer than that was
/// going to close the card anyway.
const Duration widgetReadyTimeout = Duration(seconds: 12);

/// How often the page is asked whether it has settled.
const Duration _readyPollPeriod = Duration(milliseconds: 250);

/// How many identical consecutive samples confirm the page has come to rest.
///
/// A secondary check, not the safeguard. The load passes through **three**
/// stable plateaus — the skeleton holds still for a full second, a half-built
/// state for another, and only then the finished wheel — so no value of this
/// constant can tell loading from loaded. Raising it only delays every message.
/// What discriminates is the content test in the poller; this just avoids
/// catching the page mid-write.
const int _stableSamplesRequired = 3;

/// A reward campaign in a WebView, which reports when it is actually drawn.
///
/// **Its own controller, deliberately.** `showProfile` builds a controller of
/// its own in `gameball_sdk.dart`, and this does not share it: the two have
/// different channel names, different lifetimes and different close semantics,
/// and every integration already shipped depends on that one behaving exactly
/// as it does. Extracting the common bridge is worth doing once this is proven,
/// not while it is being proven.
///
/// The readiness contract is what this widget exists for. The page fires
/// `onPageFinished` two to three seconds before the wheel is drawn — the widget
/// renders after its own fetches resolve — so mounting on page-load alone puts
/// a skeleton in front of the customer every time. Worse, the content lives in
/// `about:srcdoc` iframes, so a readiness check that only reads the top document
/// sits at ~98 nodes and never fires at all.
class GameballWidgetView extends StatefulWidget {
  const GameballWidgetView({
    super.key,
    required this.url,
    required this.onReady,
    required this.onFailed,
    required this.onCloseRequested,
    this.onEvent,
    this.readyTimeout = widgetReadyTimeout,
  });

  /// The fully composed widget URL. Built by the SDK from its own state, never
  /// carried on the campaign.
  final String url;

  /// Fires once, when the widget has finished drawing. The presenter counts the
  /// impression here rather than at mount.
  final VoidCallback onReady;

  /// Fires once when the widget never became ready, so the caller can take the
  /// message away without ever having shown it.
  final VoidCallback onFailed;

  /// The widget asked to be closed, via `window.GameballWidget.closeWidget()`.
  final VoidCallback onCloseRequested;

  /// Events the widget posts on `window.WidgetEvent.postEvent` — game
  /// completion, most usefully.
  ///
  /// Nothing arrived on this bridge during the load in any probe run, which is
  /// why readiness is detected from the DOM instead. It is wired anyway because
  /// the widget does use it after the game is played.
  final void Function(String raw)? onEvent;

  final Duration readyTimeout;

  @override
  State<GameballWidgetView> createState() => _GameballWidgetViewState();
}

class _GameballWidgetViewState extends State<GameballWidgetView> {
  late final WebViewController _controller;
  Timer? _timeout;
  bool _settled = false;

  /// DIAGNOSTIC: measures the load so trace lines can be lined up against
  /// screenshots.
  final Stopwatch _clock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _clock.start();
    _controller = WebViewController();
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel('GBIamReady',
          onMessageReceived: (m) => _finish(ready: m.message == 'ready'))
      // DIAGNOSTIC (poc/iam-widget-campaign): every readiness sample, so the
      // gate's view of the page can be lined up against what was on screen.
      ..addJavaScriptChannel('GBIamTrace',
          onMessageReceived: (m) =>
              iamLog('widget ${_clock.elapsedMilliseconds}ms ${m.message}'))
      ..addJavaScriptChannel('GBIamClose',
          onMessageReceived: (_) => widget.onCloseRequested())
      ..addJavaScriptChannel('GBIamEvent',
          onMessageReceived: (m) => widget.onEvent?.call(m.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            iamLog('widget ${_clock.elapsedMilliseconds}ms onPageFinished');
            _install();
          },
          onWebResourceError: (e) {
            // The wheel's own sub-resources fail routinely and harmlessly; only
            // the main frame failing means there is nothing to show.
            if (e.isForMainFrame ?? false) {
              iamLog('widget failed to load (${e.description})');
              _finish(ready: false);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Belt and braces: if the page never reaches onPageFinished, nothing would
    // ever install the poller and the message would hang invisible forever.
    _timeout = Timer(widget.readyTimeout, () => _finish(ready: false));
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  /// Reports the outcome exactly once.
  void _finish({required bool ready}) {
    if (_settled) return;
    _settled = true;
    _timeout?.cancel();
    if (!mounted) return;
    iamLog('widget ${_clock.elapsedMilliseconds}ms settled ready=$ready');
    if (ready) {
      widget.onReady();
    } else {
      iamLog('widget did not become ready within '
          '${widget.readyTimeout.inSeconds}s; taking the message away unshown');
      widget.onFailed();
    }
  }

  /// Installs the bridges and the readiness poller.
  ///
  /// Everything runs across frames. The widget draws inside `about:srcdoc`
  /// iframes, which inherit the parent's origin and so stay reachable; a frame
  /// that throws is skipped rather than retried.
  ///
  /// Readiness is "the DOM stopped changing, and there is something in it".
  /// Deliberately content-agnostic: keying off a selector would couple this SDK
  /// to the widget's markup and break silently the next time the web team
  /// renames a class.
  void _install() {
    final timeoutMs = widget.readyTimeout.inMilliseconds;
    _controller.runJavaScript('''
      (function () {
        if (window.__gbIamWatching) return;
        window.__gbIamWatching = true;

        function frames() {
          var out = [window];
          var els = document.querySelectorAll('iframe');
          for (var i = 0; i < els.length; i++) {
            try {
              var w = els[i].contentWindow;
              if (w && w.document) out.push(w);
            } catch (e) { /* cross-origin; nothing to read */ }
          }
          return out;
        }

        function shim(w) {
          try {
            if (w.__gbIamShimmed) return;
            w.__gbIamShimmed = true;
            var post = function (kind, raw) {
              try {
                if (kind === 'event') GBIamEvent.postMessage(String(raw));
                else GBIamClose.postMessage('');
              } catch (e) {}
            };
            var up = (w === window)
              ? post
              : function (k, r) { try { w.parent.__gbIamPost(k, r); } catch (e) {} };
            w.WidgetEvent = w.WidgetEvent || {};
            w.WidgetEvent.postEvent = function (raw) { up('event', raw); };
            w.GameballWidget = w.GameballWidget || {};
            w.GameballWidget.closeWidget = function () { up('close', ''); };
          } catch (e) {}
        }

        // Child frames hand their events up rather than posting: the channel
        // objects are only reliably present in the main frame.
        window.__gbIamPost = function (kind, raw) {
          try {
            if (kind === 'event') GBIamEvent.postMessage(String(raw));
            else GBIamClose.postMessage('');
          } catch (e) {}
        };

        function fingerprint() {
          var fs = frames();
          var nodes = 0, sizedCanvas = 0, imgDone = 0, textLen = 0;
          for (var f = 0; f < fs.length; f++) {
            var w = fs[f];
            shim(w);
            try {
              var d = w.document;
              nodes += d.querySelectorAll('*').length;
              var cv = d.querySelectorAll('canvas');
              for (var j = 0; j < cv.length; j++) {
                if (cv[j].clientWidth > 0 && cv[j].clientHeight > 0) sizedCanvas++;
              }
              var ims = d.querySelectorAll('img');
              for (var i = 0; i < ims.length; i++) {
                if (ims[i].complete && ims[i].naturalWidth > 0) imgDone++;
              }
              if (d.body) textLen += (d.body.innerText || '').trim().length;
            } catch (e) {}
          }
          return {
            key: fs.length + '/' + nodes + '/' + sizedCanvas + '/' + imgDone +
                 '/' + textLen,
            // Content, and specifically NOT a sized canvas. The skeleton has
            // one from the first sample — it is the placeholder — so including
            // it here made the predicate true throughout the loading state, and
            // an OR is only ever as strict as its weakest term. Measured: the
            // skeleton sits at imgDone=0 textLen=0 for a full second, then a
            // half-built state at textLen=35 for another second, before the
            // real content arrives at imgDone=3 textLen=104.
            drawn: imgDone > 0 || textLen > 40
          };
        }

        var last = null, stable = 0, started = Date.now();
        function tick() {
          var fp = fingerprint();
          if (fp.key === last) stable++; else { stable = 0; last = fp.key; }
          try {
            GBIamTrace.postMessage(
              'key=' + fp.key + ' drawn=' + fp.drawn + ' stable=' + stable);
          } catch (e) {}

          if (fp.drawn && stable >= $_stableSamplesRequired) {
            try { GBIamReady.postMessage('ready'); } catch (e) {}
            return;
          }
          if (Date.now() - started > $timeoutMs) {
            try { GBIamReady.postMessage('timeout'); } catch (e) {}
            return;
          }
          setTimeout(tick, ${_readyPollPeriod.inMilliseconds});
        }
        setTimeout(tick, ${_readyPollPeriod.inMilliseconds});
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
