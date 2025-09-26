library gameball_sdk;

import 'dart:convert';

import 'package:gameball_sdk/network/request_calls/initialize_customer_request.dart';
import 'package:gameball_sdk/utils/gameball_utils.dart';
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
  }

  /// Initializes a customer using a pre-built [InitializeCustomerRequest].
  ///
  /// This method validates the API key, stores essential customer data for widget display,
  /// and sends the complete request to the Gameball API for customer registration.
  ///
  /// Arguments:
  ///   - `request`: The InitializeCustomerRequest containing all customer initialization parameters.
  ///   - `responseCallback`: A callback function to handle the registration response.
  Future<void> initializeCustomer(
    InitializeCustomerRequest request,
    RegisterCallback? responseCallback,
  ) async {
    // Validate API key
    if (isNullOrEmpty(_apiKey)) {
      responseCallback!(null, Exception('API key is not initialized. Call init() first'));
      return;
    }


    // Store customer preferred language for widget display
    if (request.customerAttributes?.preferredLanguage != null &&
        request.customerAttributes?.preferredLanguage?.length == 2) {
      _customerPreferredLanguage = request.customerAttributes?.preferredLanguage;
    }

    // Send request to Gameball API
    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      initializeCustomerRequest(request, _apiKey, language, customApiPrefix: _apiPrefix)
          .then((response) {
        responseCallback!(response, null);
      });
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
  ///   - `callback`: The callback function to handle the event sending result.s
  void sendEvent(Event event, SendEventCallback? callback) {
    // Validate API key
    if (isNullOrEmpty(_apiKey)) {
      callback!(null, Exception('API key is not initialized. Call init() first'));
      return;
    }

    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      sendEventRequest(event, _apiKey, language, customApiPrefix: _apiPrefix).then((response) {
        if (response.statusCode == 200) {
          callback!(true, null);
        } else {
          callback!(false, null);
        }
      });
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
  void showProfile(BuildContext context, ShowProfileRequest request) {
    // Validate API key
    if (isNullOrEmpty(_apiKey)) {
      throw Exception('API key is not initialized. Call init() first');
    }

    _openCustomerProfileWidget(context, request);
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
          ''');
          },
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.parse(request.url);
            final widgetHost = Uri.parse(widgetBaseUrl).host;
            final isExternal = request.url.isNotEmpty && !uri.host.contains(widgetHost);
            if (isExternal) {
              _openExternalInAppBrowser(request.url);
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
    );
  }

  /// Builds the URL for the Gameball profile widget.
  ///
  /// Constructs the URL based on the ShowProfileRequest parameters and SDK configuration.
  ///
  /// Arguments:
  ///   - `request`: The ShowProfileRequest containing widget configuration parameters.
  String _buildWidgetUrl(ShowProfileRequest request) {
    String language = handleLanguage(_lang, _customerPreferredLanguage);

    String widgetUrl = '${request.widgetUrlPrefix ?? widgetBaseUrl}?';

    widgetUrl += 'playerid=${request.customerId}';

    widgetUrl += '&lang=$language';

    widgetUrl += '&apiKey=$_apiKey';

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

    return widgetUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
