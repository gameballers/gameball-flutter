import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'analytics/message_analytics.dart';
import 'analytics/message_event.dart';
import 'evaluation/frequency_cap.dart';
import 'evaluation/trigger_evaluator.dart';
import 'iam_log.dart';
import 'models/gameball_audience.dart';
import 'models/in_app_message.dart';
import 'models/in_app_message_campaign.dart';
import 'models/message_trigger.dart';
import 'personalisation/token_substitution.dart';
import 'personalisation/variable_source.dart';
import 'presentation/artwork_prefetcher.dart';
import 'presentation/message_navigator.dart';
import 'presentation/message_presenter.dart';
import 'source/campaign_cache.dart';
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

/// Consulted when a message or one of its buttons is tapped, before the SDK acts.
///
/// Return true to say the host handled it; the SDK then performs no action of its
/// own. Return false to let the built-in handling run.
///
/// [button] is null when the message surface itself was tapped rather than a
/// button. The impression, the click log and the dismissal all happen regardless —
/// this hook replaces only the *action*, not the bookkeeping.
///
/// This is Braze's native `shouldProcess` / `onInAppMessageButtonClicked` hook,
/// which their Flutter SDK cannot expose to Dart at all.
typedef GameballOnAction = bool Function(
  GameballInAppMessage message,
  GameballMessageButton? button,
  GameballClickAction action,
);

/// How long the app must be backgrounded before returning counts as a new
/// session.
///
/// Matched to [defaultDisplayCooldown] on purpose. Because a message can only be
/// shown while the app is in the foreground, time-since-last-display is always at
/// least time-spent-in-background — so aligning the two guarantees the cooldown
/// can never block a warm session-start message. A shorter timeout reintroduces
/// the gap Braze lives with, where a session-start campaign is selected and then
/// silently suppressed.
///
/// The cooldown is now server-driven, so a backend that raises it above this
/// value reopens that gap. Deliberately not chased: the alternative is a session
/// timeout that changes under the host's feet.
const Duration defaultSessionTimeout = defaultDisplayCooldown;

/// How long artwork may take to load before its campaign is passed over.
///
/// An outer bound rather than an expected cost: it exists so a wedged image host
/// cannot stall the session-start evaluation, not to describe how long a normal
/// image takes. Generous, because passing over a campaign suppresses a message
/// the marketer scheduled, and that is the more expensive mistake of the two.
const Duration defaultArtworkPrefetchTimeout = Duration(seconds: 5);

/// How long to wait for current personalisation values before displaying.
///
/// The document's figure. Bounded because a message must never be blocked or
/// dropped by this call — on timeout the sync-time text is displayed, which is
/// the same text the customer would have seen with no personalisation at all.
const Duration defaultVariableTimeout = Duration(seconds: 2);

/// Wires fetching, evaluation, deferral, display and analytics together.
///
/// Owns no display policy of its own — [selectCampaign] decides what shows —
/// and no drawing. Its job is sequencing and the pending-message slot.
class InAppMessagingService {
  InAppMessagingService({
    required GameballMessageSource source,
    required GameballMessagePresenter presenter,
    required FrequencyCap frequencyCap,
    required CampaignCache campaignCache,
    required MessageAnalytics analytics,
    required bool Function() isHostWidgetOpen,
    required MessageNavigator navigator,
    required ArtworkPrefetcher prefetcher,
    required VariableSource variables,
    void Function(GameballInAppMessage message)? emit,
    DateTime Function()? clock,
    UrlLauncher? launcher,
    this.sessionTimeout = defaultSessionTimeout,
    this.prefetchTimeout = defaultArtworkPrefetchTimeout,
    this.variableTimeout = defaultVariableTimeout,
  })  : _source = source,
        _navigator = navigator,
        _presenter = presenter,
        _cap = frequencyCap,
        _cache = campaignCache,
        _analytics = analytics,
        _isHostWidgetOpen = isHostWidgetOpen,
        _prefetcher = prefetcher,
        _variables = variables,
        _emit = emit,
        _clock = clock ?? DateTime.now,
        _launcher = launcher ?? _defaultLauncher;

  final GameballMessageSource _source;
  final GameballMessagePresenter _presenter;
  final FrequencyCap _cap;
  final CampaignCache _cache;
  final MessageAnalytics _analytics;
  final bool Function() _isHostWidgetOpen;
  final MessageNavigator _navigator;
  final ArtworkPrefetcher _prefetcher;
  final VariableSource _variables;
  final void Function(GameballInAppMessage message)? _emit;
  final DateTime Function() _clock;
  final UrlLauncher _launcher;

  /// How long backgrounded before a resume counts as a new session.
  final Duration sessionTimeout;

  /// How long artwork may take to load before its campaign is passed over.
  final Duration prefetchTimeout;

  /// How long to wait for personalisation values before displaying anyway.
  final Duration variableTimeout;

  /// How long to wait on local storage before giving up on it.
  static const Duration _storeTimeout = Duration(seconds: 2);

  /// How long to wait for telemetry to go out before leaving the app.
  static const Duration _preActionFlushTimeout = Duration(milliseconds: 800);

  GameballAudience? _audience;
  GameballBeforeDisplay? _beforeDisplay;
  GameballOnAction? _onAction;
  List<InAppMessageCampaign> _campaigns = const <InAppMessageCampaign>[];

  /// Campaigns whose artwork is decoded and safe to display.
  ///
  /// Held beside [_campaigns] rather than filtering them, so the list stays a
  /// faithful record of what the backend sent and the diagnostics can say which
  /// campaign was passed over and why.
  Set<int> _artworkReady = const <int>{};

  /// Minimum gap between any two displays, as the last sync reported it.
  Duration _cooldown = defaultDisplayCooldown;

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

  /// Guards the window between deciding to display and actually displaying.
  ///
  /// Only a token-bearing message opens that window, by awaiting its variables.
  /// Without this, a trigger firing during the await would present a second
  /// message on top of the first.
  bool _presentationInFlight = false;

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
    GameballOnAction? onAction,
  }) async {
    final current = _audience;
    if (current is CustomerAudience && current.customerId == customerId) {
      iamLog('start ignored: already running for customer "$customerId"');
      return;
    }

    _beforeDisplay = beforeDisplay;
    _onAction = onAction;
    _resetFor(CustomerAudience(customerId));
    await _syncAndEvaluateSessionStart(loadPersisted: true);
  }

  /// Clears all state and dismisses anything on screen.
  void stop() {
    if (!isStarted) return;
    _presenter.dismiss();
    _pending = null;
    _campaigns = const <InAppMessageCampaign>[];
    _artworkReady = const <int>{};
    _presentationInFlight = false;
    _forgetVariables();
    _audience = null;
    _beforeDisplay = null;
    _onAction = null;
    // Logout is one of the two moments the process may not get another chance to
    // send. Buffered events are already on disk, so a failure here only delays
    // them; flushing now means they usually go out under the identity that
    // produced them.
    //
    // Disposed immediately after, not on completion: that leaves the in-flight
    // request to finish while guaranteeing a stopped module schedules nothing.
    unawaited(_analytics.flush());
    _analytics.dispose();
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
    unawaited(_syncAndEvaluateSessionStart(loadPersisted: true));
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
    // A purchase is an event named `purchase`, not a trigger type of its own:
    // the backend models it that way, so a campaign targeting purchases is
    // authored as an event trigger and filters on productId or price.
    _evaluate(GameballCustomEventOccurrence.purchase(
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
    // Re-synced, not just re-evaluated: a session start is when campaign edits,
    // expiries and eligibility changes land. Fire and forget, because the caller
    // is a lifecycle callback and the evaluation happens inside.
    unawaited(_syncAndEvaluateSessionStart());
  }

  /// Called when the app leaves the foreground, to time the absence.
  void onAppPaused() {
    if (!isStarted) return;
    _lastPausedAt = _clock();
    // The last point at which the OS reliably gives us time. An app killed from
    // the background never resumes, so anything still buffered would otherwise
    // wait for the next launch.
    unawaited(_analytics.flush());
  }

  /// Called when the Gameball profile widget closes, freeing the screen.
  void onHostWidgetClosed() => _retryPending();

  // ------------------------------------------------------------------ internals

  void _resetFor(GameballAudience audience) {
    _presenter.dismiss();
    _pending = null;
    _campaigns = const <InAppMessageCampaign>[];
    _artworkReady = const <int>{};
    _presentationInFlight = false;
    _forgetVariables();
    _audience = audience;
  }

  /// Drops any cached personalisation values.
  ///
  /// Guarded by a type test because `clear()` is an implementation detail of the
  /// caching wrapper rather than part of the seam — a source that does not cache
  /// has nothing to forget.
  void _forgetVariables() {
    final variables = _variables;
    if (variables is CachingVariableSource) variables.clear();
  }

  /// Reads persisted state, bounded so a wedged store cannot kill the feature.
  ///
  /// Every call here goes through a platform channel, and a channel that never
  /// answers is not something a `try` can catch — an unregistered
  /// `shared_preferences` simply never completes. Left unbounded, that means
  /// `start` never returns and **no message ever displays**, silently. Degrading
  /// to "no history" risks showing a once-ever campaign twice, which is a far
  /// smaller failure than the feature being dead.
  Future<GameballSyncResult?> _readPersisted(String customerId) async {
    try {
      await _cap.load(customerId).timeout(_storeTimeout);
      final cached = await _cache.read(customerId).timeout(_storeTimeout);
      return cached.campaigns.isEmpty ? null : cached;
    } on TimeoutException {
      iamLog('local storage did not respond within '
          '${_storeTimeout.inSeconds}s; continuing without history or cache');
      return null;
    } catch (error) {
      iamLog('could not read local state ($error)');
      return null;
    }
  }

  /// Syncs, then evaluates session start.
  ///
  /// Disk and network run **concurrently**: the display history gates the
  /// decision, not the request, so paying for them in series would delay the
  /// first message for no reason.
  ///
  /// The cache is applied only when the sync failed. That ordering is the
  /// backend's rule — *"on sync failure keep the previous unexpired cache"* — and
  /// it also removes the race a parallel read would otherwise create, where a slow
  /// cache read lands after a fast sync and clobbers fresher campaigns.
  Future<void> _syncAndEvaluateSessionStart({bool loadPersisted = false}) async {
    final audience = _audience;
    if (audience == null) return;

    Future<GameballSyncResult?>? persisted;
    if (loadPersisted && audience is CustomerAudience) {
      persisted = _readPersisted(audience.customerId);
      // Not awaited: recovering a previous run's unsent events has nothing to do
      // with showing this session's message.
      unawaited(_analytics.load());
    }

    var synced = false;
    try {
      final result = await _source.fetch(audience);
      _campaigns = result.campaigns;
      _cooldown = result.cooldown;
      synced = true;
      iamLog('synced ${_campaigns.length} campaign(s), '
          'cooldown ${_cooldown.inSeconds}s');

      final raw = result.rawJson;
      if (raw != null && audience is CustomerAudience) {
        unawaited(_cache.write(audience.customerId, raw));
      }
    } catch (error) {
      iamLog('sync failed ($error)');
    }

    final cached = await persisted;
    if (!synced && cached != null) {
      _campaigns = cached.campaigns;
      _cooldown = cached.cooldown;
      iamLog('falling back to ${_campaigns.length} cached campaign(s)');
    }

    await _prefetchArtwork();

    _evaluate(const GameballSessionStartOccurrence());
  }

  /// Loads the artwork of every campaign now held, before any of them displays.
  ///
  /// Awaited rather than left running: the impression is logged the moment the
  /// widget mounts, so artwork arriving a beat later means a view was counted of
  /// something the user could not see. Waiting is the point.
  ///
  /// Every campaign is warmed, not only the one about to show. An event trigger
  /// fires with no warning and no time to fetch, so a campaign waiting on
  /// `add_to_cart` depends on this having run at sync.
  Future<void> _prefetchArtwork() async {
    final campaigns = _campaigns;
    if (campaigns.isEmpty) {
      _artworkReady = const <int>{};
      return;
    }

    // Concurrent: these are independent downloads, and the slowest one is the
    // honest cost of the set.
    final ready = await Future.wait(campaigns.map(_isArtworkReady));

    _artworkReady = <int>{
      for (var i = 0; i < campaigns.length; i++)
        if (ready[i]) campaigns[i].campaignId,
    };
  }

  /// Whether one campaign's artwork loaded, bounded by [prefetchTimeout].
  Future<bool> _isArtworkReady(InAppMessageCampaign campaign) async {
    try {
      return await _prefetcher.prefetch(campaign.message).timeout(prefetchTimeout);
    } on TimeoutException {
      iamLog('campaign "${campaign.campaignId}" artwork did not load within '
          '${prefetchTimeout.inMilliseconds}ms');
      return false;
    } catch (error) {
      iamLog('campaign "${campaign.campaignId}" artwork failed ($error)');
      return false;
    }
  }

  void _evaluate(GameballTriggerOccurrence occurrence) {
    if (_campaigns.isEmpty) {
      iamLog('trigger ignored: no campaigns loaded');
      return;
    }

    // Artwork that has not loaded means the message would paint a hole where its
    // image belongs, and log an impression for it. Passing the campaign over
    // lets a lower-priority one that *is* ready take the slot instead.
    final displayable = <InAppMessageCampaign>[];
    for (final candidate in _campaigns) {
      if (_artworkReady.contains(candidate.campaignId)) {
        displayable.add(candidate);
      } else {
        iamLog('campaign "${candidate.campaignId}" passed over: artwork not '
            'ready');
      }
    }
    if (displayable.isEmpty) return;

    final campaign = selectCampaign(
      occurrence: occurrence,
      campaigns: displayable,
      capState: _cap.snapshot(),
      now: _clock(),
      cooldown: _cooldown,
    );
    if (campaign == null) return;

    // Observers see every selected message, whatever the host then decides.
    _emit?.call(campaign.message);

    switch (_decide(campaign.message)) {
      case GameballDisplayDecision.discard:
        iamLog('campaign "${campaign.campaignId}" discarded by beforeDisplay');
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
    if (_presentationInFlight) {
      _defer(campaign, 'another message is resolving its personalisation');
      return;
    }

    // The common path, and today the only one: no tokens means nothing to
    // fetch, so display stays synchronous and byte-identical to what it was
    // before personalisation existed.
    if (!messageHasTokens(campaign.message)) {
      _present(campaign, campaign.message);
      return;
    }

    _presentationInFlight = true;
    unawaited(_resolveThenPresent(campaign));
  }

  /// Fetches current values, then displays — bounded, and never at the cost of
  /// the display itself.
  Future<void> _resolveThenPresent(InAppMessageCampaign campaign) async {
    final audience = _audience;
    var message = campaign.message;

    try {
      if (audience is CustomerAudience) {
        final values =
            await _variables.fetch(audience.customerId).timeout(variableTimeout);
        message = substituteInto(message, values);
      }
    } on TimeoutException {
      iamLog('personalisation for campaign "${campaign.campaignId}" did not '
          'arrive within ${variableTimeout.inMilliseconds}ms; displaying the '
          'text from the last sync');
    } catch (error) {
      iamLog('personalisation for campaign "${campaign.campaignId}" failed '
          '($error); displaying the text from the last sync');
    } finally {
      _presentationInFlight = false;
    }

    // Re-checked rather than trusted: the screen can change during the await,
    // and the host can log out.
    if (!isStarted) {
      iamLog('campaign "${campaign.campaignId}" abandoned: messaging stopped '
          'while its personalisation was resolving');
      return;
    }
    if (_isHostWidgetOpen() || _presenter.isShowing) {
      _defer(campaign, 'the screen was taken while personalisation resolved');
      return;
    }

    _present(campaign, message);
  }

  /// Draws [message] for [campaign], and wires its callbacks.
  ///
  /// Takes the message separately from the campaign because personalisation
  /// displays a substituted copy, while every piece of bookkeeping — caps,
  /// impressions, the pending slot — still keys on the campaign.
  void _present(InAppMessageCampaign campaign, GameballInAppMessage message) {
    // Both local to this presentation, so a campaign shown again starts clean.
    //
    // `shown` exists because a message can be dismissed before its first frame
    // paints, and a dismissal without an impression would be nonsense. `engaged`
    // exists so the dismissal that follows a tap is not also counted as "shown
    // and ignored" — which is what makes `impressions = clicks + dismissals` hold
    // as an identity the backend can rely on.
    var shown = false;
    var engaged = false;

    final presented = _presenter.present(
      message: message,
      onShown: () {
        shown = true;
        // Recorded at impression, never at selection, so a deferred or
        // suppressed message does not burn its slot.
        _cap.recordDisplay(campaign.campaignId, _clock());
        _logEvent(campaign, GameballMessageEventType.impression);
      },
      onButtonPressed: (button) {
        engaged = true;
        // A button tap is a click carrying the button's id — the backend has no
        // separate button-click type, and `buttonId` presence is what
        // distinguishes it from a tap on the message surface.
        _logEvent(
          campaign,
          GameballMessageEventType.click,
          buttonId: button.id,
          url: _urlOf(button.action),
        );
        _act(campaign.message, button, button.action);
      },
      onMessagePressed: () {
        final action = campaign.message.clickAction;
        if (action == null) return;
        engaged = true;
        _logEvent(campaign, GameballMessageEventType.click, url: _urlOf(action));
        _act(campaign.message, null, action);
      },
      onDismissed: () {
        // Braze has no dismissal event at all: closing the X, tapping outside and
        // backgrounding the app all log nothing there, so "shown and ignored" is
        // invisible in their reporting. It costs one event here.
        if (shown && !engaged) {
          _logEvent(campaign, GameballMessageEventType.dismiss);
        }
        _retryPending();
      },
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
    if (displaced != null && displaced.campaignId != campaign.campaignId) {
      iamLog('pending campaign "${displaced.campaignId}" displaced by "${campaign.campaignId}"');
    }
    _pending = campaign;
    iamLog('campaign "${campaign.campaignId}" deferred: $reason');
  }

  /// Builds and records one analytics event for [campaign].
  ///
  /// The timestamp comes from the injected clock rather than the analytics
  /// implementation's own, so it is the moment the thing happened and so tests
  /// can assert it.
  void _logEvent(
    InAppMessageCampaign campaign,
    GameballMessageEventType type, {
    String? buttonId,
    String? url,
  }) {
    // A dashboard test send displays normally and reports nothing, so a
    // marketer's testing never reaches campaign statistics.
    if (campaign.isTest) return;

    _analytics.log(GameballMessageEvent(
      type: type,
      campaignId: campaign.campaignId,
      variationId: campaign.variationId,
      dispatchId: campaign.dispatchId,
      occurredAt: _clock(),
      buttonId: buttonId,
      url: url,
    ));
  }

  /// The destination of an action, when it has one. Reported alongside a click so
  /// the backend can attribute outbound traffic without re-deriving it.
  static String? _urlOf(GameballClickAction action) =>
      action is GameballOpenUrlAction ? action.url : null;

  void _retryPending() {
    final campaign = _pending;
    if (campaign == null) return;
    _pending = null;

    final capState = _cap.snapshot();
    if (capState.shownCampaignIds.contains(campaign.campaignId)) {
      iamLog('pending campaign "${campaign.campaignId}" dropped: already shown');
      return;
    }
    // Re-validated so a message deferred before another was displayed cannot
    // slip through inside the floor.
    if (isWithinFloor(capState: capState, now: _clock(), cooldown: _cooldown)) {
      _pending = campaign;
      return;
    }

    _tryPresent(campaign);
  }

  /// Offers the tap to the host, then dismisses, then acts.
  ///
  /// Dismissal comes *before* the action deliberately: a navigate action pushes a
  /// route, and leaving the overlay up during the transition would briefly cover
  /// the screen the user just asked for.
  void _act(
    GameballInAppMessage message,
    GameballMessageButton? button,
    GameballClickAction action,
  ) {
    final handledByHost = _askHost(message, button, action);
    _presenter.dismiss();
    if (handledByHost) {
      iamLog('action on message "${message.id}" handled by the host');
      return;
    }
    unawaited(_flushThenRun(action));
  }

  /// Sends buffered telemetry before an action that may take the user away.
  ///
  /// `open_url` and `navigate` can be the last thing that happens in this process
  /// — an external browser may never hand control back, and the OS can reclaim a
  /// backgrounded app at any point. Flushing first means the click that caused it
  /// is not the event most likely to be lost.
  ///
  /// Bounded, because a dead network must not delay a tap the user is waiting on.
  /// The events are already on disk either way, so the worst case is that they go
  /// out on the next launch instead.
  Future<void> _flushThenRun(GameballClickAction action) async {
    if (action is GameballOpenUrlAction || action is GameballNavigateAction) {
      try {
        await _analytics.flush().timeout(_preActionFlushTimeout);
      } on TimeoutException {
        iamLog('telemetry flush did not finish before the action; the events '
            'stay queued');
      } catch (error) {
        iamLog('telemetry flush failed before the action ($error)');
      }
    }
    await _runAction(action);
  }

  bool _askHost(
    GameballInAppMessage message,
    GameballMessageButton? button,
    GameballClickAction action,
  ) {
    final hook = _onAction;
    if (hook == null) return false;
    try {
      return hook(message, button, action);
    } catch (error) {
      // Falling back to the built-in action matches the no-hook behaviour, so a
      // buggy host loses its override rather than losing the action entirely.
      iamLog('onAction threw; falling back to built-in handling ($error)');
      return false;
    }
  }

  Future<void> _runAction(GameballClickAction action) async {
    switch (action) {
      case GameballDismissAction():
        return;
      case GameballNavigateAction(route: final route, arguments: final arguments):
        _navigator.pushNamed(route, arguments: arguments);
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
