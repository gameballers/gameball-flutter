import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'analytics/message_analytics.dart';
import 'evaluation/frequency_cap.dart';
import 'evaluation/trigger_evaluator.dart';
import 'iam_log.dart';
import 'models/gameball_audience.dart';
import 'models/in_app_message.dart';
import 'models/in_app_message_campaign.dart';
import 'models/message_trigger.dart';
import 'presentation/message_presenter.dart';
import 'source/message_source.dart';

/// What the host wants done with a message about to be displayed.
enum GameballDisplayDecision {
  /// Display it now.
  show,

  /// Hold it; it will be retried at the next display opportunity.
  later,

  /// Drop it. It will not be shown for this trigger occurrence.
  discard,
}

/// Consulted immediately before a message is displayed.
///
/// Synchronous, matching Braze Android's `beforeInAppMessageDisplayed`. If it
/// throws, the SDK falls back to [GameballDisplayDecision.show].
typedef GameballBeforeDisplay = GameballDisplayDecision Function(
  GameballInAppMessage message,
);

/// Signature for opening a URL, injectable so tests never touch the platform.
typedef UrlLauncher = Future<bool> Function(Uri uri, {bool external});

/// How long the app must be backgrounded before returning counts as a new
/// session.
///
/// Matched to [minimumIntervalBetweenDisplays] on purpose. A shorter timeout
/// would create sessions that fire the session-start trigger while the display
/// floor is still blocking, producing a dead zone where a message is selected and
/// then silently suppressed. Braze's default is shorter than its floor and
/// accepts that; here they are aligned so a new session can always show
/// something.
const Duration defaultSessionTimeout = minimumIntervalBetweenDisplays;

/// Wires fetching, evaluation, deferral, display and analytics together.
///
/// Owns no display policy of its own — [selectCampaign] decides what shows —
/// and no drawing. Its job is sequencing and the pending-message slot.
class InAppMessagingService {
  InAppMessagingService({
    required GameballMessageSource source,
    required GameballMessagePresenter presenter,
    required FrequencyCap frequencyCap,
    required MessageAnalytics analytics,
    required bool Function() isHostWidgetOpen,
    void Function(GameballInAppMessage message)? emit,
    DateTime Function()? clock,
    UrlLauncher? launcher,
    this.sessionTimeout = defaultSessionTimeout,
  })  : _source = source,
        _presenter = presenter,
        _cap = frequencyCap,
        _analytics = analytics,
        _isHostWidgetOpen = isHostWidgetOpen,
        _emit = emit,
        _clock = clock ?? DateTime.now,
        _launcher = launcher ?? _defaultLauncher;

  final GameballMessageSource _source;
  final GameballMessagePresenter _presenter;
  final FrequencyCap _cap;
  final MessageAnalytics _analytics;
  final bool Function() _isHostWidgetOpen;
  final void Function(GameballInAppMessage message)? _emit;
  final DateTime Function() _clock;
  final UrlLauncher _launcher;

  /// How long backgrounded before a resume counts as a new session.
  final Duration sessionTimeout;

  GameballAudience? _audience;
  GameballBeforeDisplay? _beforeDisplay;
  List<InAppMessageCampaign> _campaigns = const <InAppMessageCampaign>[];

  /// The one message waiting for a display opportunity, if any.
  ///
  /// A single slot: a newer deferral displaces an older one. Braze keeps a
  /// stack; for one message type a slot is honest and enough.
  InAppMessageCampaign? _pending;

  /// When the app last left the foreground, used to decide whether a resume
  /// begins a new session.
  DateTime? _lastPausedAt;

  /// Guards the post-frame retry so it cannot re-arm on every frame.
  ///
  /// Without this, a message deferred for want of a navigator schedules a retry,
  /// which fails, which schedules another — spinning once per frame for as long
  /// as no surface exists.
  bool _postFrameRetryScheduled = false;

  /// Whether in-app messaging is running for a customer.
  bool get isStarted => _audience != null;

  /// Exposed for the debug surface in the sample app and for tests.
  InAppMessageCampaign? get pendingCampaign => _pending;

  static Future<bool> _defaultLauncher(Uri uri, {bool external = false}) {
    return launchUrl(
      uri,
      mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault,
    );
  }

  /// Opts in to in-app messaging for [customerId] and evaluates session start.
  Future<void> start({
    required String customerId,
    GameballBeforeDisplay? beforeDisplay,
  }) async {
    final current = _audience;
    if (current is CustomerAudience && current.customerId == customerId) {
      iamLog('start ignored: already running for customer "$customerId"');
      return;
    }

    _beforeDisplay = beforeDisplay;
    _resetFor(CustomerAudience(customerId));
    await _fetchAndEvaluateSessionStart();
  }

  /// Clears all state and dismisses anything on screen.
  void stop() {
    if (!isStarted) return;
    _presenter.dismiss();
    _pending = null;
    _campaigns = const <InAppMessageCampaign>[];
    _cap.reset();
    _audience = null;
    _beforeDisplay = null;
    iamLog('in-app messaging stopped');
  }

  /// Called when the host identifies a (possibly different) customer.
  void onCustomerChanged(String customerId) {
    if (!isStarted) return;
    final current = _audience;
    if (current is CustomerAudience && current.customerId == customerId) return;

    iamLog('customer changed to "$customerId"; refetching campaigns');
    _resetFor(CustomerAudience(customerId));
    // Fire and forget: the caller's contract must not wait on ours.
    _fetchAndEvaluateSessionStart();
  }

  /// Called when the host logs an event that may trigger a message.
  void onCustomEvent(String eventName, {Map<String, Object>? properties}) {
    if (!isStarted) return;
    _evaluate(GameballCustomEventOccurrence(
      eventName,
      properties: properties ?? const <String, Object>{},
    ));
  }

  /// Called when the host logs a purchase.
  void onPurchase({
    required String productId,
    required double price,
    required String currency,
    int quantity = 1,
    Map<String, Object>? properties,
  }) {
    if (!isStarted) return;
    _evaluate(GameballPurchaseOccurrence(
      productId: productId,
      price: price,
      currency: currency,
      quantity: quantity,
      properties: properties ?? const <String, Object>{},
    ));
  }

  /// Called when the app returns to the foreground.
  ///
  /// A resume after more than [sessionTimeout] in the background begins a new
  /// session and fires the session-start trigger again — so a warm return is a
  /// genuine trigger occurrence, not just a repaint.
  ///
  /// Frequency caps deliberately survive a new session: that is what makes the
  /// first session-start campaign show on the cold start and the next one show on
  /// the warm return, rather than the same message every time.
  void onAppResumed() {
    if (!isStarted) return;
    final since = _lastPausedAt;
    if (since == null) return;
    _lastPausedAt = null;

    final away = _clock().difference(since);
    if (away < sessionTimeout) {
      iamLog('resumed after ${away.inSeconds}s — same session, no trigger');
      return;
    }

    iamLog('resumed after ${away.inSeconds}s — new session');
    _evaluate(const GameballSessionStartOccurrence());
  }

  /// Called when the app leaves the foreground, to time the absence.
  void onAppPaused() {
    if (!isStarted) return;
    _lastPausedAt = _clock();
  }

  /// Called when the Gameball profile widget closes, freeing the screen.
  void onHostWidgetClosed() => _retryPending();

  // ------------------------------------------------------------------ internals

  void _resetFor(GameballAudience audience) {
    _presenter.dismiss();
    _pending = null;
    _campaigns = const <InAppMessageCampaign>[];
    _cap.reset();
    _audience = audience;
  }

  Future<void> _fetchAndEvaluateSessionStart() async {
    final audience = _audience;
    if (audience == null) return;

    await _cap.load();
    try {
      _campaigns = await _source.fetch(audience);
      iamLog('fetched ${_campaigns.length} campaign(s)');
    } catch (error) {
      _campaigns = const <InAppMessageCampaign>[];
      iamLog('fetch failed; no campaigns available for this session ($error)');
      return;
    }

    _evaluate(const GameballSessionStartOccurrence());
  }

  void _evaluate(GameballTriggerOccurrence occurrence) {
    if (_campaigns.isEmpty) {
      iamLog('trigger ignored: no campaigns loaded');
      return;
    }

    final campaign = selectCampaign(
      occurrence: occurrence,
      campaigns: _campaigns,
      capState: _cap.snapshot(),
      now: _clock(),
    );
    if (campaign == null) return;

    // Observers see every selected message, whatever the host then decides.
    _emit?.call(campaign.message);

    switch (_decide(campaign.message)) {
      case GameballDisplayDecision.discard:
        iamLog('campaign "${campaign.id}" discarded by beforeDisplay');
      case GameballDisplayDecision.later:
        _defer(campaign, 'the host asked to display it later');
      case GameballDisplayDecision.show:
        _tryPresent(campaign);
    }
  }

  GameballDisplayDecision _decide(GameballInAppMessage message) {
    final hook = _beforeDisplay;
    if (hook == null) return GameballDisplayDecision.show;
    try {
      return hook(message);
    } catch (error) {
      iamLog('beforeDisplay threw; defaulting to show ($error)');
      return GameballDisplayDecision.show;
    }
  }

  void _tryPresent(InAppMessageCampaign campaign) {
    if (_isHostWidgetOpen()) {
      _defer(campaign, 'the Gameball widget is open');
      return;
    }
    if (_presenter.isShowing) {
      _defer(campaign, 'another message is showing');
      return;
    }

    final presented = _presenter.present(
      message: campaign.message,
      onShown: () {
        // Recorded at impression, never at selection, so a deferred or
        // suppressed message does not burn its slot.
        _cap.recordDisplay(campaign.id, _clock());
        _analytics.logImpression(campaign.message, campaignId: campaign.id);
      },
      onButtonPressed: (button) {
        _analytics.logButtonClick(
          campaign.message,
          campaignId: campaign.id,
          buttonId: button.id,
        );
        _runAction(button.action);
        _presenter.dismiss();
      },
      onMessagePressed: () {
        final action = campaign.message.clickAction;
        if (action == null) return;
        _analytics.logClick(campaign.message, campaignId: campaign.id);
        _runAction(action);
        _presenter.dismiss();
      },
      onDismissed: _retryPending,
    );

    if (!presented) {
      _defer(campaign, 'no presentation surface available');
      // start() can precede the first frame, so try once more after it.
      if (!_postFrameRetryScheduled) {
        _postFrameRetryScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _postFrameRetryScheduled = false;
          _retryPending();
        });
      }
    }
  }

  void _defer(InAppMessageCampaign campaign, String reason) {
    final displaced = _pending;
    if (displaced != null && displaced.id != campaign.id) {
      iamLog('pending campaign "${displaced.id}" displaced by "${campaign.id}"');
    }
    _pending = campaign;
    iamLog('campaign "${campaign.id}" deferred: $reason');
  }

  void _retryPending() {
    final campaign = _pending;
    if (campaign == null) return;
    _pending = null;

    final capState = _cap.snapshot();
    if (capState.shownCampaignIds.contains(campaign.id)) {
      iamLog('pending campaign "${campaign.id}" dropped: already shown');
      return;
    }
    // Re-validated so a message deferred before another was displayed cannot
    // slip through inside the floor.
    if (isWithinFloor(capState: capState, now: _clock())) {
      _pending = campaign;
      return;
    }

    _tryPresent(campaign);
  }

  Future<void> _runAction(GameballClickAction action) async {
    switch (action) {
      case GameballDismissAction():
        return;
      case GameballOpenUrlAction(url: final url, external: final external):
        final uri = Uri.tryParse(url);
        if (uri == null) {
          iamLog('cannot open malformed url "$url"');
          return;
        }
        try {
          final opened = await _launcher(uri, external: external);
          if (!opened) iamLog('could not open "$url"');
        } catch (error) {
          // Never trap the user: the message is dismissed regardless.
          iamLog('could not open "$url" ($error)');
        }
    }
  }
}
