import 'property_filter.dart';

/// The event name a purchase is reported under.
///
/// Reserved: the backend's campaign model has no purchase trigger type, so a
/// purchase reaches the trigger engine as an ordinary named event. A campaign
/// targeting purchases is authored as an event trigger on this name.
const String gameballPurchaseEventName = 'purchase';

/// What causes a campaign to display — the condition a campaign *declares*.
///
/// Sealed so that adding a trigger type makes the compiler list every site that
/// must handle it.
///
/// Distinct from [GameballTriggerOccurrence], which is what actually *happened*.
/// The two were one type while matching was name-only; property filters made the
/// split necessary, since an occurrence carries data a declaration does not.
sealed class GameballMessageTrigger {
  const GameballMessageTrigger();
}

/// Fires at the start of every session — the first one after launch (cold) and
/// each one that begins on returning to the foreground (warm).
///
/// There is deliberately no cold/warm discriminator: the backend distinguishes
/// first-time from returning users with audience targeting, not with a second
/// trigger type.
final class GameballSessionStartTrigger extends GameballMessageTrigger {
  const GameballSessionStartTrigger();
}

/// Fires when an event with this exact name is logged and every filter passes.
///
/// The only event-shaped trigger. Purchases match this too, under
/// [gameballPurchaseEventName], with their built-in fields exposed as filterable
/// properties — so "any purchase" is this trigger with no filters, and "specific
/// purchase" is this trigger filtered on `productId` or `price`.
final class GameballCustomEventTrigger extends GameballMessageTrigger {
  const GameballCustomEventTrigger(
    this.eventName, {
    this.filters = const <GameballPropertyFilter>[],
  });

  final String eventName;

  /// Conditions on the event's properties. Empty matches any properties.
  final List<GameballPropertyFilter> filters;
}

// ---------------------------------------------------------------- occurrences

/// Something that actually happened, which may satisfy a declared trigger.
sealed class GameballTriggerOccurrence {
  const GameballTriggerOccurrence();

  /// The data a filter can be evaluated against.
  Map<String, Object> get filterableProperties;
}

/// A session began.
final class GameballSessionStartOccurrence extends GameballTriggerOccurrence {
  const GameballSessionStartOccurrence();

  @override
  Map<String, Object> get filterableProperties => const <String, Object>{};
}

/// A named event was logged.
///
/// A purchase produces one of these too, named [gameballPurchaseEventName] —
/// see [GameballCustomEventOccurrence.purchase].
final class GameballCustomEventOccurrence extends GameballTriggerOccurrence {
  const GameballCustomEventOccurrence(
    this.eventName, {
    this.properties = const <String, Object>{},
  });

  /// A purchase, as the event a campaign can target.
  ///
  /// The built-ins are folded into the property map so they filter with the same
  /// syntax as anything the caller added. Built-ins go first, so a caller's
  /// property of the same name wins — their data is the more specific of the two.
  factory GameballCustomEventOccurrence.purchase({
    required String productId,
    required double price,
    required String currency,
    int quantity = 1,
    Map<String, Object> properties = const <String, Object>{},
  }) {
    return GameballCustomEventOccurrence(
      gameballPurchaseEventName,
      properties: <String, Object>{
        'productId': productId,
        'price': price,
        'currency': currency,
        'quantity': quantity,
        ...properties,
      },
    );
  }

  final String eventName;
  final Map<String, Object> properties;

  @override
  Map<String, Object> get filterableProperties => properties;
}

/// Whether [occurred] satisfies the [declared] trigger a campaign carries.
bool triggerMatches(
  GameballMessageTrigger declared,
  GameballTriggerOccurrence occurred,
) {
  return switch ((declared, occurred)) {
    (GameballSessionStartTrigger(), GameballSessionStartOccurrence()) => true,
    (
      GameballCustomEventTrigger(eventName: final name, filters: final filters),
      GameballCustomEventOccurrence(eventName: final fired),
    ) =>
      name == fired && allFiltersMatch(filters, occurred.filterableProperties),
    _ => false,
  };
}
