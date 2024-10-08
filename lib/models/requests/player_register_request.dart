import 'package:json_annotation/json_annotation.dart'
    show JsonKey, JsonSerializable;

import '../../utils/platform_utils.dart';
import 'player_attributes.dart';

part 'player_register_request.g.dart';

/// Represents the data structure for a player registration request to the Gameball API.
///
/// This class defines the properties required to register a player with the Gameball platform.
/// It includes essential information for identifying the player, as well as optional details
/// to enrich their profile and personalize their experience.
@JsonSerializable()
class PlayerRegisterRequest {
  /// The unique identifier for the player (required).
  ///
  /// This ID should uniquely identify the player within your application and persist
  /// across device changes or app reinstalls. You are responsible for generating
  /// and managing this unique ID.
  @JsonKey(name: "playerUniqueId")
  String playerUniqueID;

  /// The player's device token for push notifications (required).
  ///
  /// This token is used by Gameball to send push notifications to the player's device.
  /// You'll need to implement a mechanism to obtain the device token from your
  /// platform-specific notification framework (e.g., Firebase Cloud Messaging or Apple Push Notification service).
  @JsonKey(name: "deviceToken")
  String deviceToken;

  /// The operating system type of the player's device (optional, automatically set).
  ///
  /// This value is automatically determined based on the current platform (iOS, Android, or other)
  /// and is included in the registration request for informational purposes.
  @JsonKey(name: "osType")
  String? osType;

  /// Additional player attributes to be sent during registration (optional).
  ///
  /// This can include details such as the player's display name, email address, mobile number,
  /// date of birth, and custom attributes specific to your application. These attributes can
  /// be used by Gameball to personalize the player's experience within the platform.
  @JsonKey(name: "playerAttributes")
  PlayerAttributes? playerAttributes;

  /// A referral code associated with the player (optional).
  ///
  /// If a referral code is provided, it can be used to track referrals and potentially offer
  /// rewards to both the referring and referred players.
  @JsonKey(name: "referrerCode")
  String? referrerCode;

  /// The player's email address (optional).
  ///
  /// You can include the player's email address if you plan to use email-based communication
  /// or for other purposes within your application.
  @JsonKey(name: "email")
  String? email;

  /// The player's mobile number (optional).
  ///
  /// You can include the player's mobile number if you plan to use SMS-based communication
  /// or for other purposes within your application.
  @JsonKey(name: "mobile")
  String? mobileNumber;

  /// Creates a new `PlayerRegisterRequest` object.
  ///
  /// Arguments:
  ///   - `playerUniqueID` (required): The unique identifier for the player.
  ///   - `deviceToken` (required): The player's device token.
  ///   - `osType` (optional): The operating system type (automatically set if not provided).
  ///   - `playerAttributes` (optional): Additional player attributes.
  ///   - `referrerCode` (optional): A referral code associated with the player.
  ///   - `email` (optional): The player's email address.
  ///   - `mobileNumber` (optional): The player's mobile number.
  PlayerRegisterRequest({
    required this.playerUniqueID,
    required this.deviceToken,
    this.osType,
    this.playerAttributes,
    this.referrerCode,
    this.email,
    this.mobileNumber,
  }) {
    osType = getDevicePlatform(); // Automatically set osType based on platform
  }

  /// Converts the `PlayerRegisterRequest` object to a JSON map.
  ///
  /// This method is typically used internally by the `json_serializable` package
  /// to serialize the object before sending it to the Gameball API.
  Map<String, dynamic> toJson() => _$PlayerRegisterRequestToJson(this);

  // Added factory constructor and fromJson method generated by json_serializable
  factory PlayerRegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$PlayerRegisterRequestFromJson(json);
}
