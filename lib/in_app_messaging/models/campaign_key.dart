/// Which sequence an id belongs to.
///
/// Not cosmetic. The backend's contract states that challenge ids and message
/// campaign ids are separate sequences that overlap numerically, so a bare int
/// cannot identify a campaign once both kinds share one list.
enum CampaignKind { message, game }

/// Identifies one campaign across both kinds.
///
/// Every game entry arrives with `campaignId: 0` — the field is deliberately
/// left empty rather than filled with a challenge id — so a game's identity is
/// its `gameCampaignId`. Keyed history therefore has to carry the kind as well
/// as the number, or one wheel displaying would suppress every other game.
final class CampaignKey {
  const CampaignKey.message(this.id) : kind = CampaignKind.message;
  const CampaignKey.game(this.id) : kind = CampaignKind.game;

  const CampaignKey._(this.kind, this.id);

  final CampaignKind kind;
  final int id;

  /// The form written to storage. Stable: changing it orphans display history.
  String get storageKey => '${kind.name}:$id';

  /// Reads [storageKey], and also a bare number.
  ///
  /// A bare number is how every history written before this change looks, and
  /// all of those are message campaigns — games did not exist yet. Reading them
  /// as messages is what stops an update re-showing every once-ever campaign.
  static CampaignKey? parse(String raw) {
    final bare = int.tryParse(raw);
    if (bare != null) return CampaignKey._(CampaignKind.message, bare);

    final separator = raw.indexOf(':');
    if (separator <= 0) return null;

    final id = int.tryParse(raw.substring(separator + 1));
    if (id == null) return null;

    final name = raw.substring(0, separator);
    for (final kind in CampaignKind.values) {
      if (kind.name == name) return CampaignKey._(kind, id);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CampaignKey && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => storageKey;
}
