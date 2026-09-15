/// Who messages are fetched for.
///
/// Sealed and tagged on the wire so a device-scoped variant can be added
/// without changing the request contract or any existing signature.
sealed class GameballAudience {
  const GameballAudience();

  Map<String, dynamic> toJson();
}

/// An identified customer.
final class CustomerAudience extends GameballAudience {
  const CustomerAudience(this.customerId);

  final String customerId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'customer',
        'customerId': customerId,
      };
}
