/// What causes a campaign to display.
///
/// Sealed so that adding a trigger type makes the compiler list every site that
/// must handle it.
sealed class GameballMessageTrigger {
  const GameballMessageTrigger();
}

/// Fires once when in-app messaging starts for a customer.
final class GameballSessionStartTrigger extends GameballMessageTrigger {
  const GameballSessionStartTrigger();
}

/// Fires when an event with this exact name is logged.
final class GameballCustomEventTrigger extends GameballMessageTrigger {
  const GameballCustomEventTrigger(this.eventName);

  final String eventName;
}

/// Whether [occurred] satisfies the [campaignTrigger] a campaign declares.
bool triggerMatches(
  GameballMessageTrigger campaignTrigger,
  GameballMessageTrigger occurred,
) {
  return switch ((campaignTrigger, occurred)) {
    (GameballSessionStartTrigger(), GameballSessionStartTrigger()) => true,
    (
      GameballCustomEventTrigger(eventName: final declared),
      GameballCustomEventTrigger(eventName: final fired),
    ) =>
      declared == fired,
    _ => false,
  };
}
