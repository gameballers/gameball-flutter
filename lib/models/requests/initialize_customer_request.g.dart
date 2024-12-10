// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'initialize_customer_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InitializeCustomerRequest _$InitializeCustomerRequestFromJson(
        Map<String, dynamic> json) =>
    InitializeCustomerRequest(
      customerId: json['customerId'] as String,
      deviceToken: json['deviceToken'] as String,
      osType: json['osType'] as String?,
      customerAttributes: json['customerAttributes'] == null
          ? null
          : CustomerAttributes.fromJson(
              json['customerAttributes'] as Map<String, dynamic>),
      referrerCode: json['referrerCode'] as String?,
      email: json['email'] as String?,
      mobileNumber: json['mobile'] as String?,
      isGuest: json['guest'] as bool?,
    );

Map<String, dynamic> _$InitializeCustomerRequestToJson(
        InitializeCustomerRequest instance) =>
    <String, dynamic>{
      'customerId': instance.customerId,
      'deviceToken': instance.deviceToken,
      'osType': instance.osType,
      'customerAttributes': instance.customerAttributes,
      'referrerCode': instance.referrerCode,
      'email': instance.email,
      'mobile': instance.mobileNumber,
      'guest': instance.isGuest,
    };
