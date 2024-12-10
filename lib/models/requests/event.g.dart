// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Event _$EventFromJson(Map<String, dynamic> json) => Event(
      events: (json['events'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(
            k,
            (e as Map<String, dynamic>).map(
              (k, e) => MapEntry(k, e as Object),
            )),
      ),
      customerId: json['customerId'] as String,
      mobileNumber: json['mobile'] as String?,
      email: json['email'] as String?,
    );

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
      'events': instance.events,
      'customerId': instance.customerId,
      'mobile': instance.mobileNumber,
      'email': instance.email,
    };
