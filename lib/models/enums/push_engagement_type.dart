/// What the customer did with a Gameball push, as the backend's push-engagement
/// endpoint counts it.
///
/// The numbers are the backend's own (`PushEngagementType` in g-backend-v2) and
/// are sent as they are. Never renumber them.
enum PushEngagementType {
  /// Tapped the notification or one of its action buttons.
  clicked(1),

  /// Swiped it away, or tapped a "Later" / "No thanks" button. Not detected by
  /// this SDK: a pure-Dart SDK never sees a notification being swiped away.
  dismissed(2),

  /// Didn't tap, but opened the app on their own soon after receiving it. The
  /// click token is the push the SDK credits.
  influencedOpen(3);

  const PushEngagementType(this.value);

  /// The number the backend expects in `engagementType`.
  final int value;
}
