import 'property_filter.dart';

/// The event name `logPurchase` sends to the events endpoint.
///
/// Reserved: the backend and campaign authors both need to know what a purchase
/// looks like as an event, since `logPurchase` reaches the same endpoint as any
/// other event.
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
/// Braze has a single session-start trigger and distinguishes first-time from
/// returning users with segment filters rather than a second trigger type, so
/// there is deliberately no cold/warm discriminator here.
final class GameballSessionStartTrigger extends GameballMessageTrigger {
  const GameballSessionStartTrigger();
}

/// Fires when an event with this exact name is logged and every filter passes.
final class GameballCustomEventTrigger extends GameballMessageTrigger {
  const GameballCustomEventTrigger(
    this.eventName, {
    this.filters = const <GameballPropertyFilter>[],
  });

  final String eventName;

  /// Conditions on the event's properties. Empty matches any properties.
  final List<GameballPropertyFilter> filters;
}

/// Fires on any purchase at all, unfiltered.
final class GameballAnyPurchaseTrigger extends GameballMessageTrigger {
  const GameballAnyPurchaseTrigger();
}

/// Fires on a purchase matching [productId] and/or [filters].
///
/// The purchase built-ins — `productId`, `price`, `currency`, `quantity` — are
/// folded into the filterable property map, so they filter with the same syntax
/// as custom properties.
final class GameballSpecificPurchaseTrigger extends GameballMessageTrigger {
  const GameballSpecificPurchaseTrigger({
    this.productId,
    this.filters = const <GameballPropertyFilter>[],
  });

  final String? productId;
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
final class GameballCustomEventOccurrence extends GameballTriggerOccurrence {
  const GameballCustomEventOccurrence(
    this.eventName, {
    this.properties = const <String, Object>{},
  });

  final String eventName;
  final Map<String, Object> properties;

  @override
  Map<String, Object> get filterableProperties => properties;
}

/// A purchase was logged.
final class GameballPurchaseOccurrence extends GameballTriggerOccurrence {
  const GameballPurchaseOccurrence({
    required this.productId,
    required this.price,
    required this.currency,
    this.quantity = 1,
    this.properties = const <String, Object>{},
  });

  final String productId;
  final double price;
  final String currency;
  final int quantity;
  final Map<String, Object> properties;

  /// Built-ins first, so a campaign's custom property of the same name wins —
  /// the campaign author's data is the more specific of the two.
  @override
  Map<String, Object> get filterableProperties => <String, Object>{
        'productId': productId,
        'price': price,
        'currency': currency,
        'quantity': quantity,
        ...properties,
      };
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
    (GameballAnyPurchaseTrigger(), GameballPurchaseOccurrence()) => true,
    (
      GameballSpecificPurchaseTrigger(
        productId: final wanted,
        filters: final filters
      ),
      GameballPurchaseOccurrence(productId: final bought),
    ) =>
      (wanted == null || wanted == bought) &&
          allFiltersMatch(filters, occurred.filterableProperties),
    _ => false,
  };
}
