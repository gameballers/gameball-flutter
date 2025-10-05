import 'package:json_annotation/json_annotation.dart';

part 'gameball_config.g.dart';

/// Represents the configuration parameters for initializing the Gameball SDK.
///
/// This class encapsulates all the parameters needed to initialize the SDK
/// with the required API key, language, platform, and shop information.
@JsonSerializable(createFactory: false)
class GameballConfig {
  /// The API key for authenticating with the Gameball service (required).
  @JsonKey(name: "apiKey")
  final String apiKey;

  /// The language code for SDK operations (required).
  @JsonKey(name: "lang")
  final String lang;

  /// The platform identifier (optional).
  @JsonKey(name: "platform")
  final String? platform;

  /// The shop identifier (optional).
  @JsonKey(name: "shop")
  final String? shop;

  /// The custom API prefix/base URL (optional).
  @JsonKey(name: "apiPrefix")
  final String? apiPrefix;

  /// The Session Token for secure API endpoints (optional).
  @JsonKey(name: "sessionToken")
  final String? sessionToken;

  /// Private constructor for creating GameballConfig instances.
  /// Use [GameballConfigBuilder] to create instances of this class.
  const GameballConfig._({
    required this.apiKey,
    required this.lang,
    this.platform,
    this.shop,
    this.apiPrefix,
    this.sessionToken,
  });


  /// Converts the `GameballConfig` object to a JSON map.
  ///
  /// This method is typically used internally by the `json_serializable` package.
  Map<String, dynamic> toJson() => _$GameballConfigToJson(this);

  /// Create from JSON map.
  factory GameballConfig.fromJson(Map<String, dynamic> json) => GameballConfig._(
        apiKey: json['apiKey'] as String,
        lang: json['lang'] as String,
        platform: json['platform'] as String?,
        shop: json['shop'] as String?,
        apiPrefix: json['apiPrefix'] as String?,
        sessionToken: json['sessionToken'] as String?,
      );
}

/// Builder class for [GameballConfig].
///
/// Provides a fluent API for constructing GameballConfig instances.
class GameballConfigBuilder {
  String? _apiKey;
  String? _lang;
  String? _platform;
  String? _shop;
  String? _apiPrefix;
  String? _sessionToken;

  /// Set the required API key.
  GameballConfigBuilder apiKey(String apiKey) {
    _apiKey = apiKey;
    return this;
  }

  /// Set the required language.
  GameballConfigBuilder lang(String lang) {
    _lang = lang;
    return this;
  }

  /// Set the optional platform.
  GameballConfigBuilder platform(String? platform) {
    _platform = platform;
    return this;
  }

  /// Set the optional shop.
  GameballConfigBuilder shop(String? shop) {
    _shop = shop;
    return this;
  }

  /// Set the optional custom API prefix.
  GameballConfigBuilder apiPrefix(String? apiPrefix) {
    _apiPrefix = apiPrefix;
    return this;
  }

  /// Set the optional Session Token for secure endpoints.
  GameballConfigBuilder sessionToken(String? sessionToken) {
    _sessionToken = sessionToken;
    return this;
  }

  /// Build the final immutable [GameballConfig] instance.
  GameballConfig build() {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw ArgumentError('API key cannot be empty');
    }
    if (_lang == null || _lang!.isEmpty) {
      throw ArgumentError('Language cannot be empty');
    }
    return GameballConfig._(
      apiKey: _apiKey!,
      lang: _lang!,
      platform: _platform,
      shop: _shop,
      apiPrefix: _apiPrefix,
      sessionToken: _sessionToken,
    );
  }
}