library gameball_sdk;

import 'package:gameball_sdk/network/request_calls/register_customer_request.dart';
import 'package:gameball_sdk/utils/gameball_utils.dart';
import 'package:gameball_sdk/utils/language_utils.dart';
import 'package:gameball_sdk/utils/platform_utils.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'models/requests/event.dart';
import 'models/requests/customer_attributes.dart';
import 'models/requests/initialize_customer_request.dart';
import 'network/models/callbacks.dart';
import 'network/request_calls/send_event_request.dart';

import 'network/utils/constants.dart';

class GameballApp extends StatelessWidget {
  static GameballApp? _instance;
  static String _apiKey = "";
  static String _customerId = "";
  static String _deviceToken = "";
  static String _lang = "";
  static String? _platform;
  static String? _shop;
  static String? _customerPreferredLanguage;
  static String? _customerEmail;
  static String? _customerMobile;
  static bool? _isGuest;
  static String? _referralCode;
  static String? _openDetail;
  static bool? _hideNavigation;
  static bool _showCloseButton = true;

  /// Retrieves the singleton instance of the GameballApp class.
  ///
  /// Creates a new instance if it doesn't exist and returns it.
  static GameballApp getInstance() {
    _instance ??= GameballApp();
    return _instance!;
  }

  /// Initializes the Gameball SDK with required parameters.
  ///
  /// Sets the API key, language, platform, and shop information for subsequent SDK operations.
  void init(String apiKey, String lang, String? platform, String? shop) {
    _lang = lang;
    _platform = platform;
    _shop = shop;
    _apiKey = apiKey;
  }

  /// Initializes Firebase Messaging and retrieves the device token.
  ///
  /// This method fetches the device token from Firebase Messaging and stores it
  /// in the `_deviceToken` property for later use.
  _initializeFirebase() {
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        _deviceToken = token;
      }
    });
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
  Future<void> _handleDynamicLink(ReferralCodeCallback callback) async {
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

  /// Registers a customer with Gameball.
  ///
  /// This method initiates the customer registration process, including fetching the device token, handling referral codes, and sending the registration request.
  ///
  /// Arguments:
  ///   - `customerId`: The unique identifier for the customer.
  ///   - `customerEmail`: The customer's email address (optional).
  ///   - `customerMobile`: The customer's mobile number (optional).
  ///   - `isGuest`: The customer's state whether a guest or not (optional).
  ///   - `customerAttributes`: Additional customer attributes.
  ///   - `responseCallback`: A callback function to handle the registration response.
  Future<void> registerCustomer(
    String customerId,
    String? customerEmail,
    String? customerMobile,
    bool? isGuest,
    CustomerAttributes? customerAttributes,
    RegisterCallback? responseCallback,
  ) async {
    _customerId = customerId.trim();

    if (isNullOrEmpty(_customerId) || isNullOrEmpty(_apiKey)) {
      responseCallback!(null, null);
      return;
    }

    _initializeFirebase();

    referralCodeRegistrationCallback(response, error) {
      if (error == null && response != null) {
        _referralCode = response;
      }
    }

    await _handleDynamicLink(referralCodeRegistrationCallback)
        .then((response) {});

    final email = customerEmail?.trim();
    final mobile = customerMobile?.trim();

    if (!isNullOrEmpty(email)) {
      _customerEmail = email;
    }

    if (!isNullOrEmpty(mobile)) {
      _customerMobile = mobile;
    }

    if (customerAttributes?.preferredLanguage != null &&
        customerAttributes?.preferredLanguage?.length == 2) {
      _customerPreferredLanguage = customerAttributes?.preferredLanguage;
    }

    if(isGuest == null){
      _isGuest = false;
    }else{
      _isGuest = isGuest;
    }
    
    _registerDevice(customerAttributes, responseCallback);
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
    InitializeCustomerRequest customerRegisterRequest = InitializeCustomerRequest(
        customerId: _customerId,
        deviceToken: _deviceToken,
        email: _customerEmail,
        mobileNumber: _customerMobile,
        customerAttributes: customerAttributes,
        referrerCode: _referralCode,
        isGuest: _isGuest);

    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      registerCustomerRequest(customerRegisterRequest, _apiKey, language)
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
  ///   - `eventBody`: The event data to be sent.
  ///   - `callback`: The callback function to handle the event sending result.s
  void sendEvent(Event eventBody, SendEventCallback? callback) {
    try {
      String language = handleLanguage(_lang, _customerPreferredLanguage);
      sendEventRequest(eventBody, _apiKey, language).then((response) {
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
  ///   - `customerId`: The unique identifier of the customer.
  ///   - `openDetail`: An optional URL to open within the profile.
  ///   - `hideNavigation`: An optional flag to indicate if the navigation bar should be hidden.
  ///   - `showCloseButton`: An optional flag to control the visibility of a close button, Defaulted to always show.
  void showProfile(BuildContext context, String customerId,
      String? openDetail, bool? hideNavigation, bool? showCloseButton) {
    _customerId = customerId;
    _openDetail = openDetail;
    _hideNavigation = hideNavigation;
    if(showCloseButton != null){
      _showCloseButton = showCloseButton;
    }
    _openCustomerProfileWidget(context);
  }

  /// Opens a bottom sheet to display the Gameball profile.
  ///
  /// Creates a bottom sheet with a WebView displaying the Gameball profile based on the provided parameters.
  ///
  /// Arguments:
  ///   - `context`: The build context for creating the customer profile widget.
  void _openCustomerProfileWidget(BuildContext context) {
    var widgetWebviewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          insetPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
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
                      icon: const Icon(Icons.close),
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

    String widgetUrl = widgetBaseUrl;

    widgetUrl += '&playerid=$_customerId';

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
