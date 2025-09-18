// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_attributes.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CustomerAttributes _$CustomerAttributesFromJson(Map<String, dynamic> json) =>
    CustomerAttributes(
      displayName: json['displayName'] as String?,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      email: json['email'] as String?,
      gender: json['gender'] as String?,
      mobileNumber: json['mobile'] as String?,
      dateOfBirth: json['dateOfBirth'] as String?,
      joinDate: json['joinDate'] as String?,
      preferredLanguage: json['preferredLanguage'] as String?,
      channel: json['channel'] as String? ?? 'mobile',
      city: json['city'] as String? ?? 'mobile',
      country: json['country'] as String? ?? 'mobile',
      customAttributes: (json['custom'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
    );

Map<String, dynamic> _$CustomerAttributesToJson(CustomerAttributes instance) =>
    <String, dynamic>{
      'displayName': instance.displayName,
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'email': instance.email,
      'gender': instance.gender,
      'mobile': instance.mobileNumber,
      'dateOfBirth': instance.dateOfBirth,
      'joinDate': instance.joinDate,
      'preferredLanguage': instance.preferredLanguage,
      'channel': instance.channel,
      'city': instance.city,
      'country': instance.country,
      'custom': instance.customAttributes,
    };
