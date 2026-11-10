import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums/push_engagement_type.dart';

/// Engagement signals: push taps, app opens, push arrivals and influenced opens.
///
/// Mirrors the Android SDK's `engagement` package. Taps (through
/// `handlePushClick`) and influenced opens are reported to the push-engagement
/// endpoint; app opens and arrivals are only logged.

/// Returns the current time in milliseconds since the epoch. Injected in tests.
typedef EngagementClock = int Function();

/// Writes one engagement log line. Injected in tests.
typedef EngagementLogSink = void Function(String line);

/// Reports one engagement with a push to Gameball. [occurredAt] is milliseconds
/// since the epoch. Completes with an error when the report fails.
typedef PushEngagementSender = Future<void> Function(
    PushEngagementType type, String clickToken, int occurredAt);

int _systemNow() => DateTime.now().millisecondsSinceEpoch;

void _printLine(String line) => debugPrint(line);

/// One app-level open. [type] is cold for the first in this process, warm for a
/// later one. [fromTap] is true when a Gameball push tap handled while the app
/// was away opened it.
@immutable
class AppOpen {
  const AppOpen(this.type, this.openedAt, {this.fromTap = false});

  static const String cold = 'cold';
  static const String warm = 'warm';

  final String type;
  final int openedAt;
  final bool fromTap;

  @override
  bool operator ==(Object other) =>
      other is AppOpen &&
      other.type == type &&
      other.openedAt == openedAt &&
      other.fromTap == fromTap;

  @override
  int get hashCode => Object.hash(type, openedAt, fromTap);

  @override
  String toString() => 'AppOpen($type, $openedAt, fromTap: $fromTap)';
}

/// Turns foreground/background changes of the whole app into opens.
///
/// The first time in the foreground is a cold open. A return after more than
/// [sessionGapMillis] in the background is a warm open. A return within the gap
/// continues the last open, the same rule as an in-app messaging session.
class AppOpenTracker {
  AppOpenTracker({
    EngagementClock? now,
    this.sessionGapMillis = sessionGapMs,
    this.tapMarkMillis = tapMarkMs,
    required void Function(AppOpen open) report,
  })  : _now = now ?? _systemNow,
        _report = report;

  /// In-app messaging's default session timeout, so both agree on what an open is.
  static const int sessionGapMs = 30 * 1000;

  /// How long a tap handled while the app is away marks the next return as
  /// opened by that tap.
  static const int tapMarkMs = 60 * 1000;

  final EngagementClock _now;
  final int sessionGapMillis;
  final int tapMarkMillis;
  final void Function(AppOpen open) _report;

  bool _started = false;
  bool _inForeground = false;
  int? _backgroundedAt;
  int? _tapMarkedAt;

  /// A Gameball push tap was handled. While the app is away (or not yet opened)
  /// it marks the next return as opened by the tap. On screen a tap opens
  /// nothing, so it marks nothing.
  void onTap() {
    if (!_inForeground) _tapMarkedAt = _now();
  }

  /// The app came to the foreground. Repeats while already there are ignored.
  void onForeground() {
    if (_inForeground) return;
    _inForeground = true;
    final at = _now();
    // Every return uses the tap mark up, whether or not it is an open
    final tapMarkedAt = _tapMarkedAt;
    _tapMarkedAt = null;
    final fromTap = tapMarkedAt != null && at - tapMarkedAt <= tapMarkMillis;
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    final away = backgroundedAt == null ? null : at - backgroundedAt;
    if (_started && away != null && away <= sessionGapMillis) return;
    _report(AppOpen(_started ? AppOpen.warm : AppOpen.cold, at, fromTap: fromTap));
    _started = true;
  }

  /// The app is visible again after being away, but not interactive yet:
  /// Flutter's `inactive` on the way back from `hidden`. On Android that is the
  /// activity resumed without window focus (split screen, a system dialog on
  /// top), which still counts as an open, like the native SDK's onStart. Before
  /// the first open it means nothing: a cold start counts once resumed.
  void onVisibleAgain() {
    if (!_started) return;
    onForeground();
  }

  /// The app left the foreground. Repeats while already away are ignored, so the
  /// time away is measured from the first step out (hidden, then paused).
  void onBackground() {
    if (!_inForeground) return;
    _inForeground = false;
    _backgroundedAt = _now();
  }
}

/// A Gameball push that reached the phone and hasn't been tapped. [key] identifies the push.
@immutable
class ReceivedPush {
  const ReceivedPush({
    required this.key,
    required this.clickToken,
    required this.sentAt,
    required this.receivedAt,
  });

  final String key;
  final String? clickToken;
  final int sentAt;
  final int receivedAt;

  Map<String, dynamic> toJson() => {
        'key': key,
        'clickToken': clickToken ?? '',
        'sentAt': sentAt,
        'receivedAt': receivedAt,
      };

  static ReceivedPush fromJson(Map<String, dynamic> json) {
    final token = json['clickToken'] as String?;
    return ReceivedPush(
      key: json['key'] as String,
      clickToken: (token == null || token.isEmpty) ? null : token,
      sentAt: (json['sentAt'] as num?)?.toInt() ?? 0,
      receivedAt: (json['receivedAt'] as num).toInt(),
    );
  }
}

/// Where received pushes are kept between app launches.
abstract class ReceivedPushStore {
  Future<List<ReceivedPush>> load();
  Future<void> save(List<ReceivedPush> pushes);
}

/// Received pushes on disk. The app is usually killed between a push arriving and
/// the next open, so memory isn't enough.
///
/// Uses [SharedPreferencesAsync], which has no in-memory cache: a push saved by
/// firebase_messaging's background isolate is seen by the app's main isolate. The
/// legacy `SharedPreferences` caches per isolate and would miss it.
class SharedPreferencesReceivedPushStore implements ReceivedPushStore {
  SharedPreferencesReceivedPushStore([SharedPreferencesAsync? prefs]) : _givenPrefs = prefs;

  static const String storageKey = 'gameball_received_pushes';

  final SharedPreferencesAsync? _givenPrefs;

  // Created on first use, inside load/save: SharedPreferencesAsync throws when
  // the platform side isn't registered, and that must become a failed future the
  // callers already handle, never a throw out of an SDK call.
  late final SharedPreferencesAsync _prefs = _givenPrefs ?? SharedPreferencesAsync();

  @override
  Future<List<ReceivedPush>> load() async {
    final raw = await _prefs.getString(storageKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ReceivedPush.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('GameballApp could not read received pushes: $e');
      return const [];
    }
  }

  @override
  Future<void> save(List<ReceivedPush> pushes) async {
    if (pushes.isEmpty) {
      await _prefs.remove(storageKey);
    } else {
      await _prefs.setString(
          storageKey, jsonEncode(pushes.map((p) => p.toJson()).toList()));
    }
  }
}

/// Influenced opens: a push arrived, the user didn't tap it, and opened the app
/// within [windowMillis] of receiving it.
///
/// - received → saved
/// - tapped → removed; it's a normal tap and never counts as influenced
/// - app opened by a Gameball push tap → a click, never influenced, even when
///   an older untapped push is saved and still within the window
/// - app opened otherwise → if the most recent saved push arrived within the
///   window, that push influenced the open
/// - every open clears the saved list
class InfluencedOpens {
  InfluencedOpens(this._store, {EngagementClock? now, this.windowMillis = windowMs})
      : _now = now ?? _systemNow;

  static const int windowMs = 30 * 60 * 1000;
  static const int maxSaved = 20;

  final ReceivedPushStore _store;
  final EngagementClock _now;
  final int windowMillis;

  /// Runs the read-modify-write steps one after another within this isolate.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() step) {
    final result = _queue.then((_) => step());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Saves a received push. [receivedAt] defaults to now.
  Future<void> onReceived(String key, String? clickToken, int sentAt, {int? receivedAt}) =>
      _serial(() async {
        final at = receivedAt ?? _now();
        final pushes = (await _store.load()).where((p) => p.key != key).toList()
          ..add(ReceivedPush(
              key: key, clickToken: clickToken, sentAt: sentAt, receivedAt: at));
        final start = pushes.length > maxSaved ? pushes.length - maxSaved : 0;
        await _store.save(pushes.sublist(start));
      });

  Future<void> onTap(String key) => _serial(() async {
        final pushes = await _store.load();
        if (pushes.any((p) => p.key == key)) {
          await _store.save(pushes.where((p) => p.key != key).toList());
        }
      });

  /// The push that influenced [open], or null for an ordinary open or one a
  /// tap caused. Clears the saved list either way.
  Future<ReceivedPush?> influencedBy(AppOpen open) async {
    final pushes = await takeAll();
    if (open.fromTap) return null;
    return pick(pushes, open.openedAt);
  }

  /// Every saved push, and the saved list cleared: each open starts a fresh list.
  Future<List<ReceivedPush>> takeAll() => _serial(() async {
        final pushes = await _store.load();
        if (pushes.isNotEmpty) await _store.save(const []);
        return pushes;
      });

  /// The push that influenced an open at [openedAt] that no tap caused: the
  /// most recent push, when it arrived within the window. Never an older one.
  ReceivedPush? pick(List<ReceivedPush> pushes, int openedAt) {
    if (pushes.isEmpty) return null;
    final latest = pushes.reduce((a, b) => b.receivedAt > a.receivedAt ? b : a);
    final age = openedAt - latest.receivedAt;
    return (age >= 0 && age <= windowMillis) ? latest : null;
  }

  /// Another customer's pushes must never credit this customer's opens.
  Future<void> clear() => _serial(() => _store.save(const []));
}

/// A push Gameball's backend sent, read from a data payload. Anything without
/// `isGB = "true"` is not one of ours.
class GameballPushPayload {
  GameballPushPayload._(this.payload);

  static GameballPushPayload? from(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    if (payload['isGB']?.toString().toLowerCase() != 'true') return null;
    return GameballPushPayload._(payload);
  }

  final Map<String, dynamic> payload;

  String? _string(String name) {
    final value = payload[name]?.toString();
    return (value == null || value.trim().isEmpty) ? null : value;
  }

  /// The token the backend issued for this push; null when it carries none.
  String? get clickToken => _string('gbClickToken');

  /// The same push seen twice gives the same key.
  String? get key => clickToken ?? _string('google.message_id') ?? _string('messageId');

  /// FCM's send time when the payload carries it, else null.
  int? get sentTime => int.tryParse(_string('google.sent_time') ?? '');
}

/// Wires the trackers together and owns the log lines. One per isolate.
class Engagement {
  Engagement({
    ReceivedPushStore? store,
    EngagementClock? now,
    EngagementLogSink? log,
    Future<void> Function()? waitForTap,
    this.send,
  })  : _now = now ?? _systemNow,
        _log = log ?? _printLine,
        _waitForTap = waitForTap ?? _tapGrace,
        _influencedOpens = InfluencedOpens(
          store ?? SharedPreferencesReceivedPushStore(),
          now: now,
        ) {
    appOpens = AppOpenTracker(now: _now, report: _onAppOpen);
  }

  /// How long after an open a tap can still arrive and make it an open caused
  /// by a tap, which is never influenced.
  ///
  /// On Android the native SDK sees a tap before the open it causes. A Flutter
  /// app learns of a tap from firebase_messaging (`getInitialMessage` or
  /// `onMessageOpenedApp`) and only then calls `handlePushClick`, which on a
  /// cold start is usually after the SDK has seen the app come to the
  /// foreground. Without this wait an open caused by a tap could be credited
  /// as an influenced open.
  static const Duration tapGrace = Duration(seconds: 10);

  static Future<void> _tapGrace() => Future<void>.delayed(tapGrace);

  final EngagementClock _now;
  final EngagementLogSink _log;
  final Future<void> Function() _waitForTap;
  final InfluencedOpens _influencedOpens;
  late final AppOpenTracker appOpens;

  /// Reports influenced opens to Gameball. `GameballApp` sets it; while null,
  /// influenced opens are only logged.
  PushEngagementSender? send;

  /// The current time on this engagement's clock, in milliseconds.
  int now() => _now();

  /// Taps already counted in this app run, by push key.
  final Set<String> _handledTaps = {};

  /// Gameball taps handled so far, to tell whether one came during an open's wait.
  int _taps = 0;

  /// Pending influenced-open checks, so tests can wait for them.
  Future<void> _lastOpen = Future.value();

  @visibleForTesting
  Future<void> get settled => _lastOpen;

  /// Counts a tap once per app run. Returns false when [push] was already counted.
  bool onTap(GameballPushPayload push) {
    final key = push.key;
    if (key != null && !_handledTaps.add(key)) return false;
    logSignal('push_click', {'clickToken': push.clickToken});
    _taps++;
    // While the app is away, this tap is what brings it back
    appOpens.onTap();
    // A tapped push is a normal tap and never counts toward an influenced open
    if (key != null) {
      _influencedOpens.onTap(key).catchError(
          (Object e) => _log('GameballApp could not drop a tapped push: $e'));
    }
    return true;
  }

  /// Logs and saves an arrival. [sentTime] wins over the payload's own send time.
  Future<void> onReceived(GameballPushPayload push, {int? sentTime}) async {
    final sentAt = sentTime ?? push.sentTime ?? 0;
    final receivedAt = _now();
    logSignal('push_received', {
      'clickToken': push.clickToken,
      'sentAt': sentAt,
      'receivedAt': receivedAt,
    });
    final key = push.key;
    if (key == null) return;
    try {
      await _influencedOpens.onReceived(key, push.clickToken, sentAt, receivedAt: receivedAt);
    } catch (e) {
      _log('GameballApp could not save a received Gameball push: $e');
    }
  }

  /// A different customer signed in: forget the previous customer's pushes.
  Future<void> onCustomerChanged() => _influencedOpens.clear().catchError(
      (Object e) => _log('GameballApp could not clear received pushes: $e'));

  void _onAppOpen(AppOpen open) {
    // Logged now; whether a tap caused it may only be known after the wait
    logSignal('app_open', {'type': open.type, 'openedAt': open.openedAt});
    final tapsAtOpen = _taps;
    // Cleared now, so the next open never sees these pushes
    final taken = _influencedOpens.takeAll();
    _lastOpen = () async {
      final pushes = await taken;
      if (pushes.isEmpty) return;
      await _waitForTap();
      // An open caused by a Gameball tap is a click, never an influenced open:
      // the tap was handled while the app was away, or during this wait
      if (open.fromTap || _taps != tapsAtOpen) return;
      final push = _influencedOpens.pick(pushes, open.openedAt);
      if (push == null) return;
      logSignal('influenced_open', {
        'clickToken': push.clickToken,
        'sentAt': push.sentAt,
        'receivedAt': push.receivedAt,
        'type': open.type,
        'openedAt': open.openedAt,
      });
      // Reported as happening at the open, not when the wait ended
      final token = push.clickToken;
      final send = this.send;
      if (token == null || send == null) return;
      try {
        await send(PushEngagementType.influencedOpen, token, open.openedAt);
      } catch (e) {
        _log('GameballApp could not report influenced_open: $e');
      }
    }()
        .catchError((Object e) => _log('GameballApp could not check influenced open: $e'));
  }

  void logSignal(String name, Map<String, Object?> fields) {
    _log('GameballApp engagement $name '
        '${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
  }
}
