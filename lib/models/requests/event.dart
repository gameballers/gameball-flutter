import 'package:json_annotation/json_annotation.dart';

part 'event.g.dart';

/// Represents an event to be sent to the Gameball API.
///
/// This class defines the structure of an event object with properties
/// for event data, customer Id, optional mobile number, and optional email.
@JsonSerializable(createFactory: false)
class Event {
  /// A map containing the actual event data.
  /// The key represents the event type, and the value is a map containing additional event-specific data.
  @JsonKey(name: "events")
  final Map<String, Map<String, Object>> events;

  /// The unique identifier of the customer associated with the event.
  @JsonKey(name: "customerId")
  final String customerId;

  /// The customer's mobile number (optional).
  @JsonKey(name: "mobile")
  final String? mobile;

  /// The customer's email address (optional).
  @JsonKey(name: "email")
  final String? email;

  /// Private constructor for creating Event instances.
  /// Use [EventBuilder] to create instances of this class.
  const Event._({
    required this.events,
    required this.customerId,
    this.mobile,
    this.email,
  });


  /// Converts the `Event` object to a JSON map.
  ///
  /// This method is typically used internally by the `json_serializable` package.
  /// Null values are automatically removed from the final JSON output.
  Map<String, dynamic> toJson() {
    final json = _$EventToJson(this);
    // Remove null values before sending
    json.removeWhere((key, value) => value == null);
    return json;
  }

  /// Create from JSON map.
  factory Event.fromJson(Map<String, dynamic> json) => Event._(
        events: (json['events'] as Map<String, dynamic>).map(
          (k, e) => MapEntry(k, Map<String, Object>.from(e as Map)),
        ),
        customerId: json['customerId'] as String,
        mobile: json['mobile'] as String?,
        email: json['email'] as String?,
      );
}

/// Builder for [Event].
class EventBuilder {
  final Map<String, Map<String, Object>> _events =
      <String, Map<String, Object>>{};
  String? _customerId;
  String? _mobile;
  String? _email;
  String? _currentEventName;

  EventBuilder customerId(String id) {
    _customerId = id;
    return this;
  }

  EventBuilder mobile(String? mobile) {
    _mobile = mobile;
    return this;
  }

  EventBuilder email(String? email) {
    _email = email;
    return this;
  }

  /// Sets the current event name. Must be called before adding metadata.
  EventBuilder eventName(String? eventName) {
    _currentEventName = eventName;
    if (eventName != null && _events[eventName] == null) {
      _events[eventName] = <String, Object>{};
    }
    return this;
  }

  /// Adds metadata for the current event name.
  /// Event name must be set before calling this method.
  EventBuilder eventMetaData(String key, Object value) {
    if (_currentEventName == null) {
      throw ArgumentError('Event name must be set before adding metadata');
    }
    _events[_currentEventName]?[key] = value;
    return this;
  }

  Event build() {
    if (_customerId == null || _customerId!.isEmpty) {
      throw ArgumentError('Customer ID cannot be empty');
    }
    if (_events.isEmpty) {
      throw ArgumentError('At least one event must be specified');
    }
    return Event._(
      events: Map<String, Map<String, Object>>.from(_events),
      customerId: _customerId!,
      mobile: _mobile,
      email: _email,
    );
  }
}
