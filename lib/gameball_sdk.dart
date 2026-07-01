library gameball_sdk;

import 'dart:convert';

import 'package:gameball_sdk/network/request_calls/initialize_customer_request.dart';
import 'package:gameball_sdk/utils/gameball_utils.dart';
import 'package:gameball_sdk/utils/gameball_logger.dart';
import 'package:gameball_sdk/utils/language_utils.dart';
import 'package:gameball_sdk/utils/platform_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';

import 'models/requests/event.dart';
import 'models/requests/initialize_customer_request.dart';
import 'models/requests/show_profile_request.dart';
import 'models/requests/gameball_config.dart';
import 'network/models/callbacks.dart';
import 'network/request_calls/send_event_request.dart';

import 'network/utils/constants.dart';

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
  }

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
      widgetUrl += '&platform=$_shop';
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
