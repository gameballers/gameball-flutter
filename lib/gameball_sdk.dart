library gameball_sdk;

import 'dart:convert';

import 'package:gameball_sdk/network/request_calls/initialize_customer_request.dart';
import 'package:gameball_sdk/utils/gameball_utils.dart';
import 'package:gameball_sdk/utils/language_utils.dart';
import 'package:gameball_sdk/utils/platform_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'models/requests/event.dart';
import 'models/requests/customer_attributes.dart';
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
  static String _customerId = "";
  static String _deviceToken = "";
  static String _pushProvider = "";
  static String _lang = "";
  static String? _platform;
  static String? _shop;
  static String? _customerPreferredLanguage;
  static String? _apiPrefix;
  static String? _customerEmail;
  static String? _customerMobile;
  static bool? _isGuest;
  static String? _referralCode;
  static String? _openDetail;
  static bool? _hideNavigation;
  static bool _showCloseButton = true;
  static String? _widgetUrlPrefix;

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

  /// Initializes Firebase Messaging and retrieves the device token.
  ///
  /// This method fetches the device token from Firebase Messaging and stores it
  /// in the `_deviceToken` property for later use with the `_pushProvider` variable.
  initializeFirebase() {
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        _deviceToken = token;
        _pushProvider = "Firebase";
      }
    });
  }
  /// Initializes Huawei push kit device token
  ///
  /// This method sets the device token and stores it
  /// in the `_deviceToken` property for later use with the `_pushProvider` variable.
  initializeHuawei(String deviceToken) {
    _deviceToken = deviceToken;
    _pushProvider = "Huawei";
  }

  /// Handles incoming Firebase Dynamic Links containing potential referral codes.
  ///
  /// This method retrieves any pending dynamic link upon app launch and checks
  /// if it contains a `GBReferral` query parameter. If a referral code is found,
  /// it invokes the provided callback function with the extracted code. Otherwise,
  /// the callback is called with `null` for both the referral code and any error.
  ///
  /// This method is typically used in conjunction with registering a listener
  /// for dynamic links to handle referrals throughout the app's lifecycle.
  Future<void> handleFirebaseDynamicLink(ReferralCodeCallback callback) async {
    final PendingDynamicLinkData? data =
        await FirebaseDynamicLinks.instance.getInitialLink();

    if (data != null) {
      final Uri deepLink = data.link;
      final referralCode = deepLink.queryParameters['GBReferral'];
      callback(referralCode, null);
    } else {
      callback(null, null);
    }
  }

  /// Initializes a customer using a pre-built [InitializeCustomerRequest].
  ///
  /// This provides a builder-pattern friendly API where the caller
  /// constructs an [InitializeCustomerRequest] using
  /// [InitializeCustomerRequestBuilder] and passes it here.
  ///
  /// Arguments:
  ///   - `request`: The InitializeCustomerRequest containing all customer initialization parameters.
  ///   - `responseCallback`: A callback function to handle the registration response.
  Future<void> initializeCustomer(
    InitializeCustomerRequest request,
    RegisterCallback? responseCallback,
  ) async {
    _customerId = request.customerId.trim();

    if (isNullOrEmpty(_customerId) || isNullOrEmpty(_apiKey)) {
      responseCallback!(null, null);
      return;
    }

    _deviceToken = request.deviceToken ?? '';
    if (request.pushProvider != null) {
      _pushProvider = request.pushProvider!;
    }

    final email = request.email?.trim();
    final mobile = request.mobile?.trim();

    if (!isNullOrEmpty(email)) {
      _customerEmail = email;
    }

    if (!isNullOrEmpty(mobile)) {
      _customerMobile = mobile;
    }

    if (!isNullOrEmpty(request.referralCode)) {
      _referralCode = request.referralCode;
    }

    if (request.customerAttributes?.preferredLanguage != null &&
        request.customerAttributes?.preferredLanguage?.length == 2) {
      _customerPreferredLanguage = request.customerAttributes?.preferredLanguage;
    }

    if(request.isGuest == null){
      _isGuest = false;
    }else{
      _isGuest = request.isGuest;
    }
    
    _registerDevice(request.customerAttributes, responseCallback);
  }

  /// Registers the device with Gameball using the provided customer attributes.
  ///
  /// This method constructs a `customerRegisterRequest` object and sends it to the Gameball API.
  /// The callback is invoked with the response or any encountered error.
  ///
  /// Arguments:
  ///   - `customerAttributes`: Optional customer attributes to include in the request.
  ///   - `callback`: The callback function to handle the registration result.
  void _registerDevice(
      CustomerAttributes? customerAttributes, RegisterCallback? callback) {
    InitializeCustomerRequest customerRegisterRequest =
        InitializeCustomerRequestBuilder()
            .customerId(_customerId)
            .deviceToken(_deviceToken.isEmpty ? null : _deviceToken)
            .email(_customerEmail)
            .mobile(_customerMobile)
            .customerAttributes(customerAttributes)
            .referralCode(_referralCode)
            .isGuest(_isGuest)
            .pushProvider(_pushProvider)
            .build();
    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      initializeCustomerRequest(customerRegisterRequest, _apiKey, language, customApiPrefix: _apiPrefix)
          .then((response) {
        if (response != null) {
          callback!(response, null);
        } else {
          callback!(null, null);
        }
      });
    } catch (e) {
      callback!(null, e as Exception);
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
  /// This method initiates the process of showing the Gameball profile within a bottom sheet.
  ///
  /// Arguments:
  ///   - `context`: The build context for creating the customer profile widget.
  ///   - `request`: The ShowProfileRequest containing all profile display parameters.
  void showProfile(BuildContext context, ShowProfileRequest request) {
    _customerId = request.customerId;
    _openDetail = request.openDetail;
    _hideNavigation = request.hideNavigation;
    _widgetUrlPrefix = request.widgetUrlPrefix;
    if(request.showCloseButton != null){
      _showCloseButton = request.showCloseButton!;
    }
    _openCustomerProfileWidget(context);
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
  void _openCustomerProfileWidget(BuildContext context) {
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
      ..loadRequest(Uri.parse(_buildWidgetUrl()));

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
                if (_showCloseButton)
                  Positioned(
                    top: 10.0,
                    left: isRtl(language) ? 10.0 : null,
                    right: isLtr(language) ? 10.0 : null,
                    child: IconButton(
                      icon: const Icon(
                          Icons.close,
                          color: Color(0xFFCECECE)
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
  /// Constructs the URL based on the provided parameters and returns it.
  String _buildWidgetUrl() {
    String language = handleLanguage(_lang, _customerPreferredLanguage);

    String widgetUrl = '${_widgetUrlPrefix ?? widgetBaseUrl}?';

    widgetUrl += 'playerid=$_customerId';

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

    if (!isNullOrEmpty(_openDetail)) {
      widgetUrl += '&openDetail=$_openDetail';
    }

    if (_hideNavigation != null) {
      widgetUrl += '&hideNavigation=$_hideNavigation';
    }

    return widgetUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
