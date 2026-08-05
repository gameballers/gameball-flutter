import '../models/in_app_message.dart';
import '../models/in_app_message_campaign.dart';
import '../models/message_trigger.dart';
import 'frequency_cap.dart';

/// Chooses which campaign, if any, should display for an occurred [trigger].
///
/// Pure: no I/O, no async, no `BuildContext`, and no clock — [now] is passed in
/// so the 30-second floor is testable without waiting. All display policy lives
/// here, which is why this is the most heavily tested unit in the module.
///
/// Order: filter by trigger match, drop already-shown, drop layouts this SDK
/// cannot render, enforce the floor, then take the highest priority breaking
/// ties on response order.
InAppMessageCampaign? selectCampaign({
  required GameballMessageTrigger trigger,
  required List<InAppMessageCampaign> campaigns,
  required CapState capState,
  required DateTime now,
}) {
  final eligible = <InAppMessageCampaign>[];
  for (final candidate in campaigns) {
    if (!triggerMatches(candidate.trigger, trigger)) continue;
    if (capState.shownCampaignIds.contains(candidate.id)) continue;
    // An unsupported layout is filtered here rather than refused at display
    // time, so a usable lower-priority campaign can still win.
    if (candidate.message.type == GameballMessageType.unsupported) continue;
    eligible.add(candidate);
  }

  if (eligible.isEmpty) return null;
  if (isWithinFloor(capState: capState, now: now)) return null;

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
bool isWithinFloor({required CapState capState, required DateTime now}) {
  final last = capState.lastDisplayAt;
  if (last == null) return false;
  return now.difference(last) < minimumIntervalBetweenDisplays;
}
