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
  @JsonKey(name: "channel", defaultValue: "mobile")
  final String? channel;

  /// A map containing additional custom customer attributes (optional).
  @JsonKey(name: "custom")
  final Map<String, String>? customAttributes;

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
    this.channel,
    this.customAttributes,
  });

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
    String? channel,
    Map<String, String>? customAttributes,
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
      channel: channel ?? this.channel,
      customAttributes: customAttributes ?? this.customAttributes,
    );
  }

  /// Converts the `CustomerAttributes` object to a JSON map.
  ///
  /// This method is typically used internally by the `json_serializable` package.
  Map<String, dynamic> toJson() => _$CustomerAttributesToJson(this);

  /// Create from JSON map.
  factory CustomerAttributes.fromJson(Map<String, dynamic> json) => CustomerAttributes._(
        displayName: json['displayName'] as String?,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        email: json['email'] as String?,
        gender: json['gender'] as String?,
        mobile: json['mobile'] as String?,
        dateOfBirth: json['dateOfBirth'] as String?,
        joinDate: json['joinDate'] as String?,
        preferredLanguage: json['preferredLanguage'] as String?,
        channel: json['channel'] as String? ?? 'mobile',
        customAttributes: (json['custom'] as Map<String, dynamic>?)?.map(
          (k, e) => MapEntry(k, e as String),
        ),
      );
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
    );
  }
}
