import 'package:json_annotation/json_annotation.dart';

part 'show_profile_request.g.dart';

/// Represents the parameters for showing the Gameball profile.
///
/// This class encapsulates all the parameters needed to display the customer profile
/// widget with customizable options for navigation and detail views.
@JsonSerializable(createFactory: false)
class ShowProfileRequest {
  /// The unique identifier for the customer (optional for guest view).
  @JsonKey(name: "customerId")
  final String? customerId;

  /// An optional URL to open within the profile.
  @JsonKey(name: "openDetail")
  final String? openDetail;

  /// An optional flag to indicate if the navigation bar should be hidden.
  @JsonKey(name: "hideNavigation")
  final bool? hideNavigation;

  /// An optional flag to control the visibility of a close button.
  @JsonKey(name: "showCloseButton")
  final bool? showCloseButton;

  /// An optional custom URL prefix for the widget.
  @JsonKey(name: "widgetUrlPrefix")
  final String? widgetUrlPrefix;

  /// An optional color for the close button.
  @JsonKey(name: "closeButtonColor")
  final String? closeButtonColor;

  /// An optional customer mobile number.
  @JsonKey(name: "mobile")
  final String? mobile;

  /// An optional customer email address.
  @JsonKey(name: "email")
  final String? email;

  /// Private constructor for creating ShowProfileRequest instances.
  /// Use [ShowProfileRequestBuilder] to create instances of this class.
  const ShowProfileRequest._({
    this.customerId,
    this.openDetail,
    this.hideNavigation,
    this.showCloseButton,
    this.widgetUrlPrefix,
    this.closeButtonColor,
    this.mobile,
    this.email,
  });


  /// Converts the `ShowProfileRequest` object to a JSON map.
  ///
  /// This method is typically used internally by the `json_serializable` package.
  Map<String, dynamic> toJson() => _$ShowProfileRequestToJson(this);

  /// Create from JSON map.
  factory ShowProfileRequest.fromJson(Map<String, dynamic> json) => ShowProfileRequest._(
        customerId: json['customerId'] as String?,
        openDetail: json['openDetail'] as String?,
        hideNavigation: json['hideNavigation'] as bool?,
        showCloseButton: json['showCloseButton'] as bool?,
        widgetUrlPrefix: json['widgetUrlPrefix'] as String?,
        closeButtonColor: json['closeButtonColor'] as String?,
        mobile: json['mobile'] as String?,
        email: json['email'] as String?,
      );
}

/// Builder class for [ShowProfileRequest].
///
/// Provides a fluent API for constructing ShowProfileRequest instances.
class ShowProfileRequestBuilder {
  String? _customerId;
  String? _openDetail;
  bool? _hideNavigation;
  bool? _showCloseButton;
  String? _widgetUrlPrefix;
  String? _closeButtonColor;
  String? _mobile;
  String? _email;

  /// Set the optional customer id.
  ShowProfileRequestBuilder customerId(String? customerId) {
    _customerId = customerId;
    return this;
  }

  /// Set the optional detail URL to open.
  ShowProfileRequestBuilder openDetail(String? openDetail) {
    _openDetail = openDetail;
    return this;
  }

  /// Set whether to hide navigation.
  ShowProfileRequestBuilder hideNavigation(bool? hideNavigation) {
    _hideNavigation = hideNavigation;
    return this;
  }

  /// Set whether to show close button.
  ShowProfileRequestBuilder showCloseButton(bool? showCloseButton) {
    _showCloseButton = showCloseButton;
    return this;
  }

  /// Set the optional custom widget URL prefix.
  ShowProfileRequestBuilder widgetUrlPrefix(String? widgetUrlPrefix) {
    _widgetUrlPrefix = widgetUrlPrefix;
    return this;
  }

  /// Set the optional close button color.
  ShowProfileRequestBuilder closeButtonColor(String? closeButtonColor) {
    _closeButtonColor = closeButtonColor;
    return this;
  }

  /// Set the optional customer mobile number.
  ShowProfileRequestBuilder mobile(String? mobile) {
    _mobile = mobile;
    return this;
  }

  /// Set the optional customer email address.
  ShowProfileRequestBuilder email(String? email) {
    _email = email;
    return this;
  }

  /// Build the final immutable [ShowProfileRequest] instance.
  ShowProfileRequest build() {
    return ShowProfileRequest._(
      customerId: _customerId,
      openDetail: _openDetail,
      hideNavigation: _hideNavigation,
      showCloseButton: _showCloseButton,
      widgetUrlPrefix: _widgetUrlPrefix,
      closeButtonColor: _closeButtonColor,
      mobile: _mobile,
      email: _email,
    );
  }
}