import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';
import '../source/message_source.dart' show defaultDisplayCooldown;
import 'frequency_cap.dart';

/// Chooses which campaign, if any, should display for a given [occurrence].
///
/// Pure: no I/O, no async, no `BuildContext`, and no clock — [now] is passed in
/// so the 30-second floor is testable without waiting. All display policy lives
/// here, which is why this is the most heavily tested unit in the module.
///
/// Order: filter by trigger match, drop expired, drop already-shown, drop layouts
/// this SDK cannot render, enforce the cooldown, then take the highest priority
/// breaking ties on response order.
InAppMessageCampaign? selectCampaign({
  required GameballTriggerOccurrence occurrence,
  required List<InAppMessageCampaign> campaigns,
  required CapState capState,
  required DateTime now,
  Duration cooldown = defaultDisplayCooldown,
}) {
  final eligible = <InAppMessageCampaign>[];
  for (final candidate in campaigns) {
    if (!triggerMatches(candidate.trigger, occurrence)) continue;
    // Enforced here and not only at fetch, because campaigns are cached for the
    // session: one fetched at 23:58 would otherwise keep firing all night, and
    // keep firing after the campaign was paused or archived.
    if (candidate.hasExpiredAt(now)) continue;
    if (capState.shownCampaignIds.contains(candidate.campaignId)) continue;
    // An unsupported layout is filtered here rather than refused at display
    // time, so a usable lower-priority campaign can still win.
    if (candidate.message.type == GameballMessageType.unsupported) continue;
    eligible.add(candidate);
  }

  if (eligible.isEmpty) return null;
  if (isWithinFloor(capState: capState, now: now, cooldown: cooldown)) return null;

  // Dart's List.sort is not stable, so ordering by priority alone would make
  // tie-breaks arbitrary. Carrying the original index keeps "ties break on
  // response order" true regardless of list length.
  final indexed = <(int, InAppMessageCampaign)>[
    for (var i = 0; i < eligible.length; i++) (i, eligible[i]),
  ];
  indexed.sort((a, b) {
    final byPriority = b.$2.priority.compareTo(a.$2.priority);
    return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
  });

  return indexed.first.$2;
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
