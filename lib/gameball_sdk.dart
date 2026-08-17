library gameball_sdk;

import 'dart:async';
import 'dart:convert';

import 'package:gameball_sdk/network/request_calls/initialize_customer_request.dart';
import 'package:gameball_sdk/network/request_calls/send_message_events_request.dart';
import 'package:gameball_sdk/network/request_calls/fetch_message_variables_request.dart';
import 'package:gameball_sdk/network/request_calls/sync_in_app_messages_request.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:gameball_sdk/utils/gameball_utils.dart';
import 'package:gameball_sdk/utils/gameball_logger.dart';
import 'package:gameball_sdk/utils/language_utils.dart';
import 'package:gameball_sdk/utils/platform_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';

import 'in_app_messaging/analytics/batched_message_analytics.dart';
import 'in_app_messaging/analytics/message_analytics.dart';
import 'in_app_messaging/evaluation/frequency_cap.dart';
import 'in_app_messaging/iam_log.dart';
import 'in_app_messaging/in_app_messaging_service.dart';
import 'in_app_messaging/models/in_app_message.dart';
import 'in_app_messaging/models/in_app_message_campaign.dart';
import 'in_app_messaging/models/message_trigger.dart';
import 'in_app_messaging/personalisation/variable_source.dart';
import 'in_app_messaging/presentation/artwork_prefetcher.dart';
import 'in_app_messaging/presentation/message_navigator.dart';
import 'in_app_messaging/presentation/overlay_presenter.dart';
import 'in_app_messaging/source/campaign_cache.dart';
import 'in_app_messaging/source/http_message_source.dart';
import 'in_app_messaging/source/message_source.dart';
import 'models/requests/event.dart';
import 'models/requests/initialize_customer_request.dart';
import 'models/requests/show_profile_request.dart';
import 'models/requests/gameball_config.dart';
import 'network/models/callbacks.dart';
import 'network/request_calls/send_event_request.dart';

import 'network/utils/constants.dart';

/// The in-app messaging public surface, so hosts need only one import.
export 'in_app_messaging/in_app_messaging.dart';

class GameballApp extends StatelessWidget {
  const GameballApp({super.key});
  
  static GameballApp? _instance;
  static String _apiKey = "";
  static String _lang = "";
  static String? _platform;
  static String? _shop;
  static String? _customerPreferredLanguage;
  static String? _apiPrefix;
  static String? _sessionToken;
  static VoidCallback? _dismissActiveWidget;

  /// Null until [startInAppMessaging] is called. Everything in-app-messaging
  /// related no-ops while this is null, so upgrading changes nothing for a
  /// client that does not opt in.
  static InAppMessagingService? _inAppMessaging;

  /// Created on first access of [onInAppMessage], so a host that never listens
  /// pays nothing.
  static StreamController<GameballInAppMessage>? _inAppMessageController;

  /// The navigator key the current presenter is bound to, so a changed key can
  /// be detected and the presenter rebuilt.
  static GlobalKey<NavigatorState>? _inAppMessagingNavigatorKey;

  /// Who analytics events are attributed to.
  ///
  /// Held here rather than captured in the sender closure because the analytics
  /// buffer is built once, while `startInAppMessaging` may later run for a
  /// different customer — a closure would keep sending under the first identity.
  static String? _inAppMessagingCustomerId;

  /// Registered on first [startInAppMessaging] so warm resumes begin new
  /// sessions. Null for any client that never opts in.
  static _GameballLifecycleObserver? _lifecycleObserver;

  /// Retrieves the singleton instance of the GameballApp class.
  ///
  /// Creates a new instance if it doesn't exist and returns it.
  static GameballApp getInstance() {
    _instance ??= const GameballApp();
    return _instance!;
  }

  /// Initializes the Gameball SDK with required parameters.
  ///
  /// Sets the API key, language, platform, and shop information for subsequent SDK operations.
  ///
  /// Arguments:
  ///   - `config`: The GameballConfig containing all initialization parameters.
  void init(GameballConfig config) {
    _lang = config.lang;
    _platform = config.platform;
    _shop = config.shop;
    _apiKey = config.apiKey;
    _apiPrefix = config.apiPrefix;
    _sessionToken = config.sessionToken;

    GameballLogger.instance.configure(apiKey: _apiKey, lang: _lang, apiPrefix: _apiPrefix);
    GameballLogger.instance.log('sdk.init', params: {
      'apiKey': config.apiKey,
      'lang': config.lang,
      'platform': config.platform,
      'shop': config.shop,
      'apiPrefix': config.apiPrefix,
      'sessionToken': config.sessionToken,
    });
  }

  /// Initializes a customer using a pre-built [InitializeCustomerRequest].
  ///
  /// This method validates the API key, stores essential customer data for widget display,
  /// and sends the complete request to the Gameball API for customer registration.
  ///
  /// Arguments:
  ///   - `request`: The InitializeCustomerRequest containing all customer initialization parameters.
  ///   - `responseCallback`: A callback function to handle the registration response.
  ///   - `sessionToken`: Optional session token for this request.
  ///                     If provided, overrides the global sessionToken.
  ///                     If not provided, nullifies the global sessionToken.
  Future<void> initializeCustomer(
    InitializeCustomerRequest request,
    RegisterCallback? responseCallback, {
    String? sessionToken,
  }) async {
    // Validate API key
    if (isNullOrEmpty(_apiKey)) {
      responseCallback!(null, Exception('API key is not initialized. Call init() first'));
      return;
    }

    // Override or nullify sessionToken based on parameter
    _sessionToken = sessionToken;

    // Store customer preferred language for widget display
    if (request.customerAttributes?.preferredLanguage != null &&
        request.customerAttributes?.preferredLanguage?.length == 2) {
      _customerPreferredLanguage = request.customerAttributes?.preferredLanguage;
    }

    // Send request to Gameball API
    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      initializeCustomerRequest(request, _apiKey, language, customApiPrefix: _apiPrefix, sessionToken: _sessionToken)
          .then((response) {
        responseCallback!(response, null);
      });
      // Fire telemetry immediately after dispatching the request.
      GameballLogger.instance.log('sdk.initializeCustomer', params: request.toJson());
    } catch (e) {
      responseCallback!(null, e as Exception);
    }

    // Additive: tell in-app messaging the customer may have changed. Guarded,
    // and deliberately outside the request's future chain — that chain has no
    // catchError, so anything thrown inside it escapes unhandled.
    try {
      _inAppMessagingCustomerId = request.customerId;
      _inAppMessaging?.onCustomerChanged(request.customerId);
    } catch (error) {
      iamLog('onCustomerChanged hook failed: $error');
    }
  }

  /// Sends an event to Gameball.
  ///
  /// This method constructs an event request and sends it to the Gameball API.
  /// The callback is invoked with a success/failure indicator and any encountered error.
  ///
  /// Arguments:
  ///   - `event`: The event data to be sent.
  ///   - `callback`: The callback function to handle the event sending result.
  ///   - `sessionToken`: Optional session token for this request.
  ///                     If provided, overrides the global sessionToken.
  ///                     If not provided, nullifies the global sessionToken.
  void sendEvent(Event event, SendEventCallback? callback, {String? sessionToken}) {
    // Validate API key
    if (isNullOrEmpty(_apiKey)) {
      callback!(null, Exception('API key is not initialized. Call init() first'));
      return;
    }

    // Override or nullify sessionToken based on parameter
    _sessionToken = sessionToken;

    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      sendEventRequest(event, _apiKey, language, customApiPrefix: _apiPrefix, sessionToken: _sessionToken).then((response) {
        if (response.statusCode == 200) {
          callback!(true, null);
        } else {
          callback!(false, null);
        }
      });
      // Fire telemetry immediately after dispatching the request.
      GameballLogger.instance.log('sdk.sendEvent', params: event.toJson());
    } catch (e) {
      callback!(null, e as Exception);
    }

    // Additive: an event may trigger an in-app message. Guarded, and
    // deliberately outside the request's future chain — that chain has no
    // catchError, so anything thrown inside it escapes unhandled.
    try {
      final service = _inAppMessaging;
      if (service != null) {
        // Iterating entries, not keys: `Event.events` maps a name to its
        // metadata, and a campaign's property filters are evaluated against that
        // metadata. Passing only the name made every filtered custom-event
        // campaign unmatchable, because a filter on an absent property never
        // matches — the filters were built and unit-tested but unreachable.
        for (final entry in event.events.entries) {
          service.onCustomEvent(entry.key, properties: entry.value);
        }
      }
    } catch (error) {
      iamLog('onCustomEvent hook failed: $error');
    }
  }

  /// Logs a purchase.
  ///
  /// Additive: no existing behaviour changes and no client is required to call
  /// it. Sends an event to the same events endpoint as [sendEvent], using the
  /// reserved name `purchase` with the purchase details as metadata, and — when
  /// in-app messaging is running — notifies it so any-purchase and
  /// specific-purchase campaigns can trigger.
  ///
  /// Arguments:
  ///   - `customerId`: who bought. Required for the same reason [sendEvent]
  ///     takes it on the `Event` — this SDK keeps no ambient customer.
  ///   - `productId`: identifier of the item bought.
  ///   - `price`: unit price.
  ///   - `currency`: ISO currency code, e.g. `USD`.
  ///   - `quantity`: number of units, defaulting to 1.
  ///   - `properties`: extra metadata, also available to campaign filters.
  ///   - `callback`: invoked with the send result, as [sendEvent] does.
  ///   - `sessionToken`: optional session token for this request.
  void logPurchase({
    required String customerId,
    required String productId,
    required double price,
    required String currency,
    int quantity = 1,
    Map<String, Object>? properties,
    SendEventCallback? callback,
    String? sessionToken,
  }) {
    final metadata = <String, Object>{
      'productId': productId,
      'price': price,
      'currency': currency,
      'quantity': quantity,
      ...?properties,
    };

    final builder = EventBuilder()
        .customerId(customerId)
        .eventName(gameballPurchaseEventName);
    for (final entry in metadata.entries) {
      builder.eventMetaData(entry.key, entry.value);
    }

    sendEvent(builder.build(), callback, sessionToken: sessionToken);

    // Additive and guarded, like the other in-app messaging hooks. Note this
    // runs in addition to the custom-event hook inside sendEvent, so a campaign
    // can trigger on either the purchase or the reserved event name.
    try {
      _inAppMessaging?.onPurchase(
        productId: productId,
        price: price,
        currency: currency,
        quantity: quantity,
        properties: properties,
      );
    } catch (error) {
      iamLog('onPurchase hook failed: $error');
    }
  }

  /// Opts in to in-app messaging for [customerId].
  ///
  /// Nothing in the in-app messaging module runs until this is called: no
  /// requests, no timers, no state. Existing integrations are unaffected by
  /// upgrading.
  ///
  /// [navigatorKey] must be the key assigned to your `MaterialApp.navigatorKey`
  /// — it is how the SDK finds a surface to draw on without needing a
  /// `BuildContext` at every call site.
  ///
  /// [beforeDisplay] is consulted immediately before each message is shown, and
  /// can show, defer or discard it. Omit it to always show.
  ///
  /// [sessionTimeout] is how long the app must be in the background before a
  /// return to the foreground counts as a new session and fires the session-start
  /// trigger again. Defaults to 30 seconds.
  ///
  /// Braze's native default is 10 seconds. Ours is deliberately longer, and
  /// matched to the 30-second minimum interval between displays: because a message
  /// can only be shown while the app is in the foreground, time-since-last-display
  /// is always at least the time spent in the background, so aligning the two
  /// guarantees a new session is never blocked by the display floor. Lowering this
  /// below that floor reintroduces the gap Braze lives with, where a session-start
  /// campaign is selected and then silently suppressed.
  ///
  /// Takes effect when messaging first starts. To change it later, call
  /// [stopInAppMessaging] first.
  ///
  /// Calling this again with a different [customerId] refetches campaigns and
  /// resets frequency caps. Calling it with the same one does nothing.
  void startInAppMessaging({
    required String customerId,
    required GlobalKey<NavigatorState> navigatorKey,
    GameballBeforeDisplay? beforeDisplay,
    GameballOnAction? onAction,
    GameballOnNavigate? onNavigate,
    Duration sessionTimeout = defaultSessionTimeout,
  }) {
    if (isNullOrEmpty(_apiKey)) {
      iamLog('startInAppMessaging ignored: API key is not initialized. '
          'Call init() first');
      return;
    }

    // Rebuild when the host supplies a different navigator key — which is what
    // a hot restart does. Reusing the old presenter would leave it bound to a
    // key whose widget is gone, and messages would silently never appear.
    if (_inAppMessaging != null && _inAppMessagingNavigatorKey != navigatorKey) {
      iamLog('navigator key changed; rebuilding the presenter');
      _inAppMessaging!.stop();
      _inAppMessaging = null;
    }
    _inAppMessagingNavigatorKey = navigatorKey;
    // Read by the analytics sender on every batch rather than captured once, so a
    // later start() for a different customer attributes events correctly.
    _inAppMessagingCustomerId = customerId;

    if (_inAppMessaging != null && sessionTimeout != _inAppMessaging!.sessionTimeout) {
      iamLog('sessionTimeout ignored: messaging is already running with '
          '${_inAppMessaging!.sessionTimeout.inSeconds}s. Call '
          'stopInAppMessaging() first to change it');
    }

    final service = _inAppMessaging ??= InAppMessagingService(
      source: debugMessageSource ?? HttpMessageSource(_syncInAppMessages),
      presenter: OverlayPresenter(navigatorKey),
      // Persisted, both of them: the backend's contract requires that a
      // non-repeatable campaign never shows again "locally too", and that a
      // failed sync falls back to the previous cache. Neither survives a restart
      // in memory.
      frequencyCap: StoredFrequencyCap(),
      campaignCache: StoredCampaignCache(),
      analytics: debugAnalytics ??
          BatchedMessageAnalytics(send: _sendInAppMessageEvents),
      sessionTimeout: sessionTimeout,
      isHostWidgetOpen: () => _dismissActiveWidget != null,
      // The host routes when it told us how; otherwise fall back to named
      // routes, which is right for a plain MaterialApp but cannot see the routes
      // of go_router or any other Navigator 2.0 router.
      navigator: onNavigate != null
          ? CallbackNavigator(onNavigate)
          : NavigatorKeyNavigator(navigatorKey),
      // Artwork is loaded at sync rather than at display, so the impression is
      // logged for a message the user can actually see.
      prefetcher: debugArtworkPrefetcher ?? ImageCacheArtworkPrefetcher(),
      // Personalisation values, fetched just before display and cached briefly.
      // Inert until the backend sends text that still contains {tokens}.
      variables: debugVariableSource ??
          CachingVariableSource(fetcher: _fetchMessageVariables),
      emit: (message) => _inAppMessageController?.add(message),
    );

    // Watch the app lifecycle so a resume after the session timeout starts a new
    // session and fires session_start again. Registered once, and only for hosts
    // that opted in, so a client who never starts messaging gains no observer.
    if (_lifecycleObserver == null) {
      final observer = _GameballLifecycleObserver();
      _lifecycleObserver = observer;
      WidgetsBinding.instance.addObserver(observer);
    }

    service.start(
      customerId: customerId,
      beforeDisplay: beforeDisplay,
      onAction: onAction,
    );
  }

  /// Ships one batch of in-app message analytics events.
  ///
  /// A plain static function so it can be handed to the analytics buffer as a
  /// value: the buffer owns batching, persistence and retry, and this owns nothing
  /// but the request. Returning false leaves the batch queued, which is why an
  /// unconfigured SDK is a false rather than a drop — the events go out once
  /// [init] and [startInAppMessaging] have run.
  /// Replaces the campaign source. Tests only — never set this in an app.
  ///
  /// The end-to-end suite drives the real module through this class, and without a
  /// substitute every test would perform a live sync.
  @visibleForTesting
  static GameballMessageSource? debugMessageSource;

  /// The host app's version, resolved once.
  ///
  /// Cached because `PackageInfo` is an async platform call and a sync happens on
  /// every session start; re-reading it would put a channel round trip on the path
  /// to the first message.
  static String? _appVersion;

  /// Performs one sync request for [customerId].
  ///
  /// Reads credentials at call time rather than capturing them, so a later
  /// `init` or `initializeCustomer` is picked up without rebuilding the source.
  static Future<String?> _syncInAppMessages(String customerId) async {
    if (isNullOrEmpty(_apiKey)) return null;

    if (_appVersion == null) {
      try {
        _appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {
        // Targeting by app version degrades; syncing must not.
        _appVersion = '';
      }
    }

    return syncInAppMessagesRequest(
      customerId: customerId,
      platform: getDevicePlatformCode(),
      locale: handleLanguage(_lang, _customerPreferredLanguage),
      appVersion: _appVersion ?? '',
      sdkVersion: getSdkVersion(),
      apiKey: _apiKey,
      customApiPrefix: _apiPrefix,
      sessionToken: _sessionToken,
    );
  }

  /// Replaces the analytics implementation. Tests only — never set this in an app.
  ///
  /// The end-to-end tests drive the module through this class's public API, which
  /// is the point of them. Left alone they would post batches to the live API and
  /// leave the ten-second flush timer pending, which a widget test rightly rejects.
  @visibleForTesting
  static MessageAnalytics? debugAnalytics;

  /// Replaces the artwork prefetcher. Tests only — never set this in an app.
  ///
  /// `flutter_test` answers every HTTP request with a 400, so the real
  /// prefetcher correctly reports the fixtures' artwork as unloadable and the
  /// module correctly suppresses those campaigns. Right behaviour, but it leaves
  /// the end-to-end suite with nothing to display.
  @visibleForTesting
  static ArtworkPrefetcher? debugArtworkPrefetcher;

  /// Replaces the personalisation source. Tests only — never set this in an app.
  ///
  /// Without it a token-bearing message would reach for the live endpoint, which
  /// `flutter_test` answers with a 400 — harmless, but it makes a suite's
  /// behaviour depend on a network call it never meant to make.
  @visibleForTesting
  static VariableSource? debugVariableSource;

  /// Fetches the customer's current personalisation values.
  static Future<Map<String, String>> _fetchMessageVariables(
    String customerId,
  ) async {
    if (isNullOrEmpty(_apiKey)) return const <String, String>{};
    return fetchMessageVariablesRequest(
      customerId: customerId,
      apiKey: _apiKey,
      lang: handleLanguage(_lang, _customerPreferredLanguage),
      customApiPrefix: _apiPrefix,
      sessionToken: _sessionToken,
    );
  }

  static Future<GameballAnalyticsSendResult> _sendInAppMessageEvents(
    List<Map<String, dynamic>> events,
  ) async {
    final customerId = _inAppMessagingCustomerId;
    if (isNullOrEmpty(_apiKey) || customerId == null) {
      // Retry rather than discard: the events are valid, we just cannot address
      // them yet. They go out once init() and startInAppMessaging() have run.
      return GameballAnalyticsSendResult.retry;
    }

    return sendMessageEventsRequest(
      events,
      customerId: customerId,
      platform: getDevicePlatformCode(),
      apiKey: _apiKey,
      lang: handleLanguage(_lang, _customerPreferredLanguage),
      customApiPrefix: _apiPrefix,
      sessionToken: _sessionToken,
    );
  }

  /// Stops in-app messaging, dismissing anything on screen and clearing state.
  ///
  /// Call on logout. Safe to call when it was never started.
  void stopInAppMessaging() => _inAppMessaging?.stop();

  /// Forwards a foreground resume to in-app messaging. Called by the lifecycle
  /// observer; guarded so a host that never opted in is unaffected.
  static void notifyAppResumed() {
    try {
      _inAppMessaging?.onAppResumed();
    } catch (error) {
      iamLog('onAppResumed hook failed: $error');
    }
  }

  /// Forwards leaving the foreground to in-app messaging, so the time away can
  /// be measured against the session timeout.
  static void notifyAppPaused() {
    try {
      _inAppMessaging?.onAppPaused();
    } catch (error) {
      iamLog('onAppPaused hook failed: $error');
    }
  }

  /// Whether in-app messaging is currently running.
  bool get isInAppMessagingStarted => _inAppMessaging?.isStarted ?? false;

  /// The message waiting for a display opportunity, if any. Diagnostic.
  InAppMessageCampaign? get pendingInAppMessageCampaign =>
      _inAppMessaging?.pendingCampaign;

  /// Every in-app message the SDK selects for display.
  ///
  /// Observation only — the SDK owns impression and click logging, so there is
  /// no way to double-count from here. Safe to subscribe before
  /// [startInAppMessaging]. The controller is created on first access, so hosts
  /// that never listen pay nothing.
  Stream<GameballInAppMessage> get onInAppMessage =>
      (_inAppMessageController ??=
              StreamController<GameballInAppMessage>.broadcast())
          .stream;

  /// Displays the Gameball profile in a bottom sheet.
  ///
  /// This method validates the API key, stores the customer ID for widget display,
  /// and opens a modal bottom sheet containing the Gameball profile widget.
  ///
  /// Arguments:
  ///   - `context`: The build context for creating the customer profile widget.
  ///   - `request`: The ShowProfileRequest containing all profile display parameters.
  ///   - `sessionToken`: Optional session token for this request.
  ///                     If provided, overrides the global sessionToken.
  ///                     If not provided, nullifies the global sessionToken.
  void showProfile(BuildContext context, ShowProfileRequest request, {String? sessionToken}) {
    // Validate API key
    if (isNullOrEmpty(_apiKey)) {
      throw Exception('API key is not initialized. Call init() first');
    }

    // Override or nullify sessionToken based on parameter
    _sessionToken = sessionToken;

    // showProfile opens a webview (never hits the backend), so it is invisible server-side — log it here.
    // Full request as-is (toJson omits the externalLinkCallback).
    GameballLogger.instance.log('sdk.showProfile', params: request.toJson());

    _openCustomerProfileWidget(context, request);
  }

  /// Hides the currently shown profile widget. No-op when nothing is shown. Counterpart to [showProfile].
  void hideProfile() {
    _closeActiveWidget();
  }

  /// Dismisses the active widget dialog, if any. Backs both the widget-initiated
  /// window.GameballWidget.closeWidget() bridge and [hideProfile].
  static void _closeActiveWidget() {
    _dismissActiveWidget?.call();
  }

  void _nativeShare(String title, String text, String url) {
    final bodyText = text.isNotEmpty ? text : title;

    Share.share(
      bodyText,
      subject: title.isNotEmpty ? title : null,
    );
  }

  Future<void> _openExternalInAppBrowser(String url) async {
    try {
      final uri = Uri.parse(url);

      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication
      );
    } catch (e) {}
  }

  // Navigation handling — consumes every intercepted link (nothing loads in-widget):
  //   1) gbExternalBrowser=true → device browser (flag outranks the callback)
  //   2) else if externalLinkCallback set → delegate to it
  //   3) else → device browser
  bool _handleExternalBrowserLink(String url, ShowProfileRequest request) {
    if (url.contains('gbExternalBrowser=true')) {
      _openExternalInAppBrowser(url);
    } else if (request.externalLinkCallback != null) {
      request.externalLinkCallback!(url);
    } else {
      _openExternalInAppBrowser(url);
    }
    return true;
  }

  /// Opens a bottom sheet to display the Gameball profile.
  ///
  /// Creates a bottom sheet with a WebView displaying the Gameball profile based on the provided parameters.
  ///
  /// Arguments:
  ///   - `context`: The build context for creating the customer profile widget.
  ///   - `request`: The ShowProfileRequest containing all profile display parameters.
  void _openCustomerProfileWidget(BuildContext context, ShowProfileRequest request) {
    var widgetWebviewController = WebViewController();
    widgetWebviewController
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Android',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            // Handle both JSON format and pipe-separated format
            if (message.message.startsWith('{')) {
              // JSON format
              final data = json.decode(message.message);

              if (data['action'] == 'nativeShare') {
                final title = data['title'] ?? '';
                final text = data['text'] ?? '';
                final url = data['url'] ?? '';
                _nativeShare(title, text, url);
              }
            } else if (message.message.startsWith('nativeShare|')) {
              // Pipe-separated format
              final parts = message.message.split('|');
              if (parts.length >= 4) {
                final title = parts[1];
                final text = parts[2];
                final url = parts[3];
                _nativeShare(title, text, url);
              }
            } else {
              // Legacy format - assume it's JSON with direct share data
              final data = json.decode(message.message);
              final text = data['text'] ?? '';
              final title = data['title'] ?? '';
              final url = data['url'] ?? '';
              _nativeShare(title, text, url);
            }
          } catch (e) {}
        },
      )
      ..addJavaScriptChannel(
        'GBWidgetEvent',
        onMessageReceived: (JavaScriptMessage message) {
          // Widget → host events (e.g. game completion), posted via window.WidgetEvent.postEvent.
          final callback = request.widgetEventCallback;
          if (callback == null) return;
          try {
            final decoded = json.decode(message.message);
            if (decoded is Map<String, dynamic>) {
              callback(decoded, null);
            } else {
              callback(null, Exception('Unexpected widget event payload'));
            }
          } catch (e) {
            callback(null, e is Exception ? e : Exception(e.toString()));
          }
        },
      )
      ..addJavaScriptChannel(
        'GBWidgetClose',
        onMessageReceived: (JavaScriptMessage message) {
          // Widget-initiated close, posted via window.GameballWidget.closeWidget().
          _closeActiveWidget();
        },
      )
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {},
          onPageFinished: (String url) {
            // Inject JavaScript to override native share function
            widgetWebviewController.runJavaScript('''
            // Override the native share if it exists or create a polyfill
            if (typeof window.nativeShare === 'undefined') {
              window.nativeShare = function(title, text, url) {
                Android.postMessage('nativeShare|' + (title || '') + '|' + (text || '') + '|' + (url || ''));
              };
            }
            
            // Also support Web Share API polyfill
            if (!navigator.share) {
              navigator.share = function(params) {
                Android.postMessage(JSON.stringify({
                  action: 'nativeShare',
                  title: params.title || '',
                  text: params.text || '',
                  url: params.url || ''
                }));
                return Promise.resolve();
              };
            }

            // Bridge widget → host events onto the Flutter channel: the widget calls
            // window.WidgetEvent.postEvent(rawJson), which webview_flutter surfaces via postMessage.
            window.WidgetEvent = window.WidgetEvent || {};
            window.WidgetEvent.postEvent = function (raw) {
              GBWidgetEvent.postMessage(raw);
            };

            // Bridge widget-initiated close: window.GameballWidget.closeWidget() dismisses the widget.
            window.GameballWidget = window.GameballWidget || {};
            window.GameballWidget.closeWidget = function () {
              GBWidgetClose.postMessage('');
            };
          ''');
          },
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest navigationRequest) {
            if (_handleExternalBrowserLink(navigationRequest.url, request)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_buildWidgetUrl(request)));

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        // Track the active widget so window.GameballWidget.closeWidget() and hideProfile() can dismiss it.
        _dismissActiveWidget = () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        };
        String language = handleLanguage(_lang, _customerPreferredLanguage);

        return Dialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.95,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
                  child: Container(
                    height: MediaQuery.of(context).size.height, // Set bounded height for WebView
                    child: WebViewWidget(
                      controller: widgetWebviewController,
                    ),
                  ),
                ),
                if (request.showCloseButton ?? true)
                  Positioned(
                    top: 10.0,
                    left: isRtl(language) ? 10.0 : null,
                    right: isLtr(language) ? 10.0 : null,
                    child: IconButton(
                      icon: Icon(
                          Icons.close,
                          color: request.closeButtonColor != null
                              ? Color(int.parse(request.closeButtonColor!.replaceFirst('#', '0xFF')))
                              : const Color(0xFFCECECE)
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _dismissActiveWidget = null;
      // Additive: the screen is free again, so a deferred message may now be
      // presentable.
      try {
        _inAppMessaging?.onHostWidgetClosed();
      } catch (error) {
        iamLog('onHostWidgetClosed hook failed: $error');
      }
    });
  }

  /// Builds the URL for the Gameball profile widget.
  ///
  /// Constructs the URL based on the ShowProfileRequest parameters and SDK configuration.
  ///
  /// Arguments:
  ///   - `request`: The ShowProfileRequest containing widget configuration parameters.
  String _buildWidgetUrl(ShowProfileRequest request) {
    String language = handleLanguage(_lang, _customerPreferredLanguage);

    String widgetUrl = '${request.widgetUrlPrefix ?? widgetBaseUrl}?lang=$language';

    widgetUrl += '&apiKey=$_apiKey';

    widgetUrl += '&customerId=${request.customerId ?? ""}';

    if (!isNullOrEmpty(_platform)) {
      widgetUrl += '&platform=$_platform';
    }

    if (!isNullOrEmpty(_shop)) {
      widgetUrl += '&shop=$_shop';
    }

    widgetUrl += '&os=${getDevicePlatform()}';

    widgetUrl += '&sdk=Flutter-${getSdkVersion()}';

    if (!isNullOrEmpty(request.openDetail)) {
      widgetUrl += '&openDetail=${request.openDetail}';
    }

    if (request.hideNavigation != null) {
      widgetUrl += '&hideNavigation=${request.hideNavigation}';
    }

    if (!isNullOrEmpty(request.mobile)) {
      widgetUrl += '&mobile=${Uri.encodeComponent(request.mobile!)}';
    }

    if (!isNullOrEmpty(request.email)) {
      widgetUrl += '&email=${Uri.encodeComponent(request.email!)}';
    }

    if (!isNullOrEmpty(_sessionToken)) {
      widgetUrl += '&sessionToken=$_sessionToken';
    }

    return widgetUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

/// Turns app lifecycle changes into session boundaries for in-app messaging.
///
/// Separate from [GameballApp] because that class is a `StatelessWidget` and
/// cannot mix in [WidgetsBindingObserver]. Registered only once a host opts into
/// in-app messaging, so a client that never calls `startInAppMessaging` pays
/// nothing.
class _GameballLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        GameballApp.notifyAppResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        GameballApp.notifyAppPaused();
    }
  }
}
