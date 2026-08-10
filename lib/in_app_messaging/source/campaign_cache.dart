import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../iam_log.dart';
import 'message_parser.dart';
import 'message_source.dart';

/// Keeps the last successful sync on disk, scoped to one customer.
///
/// Required by the backend's contract twice over: *"on sync failure keep the
/// previous unexpired cache"*, and a message can display offline if its payload
/// arrived first. Neither is possible if campaigns only live in memory.
///
/// **The raw response is stored, not parsed objects.** That means no serialiser to
/// write and keep in step with the model, and the only reader is the parser that
/// is already tested. It also means a payload written by an older SDK version is
/// re-parsed by the newer one's rules rather than resurrected as stale objects.
abstract class CampaignCache {
  /// Reads the cached sync for [customerId], or an empty result when there is
  /// none, it belongs to someone else, or it cannot be parsed.
  Future<GameballSyncResult> read(String customerId);

  /// Replaces the cache with [rawJson].
  Future<void> write(String customerId, String rawJson);

  /// Forgets everything, in memory and on disk.
  Future<void> clear();
}

/// A cache that forgets everything when the process ends.
class InMemoryCampaignCache implements CampaignCache {
  String? _customerId;
  String? _rawJson;

  @override
  Future<GameballSyncResult> read(String customerId) async {
    final raw = _rawJson;
    if (raw == null || _customerId != customerId) {
      return const GameballSyncResult.empty();
    }
    final result = parseSyncResponse(raw);
    return GameballSyncResult(
      campaigns: result.campaigns,
      cooldown: result.cooldown,
    );
  }

  @override
  Future<void> write(String customerId, String rawJson) async {
    _customerId = customerId;
    _rawJson = rawJson;
  }

  @override
  Future<void> clear() async {
    _customerId = null;
    _rawJson = null;
  }
}

/// A cache backed by device storage.
class StoredCampaignCache implements CampaignCache {
  StoredCampaignCache({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  static const String _key = 'gameball_iam_campaign_cache';

  @override
  Future<GameballSyncResult> read(String customerId) async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const GameballSyncResult.empty();

      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) {
        await prefs.remove(_key);
        return const GameballSyncResult.empty();
      }

      if (envelope['customerId'] != customerId) {
        // Never reused across customers. Showing one person's campaigns to
        // another is the one failure this whole scoping exists to prevent.
        iamLog('cached campaigns belonged to another customer; discarded');
        await prefs.remove(_key);
        return const GameballSyncResult.empty();
      }

      final payload = envelope['payload'];
      if (payload is! String) return const GameballSyncResult.empty();

      final result = parseSyncResponse(payload);
      iamLog('loaded ${result.campaigns.length} cached campaign(s)');
      // rawJson deliberately dropped: this came *from* the cache, and carrying it
      // would let a read trigger a redundant write.
      return GameballSyncResult(
        campaigns: result.campaigns,
        cooldown: result.cooldown,
      );
    } catch (error) {
      // A corrupt cache must not stop messaging from starting.
      iamLog('could not read the campaign cache ($error)');
      return const GameballSyncResult.empty();
    }
  }

  @override
  Future<void> write(String customerId, String rawJson) async {
    try {
      final prefs = await _preferences();
      await prefs.setString(
        _key,
        jsonEncode(<String, dynamic>{
          'customerId': customerId,
          'payload': rawJson,
        }),
      );
    } catch (error) {
      iamLog('could not write the campaign cache ($error)');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await _preferences();
      await prefs.remove(_key);
    } catch (error) {
      iamLog('could not clear the campaign cache ($error)');
    }
  }
}
