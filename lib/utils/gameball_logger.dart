import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/request_calls/send_logs_request.dart';
import 'gameball_utils.dart';
import 'platform_utils.dart';

/// Fail-silent SDK telemetry logger. Fires one diagnostic entry per call directly to
/// api/v4.0/integrations/mobile/logs (forwarded to Datadog). The payload is sent as-is, immediately
/// and fire-and-forget; this layer must never throw into, or block, the host app.
class GameballLogger {
  GameballLogger._();
  static final GameballLogger instance = GameballLogger._();

  static const String _installIdKey = 'gameball_install_id';

  Map<String, dynamic>? _context;
  String? _installId;

  String _apiKey = '';
  String _lang = '';
  String? _apiPrefix;

  /// Configure the logger with the current SDK credentials. Called from init().
  void configure({required String apiKey, required String lang, String? apiPrefix}) {
    _apiKey = apiKey;
    _lang = lang;
    _apiPrefix = apiPrefix;
  }

  /// Fire one SDK event immediately. Never throws. [params] is sent as-is.
  void log(String event, {Object? params}) {
    if (isNullOrEmpty(_apiKey)) return;
    final entry = <String, dynamic>{
      'event': event,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    if (params != null) entry['params'] = params;
    _send(entry);
  }

  Future<void> _send(Map<String, dynamic> entry) async {
    try {
      final body = <String, dynamic>{
        'context': await _buildContext(),
        'logs': [entry],
      };
      await sendLogsRequest(body, _apiKey, _lang, customApiPrefix: _apiPrefix);
    } catch (_) {
      // Telemetry must never affect the host app.
    }
  }

  Future<Map<String, dynamic>> _buildContext() async {
    if (_context != null) return _context!;

    final platform = getDevicePlatform(); // 'iOS' | 'Android' | 'Unknown'
    String? model;
    String? osVersion;
    String? appBundleId;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (platform == 'Android') {
        final android = await deviceInfo.androidInfo;
        model = '${android.manufacturer} ${android.model}';
        osVersion = 'Android ${android.version.release}';
      } else if (platform == 'iOS') {
        final ios = await deviceInfo.iosInfo;
        model = ios.utsname.machine;
        osVersion = '${ios.systemName} ${ios.systemVersion}';
      }
    } catch (_) {}

    try {
      appBundleId = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {}

    _context = <String, dynamic>{
      'sdkType': 'flutter',
      'sdkVersion': getSdkVersion(),
      'devicePlatform': platform,
      'deviceOsVersion': osVersion,
      'deviceModel': model,
      'appBundleId': appBundleId,
      'installId': await _getInstallId(),
    };
    return _context!;
  }

  /// Returns the persisted per-install UUID, generating one on first access.
  Future<String?> _getInstallId() async {
    if (_installId != null) return _installId;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_installIdKey);
      if (id == null || id.isEmpty) {
        id = _uuidV4();
        await prefs.setString(_installIdKey, id);
      }
      _installId = id;
      return id;
    } catch (_) {
      return null;
    }
  }

  String _uuidV4() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
