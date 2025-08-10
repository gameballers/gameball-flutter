import 'package:json_annotation/json_annotation.dart'
    show JsonKey, JsonSerializable;

import '../../utils/platform_utils.dart';
import 'customer_attributes.dart';

part 'initialize_customer_request.g.dart';

/// Represents the data structure for a customer registration request to the Gameball API.
///
/// This class defines the properties required to register a customer with the Gameball platform.
/// It includes essential information for identifying the customer, as well as optional details
/// to enrich their profile and personalize their experience.
@JsonSerializable(createFactory: false)
class InitializeCustomerRequest {
  /// The unique identifier for the customer (required).
  ///
  /// This identifier should uniquely identify the customer within your application and persist
  /// across device changes or app re-installs. You are responsible for generating
  /// and managing this unique Id.
  @JsonKey(name: "customerId")
  final String customerId;

  /// The customer's device token for push notifications (optional).
  ///
  /// This token is used by Gameball to send push notifications to the customer's device.
  /// You'll need to implement a mechanism to obtain the device token from your
  /// platform-specific notification framework (e.g., Firebase Cloud Messaging or Apple Push Notification service).
  @JsonKey(name: "deviceToken")
  final String? deviceToken;

  /// The operating system type of the customer's device (automatically set).
  ///
  /// This value is automatically determined based on the current platform (iOS, Android, or other)
  /// and is included in the registration request for informational purposes.
  @JsonKey(name: "osType")
  final String osType;

  /// Additional customer attributes to be sent during registration (optional).
  ///
  /// This can include details such as the customer's display name, email address, mobile number,
  /// date of birth, and custom attributes specific to your application. These attributes can
  /// be used by Gameball to personalize the customer's experience within the platform.
  @JsonKey(name: "customerAttributes")
  final CustomerAttributes? customerAttributes;

  /// A referral code associated with the customer (optional).
  ///
  /// If a referral code is provided, it can be used to track referrals and potentially offer
  /// rewards to both the referring and referred customers.
  @JsonKey(name: "referrerCode")
  final String? referralCode;

  /// The customer's email address (optional).
  ///
  /// You can include the customer's email address if you plan to use email-based communication
  /// or for other purposes within your application.
  @JsonKey(name: "email")
  final String? email;

  /// The customer's mobile number (optional).
  ///
  /// You can include the customer's mobile number if you plan to use SMS-based communication
  /// or for other purposes within your application.
  @JsonKey(name: "mobile")
  final String? mobile;

  /// A flag indicating if the individual interacting with your system is a guest (not signed up).
  ///
  /// Set to `true` for guest users. If `false` or omitted, the individual is treated
  /// as a registered customer by default.
  @JsonKey(name: "guest")
  final bool? isGuest;

  @JsonKey(name: "pushServiceProvider")
  final String? pushProvider;

  /// Private constructor for creating InitializeCustomerRequest instances.
  /// Use [InitializeCustomerRequestBuilder] to create instances of this class.
  InitializeCustomerRequest._({
    required this.customerId,
    this.deviceToken,
    this.customerAttributes,
    this.referralCode,
    this.email,
    this.mobile,
    this.isGuest,
    this.pushProvider,
  }) : osType = getDevicePlatform();


  /// Converts the `InitializeCustomerRequest` object to a JSON map.
  ///
  /// This method is typically used internally by the `json_serializable` package
  /// to serialize the object before sending it to the Gameball API.
  Map<String, dynamic> toJson() => _$InitializeCustomerRequestToJson(this);

  /// Create from JSON map.
  factory InitializeCustomerRequest.fromJson(Map<String, dynamic> json) => InitializeCustomerRequest._(
        customerId: json['customerId'] as String,
        deviceToken: json['deviceToken'] as String?,
        customerAttributes: json['customerAttributes'] == null
            ? null
            : CustomerAttributes.fromJson(json['customerAttributes'] as Map<String, dynamic>),
        referralCode: json['referrerCode'] as String?,
        email: json['email'] as String?,
        mobile: json['mobile'] as String?,
        isGuest: json['guest'] as bool?,
        pushProvider: json['pushServiceProvider'] as String?,
      );
}

/// Builder class for [InitializeCustomerRequest].
///
/// Provides a fluent API similar to the Android SDK while keeping the
/// original request object immutable.
class InitializeCustomerRequestBuilder {
  String? _customerId;
  String? _deviceToken;
  CustomerAttributes? _customerAttributes;
  String? _referralCode;
  String? _email;
  String? _mobile;
  bool? _isGuest;
  String? _pushProvider;

  /// Set the required customer id.
  InitializeCustomerRequestBuilder customerId(String customerId) {
    _customerId = customerId;
    return this;
  }

  /// Set the optional device token.
  InitializeCustomerRequestBuilder deviceToken(String? deviceToken) {
    _deviceToken = deviceToken;
    return this;
  }


  /// Provide extra customer attributes.
  InitializeCustomerRequestBuilder customerAttributes(
      CustomerAttributes? attributes) {
    _customerAttributes = attributes;
    return this;
  }

  /// Set a referral code.
  InitializeCustomerRequestBuilder referralCode(String? code) {
    _referralCode = code;
    return this;
  }

  /// Provide customer email.
  InitializeCustomerRequestBuilder email(String? email) {
    _email = email;
    return this;
  }

  /// Provide customer mobile number.
  InitializeCustomerRequestBuilder mobile(String? mobile) {
    _mobile = mobile;
    return this;
  }

  /// Specify whether the customer is a guest.
  InitializeCustomerRequestBuilder isGuest(bool? isGuest) {
    _isGuest = isGuest;
    return this;
  }

  /// Specify the push provider used to obtain the device token.
  InitializeCustomerRequestBuilder pushProvider(String? provider) {
    _pushProvider = provider;
    return this;
  }

  /// Build the final immutable [InitializeCustomerRequest] instance.
  InitializeCustomerRequest build() {
    if (_customerId == null || _customerId!.isEmpty) {
      throw ArgumentError('Customer ID cannot be empty');
    }
    return InitializeCustomerRequest._(
      customerId: _customerId!,
      deviceToken: _deviceToken,
      customerAttributes: _customerAttributes,
      referralCode: _referralCode,
      email: _email,
      mobile: _mobile,
      isGuest: _isGuest ?? false,
      pushProvider: _pushProvider,
    );
  }
}
