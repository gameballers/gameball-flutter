import 'package:json_annotation/json_annotation.dart'
    show JsonKey, JsonSerializable;

part 'customer_attributes.g.dart';

/// Represents additional customer attributes to be sent during registration.
///
/// This class defines various optional customer attributes that can be included
/// with the customer registration request. These attributes can be used to
/// personalize the customer's experience within the Gameball platform.
@JsonSerializable(createFactory: false)
class CustomerAttributes {
  /// The customer's display name (optional).
  @JsonKey(name: "displayName")
  final String? displayName;

  /// The customer's first name (optional).
  @JsonKey(name: "firstName")
  final String? firstName;

  /// The customer's last name (optional).
  @JsonKey(name: "lastName")
  final String? lastName;

  /// The customer's email address (optional).
  @JsonKey(name: "email")
  final String? email;

  /// The customer's gender (optional).
  @JsonKey(name: "gender")
  final String? gender;

  /// The customer's mobile number (optional).
  @JsonKey(name: "mobile")
  final String? mobile;

  /// The customer's date of birth in a format suitable for the API (optional).
  @JsonKey(name: "dateOfBirth")
  final String? dateOfBirth;

  /// The customer's join date in a format suitable for the API (optional).
  @JsonKey(name: "joinDate")
  final String? joinDate;

  /// The customer's preferred language (optional).
  @JsonKey(name: "preferredLanguage")
  final String? preferredLanguage;

  /// The channel through which the customer joined (defaults to "mobile").
  @JsonKey(name: "channel")
  final String channel;

  /// A map containing additional custom customer attributes (optional).
  @JsonKey(name: "custom")
  final Map<String, String>? customAttributes;

  /// A map containing additional attributes that are not serialized to JSON.
  /// These attributes can be used for internal processing.
  @JsonKey(includeToJson: false, includeFromJson: false)
  final Map<String, String>? additionalAttributes;

  /// Private constructor for creating CustomerAttributes instances.
  /// Use [CustomerAttributesBuilder] to create instances of this class.
  const CustomerAttributes._({
    this.displayName,
    this.firstName,
    this.lastName,
    this.email,
    this.gender,
    this.mobile,
    this.dateOfBirth,
    this.joinDate,
    this.preferredLanguage,
    this.customAttributes,
    this.additionalAttributes,
  }) : channel = "mobile";

  /// Creates a copy with updated values.
  CustomerAttributes copyWith({
    String? displayName,
    String? firstName,
    String? lastName,
    String? email,
    String? gender,
    String? mobile,
    String? dateOfBirth,
    String? joinDate,
    String? preferredLanguage,
    Map<String, String>? customAttributes,
    Map<String, String>? additionalAttributes,
  }) {
    return CustomerAttributes._(
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      mobile: mobile ?? this.mobile,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      joinDate: joinDate ?? this.joinDate,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      customAttributes: customAttributes ?? this.customAttributes,
      additionalAttributes: additionalAttributes ?? this.additionalAttributes,
    );
  }

  /// Converts the `CustomerAttributes` object to a JSON map.
  ///
  /// This method merges additionalAttributes at the top level of the JSON,
  /// similar to the Android implementation's MapFromCustomerAttributes.
  /// Null values are automatically removed from the final JSON output.
  Map<String, dynamic> toJson() {
    // Start with the standard serialized fields
    final json = _$CustomerAttributesToJson(this);

    // Merge additionalAttributes at the top level
    if (additionalAttributes != null) {
      json.addAll(additionalAttributes!);
    }
    // Remove null values before sending
    json.removeWhere((key, value) => value == null);
    return json;
  }

  /// Create from JSON map.
  ///
  /// This method extracts standard fields and treats any remaining
  /// top-level fields as additionalAttributes, similar to Android's
  /// MapToCustomerAtrributes method.
  factory CustomerAttributes.fromJson(Map<String, dynamic> json) {
    final tempJson = Map<String, dynamic>.from(json);

    // Extract standard fields
    final displayName = tempJson.remove('displayName') as String?;
    final firstName = tempJson.remove('firstName') as String?;
    final lastName = tempJson.remove('lastName') as String?;
    final email = tempJson.remove('email') as String?;
    final gender = tempJson.remove('gender') as String?;
    final mobile = tempJson.remove('mobile') as String?;
    final dateOfBirth = tempJson.remove('dateOfBirth') as String?;
    final joinDate = tempJson.remove('joinDate') as String?;
    final preferredLanguage = tempJson.remove('preferredLanguage') as String?;
    final channel = tempJson.remove('channel') as String? ?? 'mobile';

    // Extract custom attributes
    final customAttributes = (tempJson.remove('custom') as Map<String, dynamic>?)?.map(
      (k, e) => MapEntry(k, e as String),
    );

    // Any remaining fields become additionalAttributes
    final additionalAttributes = tempJson.isNotEmpty
        ? tempJson.map((k, e) => MapEntry(k, e.toString()))
        : null;

    return CustomerAttributes._(
      displayName: displayName,
      firstName: firstName,
      lastName: lastName,
      email: email,
      gender: gender,
      mobile: mobile,
      dateOfBirth: dateOfBirth,
      joinDate: joinDate,
      preferredLanguage: preferredLanguage,
      customAttributes: customAttributes,
      additionalAttributes: additionalAttributes,
    );
  }
}

/// Builder for [CustomerAttributes].
///
/// Allows constructing attribute objects using a fluent API.
class CustomerAttributesBuilder {
  String? _displayName;
  String? _firstName;
  String? _lastName;
  String? _email;
  String? _gender;
  String? _mobile;
  String? _dateOfBirth;
  String? _joinDate;
  String? _preferredLanguage;
  Map<String, String>? _customAttributes;
  Map<String, String>? _additionalAttributes;

  CustomerAttributesBuilder displayName(String? displayName) {
    _displayName = displayName;
    return this;
  }

  CustomerAttributesBuilder firstName(String? firstName) {
    _firstName = firstName;
    return this;
  }

  CustomerAttributesBuilder lastName(String? lastName) {
    _lastName = lastName;
    return this;
  }

  CustomerAttributesBuilder email(String? email) {
    _email = email;
    return this;
  }

  CustomerAttributesBuilder gender(String? gender) {
    _gender = gender;
    return this;
  }

  CustomerAttributesBuilder mobile(String? mobile) {
    _mobile = mobile;
    return this;
  }

  CustomerAttributesBuilder dateOfBirth(String? dateOfBirth) {
    _dateOfBirth = dateOfBirth;
    return this;
  }

  CustomerAttributesBuilder joinDate(String? joinDate) {
    _joinDate = joinDate;
    return this;
  }

  CustomerAttributesBuilder preferredLanguage(String? preferredLanguage) {
    _preferredLanguage = preferredLanguage;
    return this;
  }

  CustomerAttributesBuilder addCustomAttribute(String key, String value) {
    _customAttributes ??= <String, String>{};
    _customAttributes![key] = value;
    return this;
  }

  CustomerAttributesBuilder customAttributes(Map<String, String>? attrs) {
    _customAttributes = attrs;
    return this;
  }

  CustomerAttributesBuilder addAdditionalAttribute(String key, String value) {
    _additionalAttributes ??= <String, String>{};
    _additionalAttributes![key.toLowerCase()] = value;
    return this;
  }

  CustomerAttributesBuilder additionalAttributes(Map<String, String>? attrs) {
    _additionalAttributes = attrs;
    return this;
  }

  CustomerAttributes build() {
    return CustomerAttributes._(
      displayName: _displayName,
      firstName: _firstName,
      lastName: _lastName,
      email: _email,
      gender: _gender,
      mobile: _mobile,
      dateOfBirth: _dateOfBirth,
      joinDate: _joinDate,
      preferredLanguage: _preferredLanguage,
      customAttributes: _customAttributes,
      additionalAttributes: _additionalAttributes,
    );
  }
}
