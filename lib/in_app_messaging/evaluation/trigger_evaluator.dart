import '../iam_log.dart';
import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';
import '../models/quiet_hours.dart';
import '../source/message_source.dart' show defaultDisplayCooldown;
import 'frequency_cap.dart';

/// Chooses which campaign, if any, should display for a given [occurrence].
///
/// Pure apart from diagnostics: no async, no `BuildContext`, and no clock —
/// [now] is passed in so the floor is testable without waiting. It does log,
/// as the filters do, because a decision this function makes silently is a
/// decision nobody can debug. All display policy lives here, which is why this
/// is the most heavily tested unit in the module.
///
/// Order: filter by trigger match, drop expired, drop already-shown, drop layouts
/// this SDK cannot render, enforce quiet hours and the cooldown, then take the
/// highest priority — breaking ties on the order the backend listed them in,
/// which is the order the marketer chose.
InAppMessageCampaign? selectCampaign({
  required GameballTriggerOccurrence occurrence,
  required List<InAppMessageCampaign> campaigns,
  required CapState capState,
  required DateTime now,
  Duration cooldown = defaultDisplayCooldown,
  GameballQuietHours? quietHours,
}) {
  final eligible = <InAppMessageCampaign>[];
  for (final candidate in campaigns) {
    if (!triggerMatches(candidate.trigger, occurrence)) continue;
    // Enforced here and not only at fetch, because campaigns are cached for the
    // session: one fetched at 23:58 would otherwise keep firing all night, and
    // keep firing after the campaign was paused or archived.
    if (candidate.hasExpiredAt(now)) continue;
    if (!isRepeatEligible(campaign: candidate, capState: capState, now: now)) {
      continue;
    }
    // An unsupported layout is filtered here rather than refused at display
    // time, so a usable lower-priority campaign can still win.
    if (candidate.message.type == GameballMessageType.unsupported) continue;
    eligible.add(candidate);
  }

  if (eligible.isEmpty) return null;

  // Suppressed, not deferred. A quiet window is hours long while the pending
  // slot is in memory and dies with the process, so "retry when it ends" would
  // essentially never fire. Suppressing costs the occurrence and not the
  // campaign: it is selected again at the next trigger outside the window.
  //
  // Checked after eligibility so the log only mentions it when a message would
  // otherwise have displayed.
  if (quietHours != null && quietHours.contains(now)) {
    iamLog('${eligible.length} campaign(s) matched but it is inside the '
        'quiet-hours window (UTC); suppressed');
    return null;
  }

  if (isWithinFloor(capState: capState, now: now, cooldown: cooldown)) {
    // Named rather than silent. This is the one path where a campaign matched,
    // was in date, was repeat-eligible and renderable, and still produced
    // nothing — so without a line here "why didn't my campaign fire" is
    // unanswerable from the log, and a working cooldown reads as a broken
    // trigger. The occurrence is suppressed, not consumed: the next session
    // start outside the floor still gets it.
    iamLog('${eligible.length} campaign(s) matched but the '
        '${cooldown.inSeconds}s cooldown has not elapsed since the last '
        'message; suppressed');
    return null;
  }

  // Response order is the tie-break, and it is **meaningful rather than merely
  // deterministic**: the backend returns campaigns in the sequence the marketer
  // arranged them in the dashboard, so the array is itself the ranking —
  // confirmed with the backend team 2026-08-24.
  //
  // That distinction is the whole reason this comment is long. Read as "we need
  // *some* stable order", this invites a tidier-looking total order — ascending
  // campaignId is the obvious candidate — which would silently re-rank every tie
  // the dashboard had already settled. It is not interchangeable.
  //
  // Carrying the original index is what makes it hold: Dart's List.sort is not
  // stable, so comparing on priority alone would scramble equal-priority
  // campaigns once the list is long enough to trip the unstable path.
  //
  // `campaignOrdering` on the sync response is **not** this ranking, despite the
  // name — see the note on it in the port specification.
  final indexed = <(int, InAppMessageCampaign)>[
    for (var i = 0; i < eligible.length; i++) (i, eligible[i]),
  ];
  indexed.sort((a, b) {
    final byPriority = b.$2.priority.compareTo(a.$2.priority);
    return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
  });

  return indexed.first.$2;
}

/// Whether [campaign] may display again given what it has already done.
///
/// Two rules, both the backend's:
///
/// * **Not repeatable** means once ever. Enforced locally rather than relying on
///   the server stopping to send it, because the campaign is cached on the device
///   and a stale cache would show it again.
/// * **Repeatable** means after `minIntervalSeconds` since *this* campaign's own
///   last display. Distinct from the global cooldown, which applies between any
///   two messages from any campaign.
bool isRepeatEligible({
  required InAppMessageCampaign campaign,
  required CapState capState,
  required DateTime now,
}) {
  final lastShown = capState.lastDisplayByCampaign[campaign.campaignId];
  if (lastShown == null) return true;

  if (!campaign.repeatable) return false;

  final interval = campaign.minInterval;
  if (interval == null) return true;
  return now.difference(lastShown) >= interval;
}

/// Whether too little time has passed since the last display.
///
/// [cooldown] comes from the sync response rather than a constant, so the backend
/// can tune marketing pressure without a client release.
bool isWithinFloor({
  required CapState capState,
  required DateTime now,
  Duration cooldown = defaultDisplayCooldown,
}) {
  final last = capState.lastDisplayAt;
  if (last == null) return false;
  return now.difference(last) < cooldown;
}
