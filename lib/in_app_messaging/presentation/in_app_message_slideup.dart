import 'package:flutter/material.dart';

import '../models/in_app_message.dart';
import 'message_view_metrics.dart';

/// How long the banner takes to slide in and out.
const Duration slideupTransition = Duration(milliseconds: 220);

/// The slideup layout: a banner at one edge of the screen.
///
/// Three things make it a different widget rather than a squashed modal:
///
/// * **Non-blocking.** There is no scrim, and it occupies only its own band, so
///   the app underneath stays usable. It is the one type that does not demand a
///   decision from the user.
/// * **No buttons.** The whole surface is the tap target, which is Braze's model
///   too — a banner this size has no room for actions, and a stray tap near a
///   button would be ambiguous.
/// * **Swipe to dismiss.** Because there is nothing else to close it with: a
///   slideup has no close glyph and often no auto-dismiss, so a drag towards its
///   own edge is the only exit. Without it a campaign with neither would be
///   permanent.
class GameballInAppMessageSlideup extends StatefulWidget {
  const GameballInAppMessageSlideup({
    super.key,
    required this.message,
    required this.onMessagePressed,
    required this.onDismissRequested,
  });

  final GameballInAppMessage message;

  /// Invoked when the banner is tapped. Only reachable when the campaign set a
  /// message-level action.
  final VoidCallback onMessagePressed;

  /// Invoked when the user swipes the banner away.
  ///
  /// Named "requested" because the widget only reports the gesture; the presenter
  /// decides what dismissal means and reports it for analytics.
  final VoidCallback onDismissRequested;

  @override
  State<GameballInAppMessageSlideup> createState() =>
      _GameballInAppMessageSlideupState();
}

class _GameballInAppMessageSlideupState
    extends State<GameballInAppMessageSlideup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: slideupTransition,
    vsync: this,
  );

  bool get _fromTop =>
      widget.message.slidePosition == GameballSlidePosition.top;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.message.style;
    final message = widget.message;

    // Only the banner's own band is laid out, so nothing else on screen is
    // covered and no hit test outside it is intercepted.
    return SafeArea(
      child: Align(
        alignment: _fromTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: Padding(
          padding: SlideupMetrics.margin,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: SlideupMetrics.maxWidth),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, _fromTop ? -1 : 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutCubic,
              )),
              child: Dismissible(
                key: const Key('gb_iam_slideup_dismissible'),
                // Only towards its own edge: a banner at the bottom swipes down,
                // one at the top swipes up. Sideways would fight a horizontal
                // scroll or a page view underneath.
                direction:
                    _fromTop ? DismissDirection.up : DismissDirection.down,
                onDismissed: (_) => widget.onDismissRequested(),
                child: Material(
                  key: const Key('gb_iam_slideup_surface'),
                  color: style.backgroundColor ?? theme.colorScheme.surface,
                  borderRadius:
                      BorderRadius.circular(SlideupMetrics.cornerRadius),
                  elevation: SlideupMetrics.elevation,
                  clipBehavior: Clip.antiAlias,
                  child: _wrapTappable(
                    Padding(
                      padding: SlideupMetrics.contentPadding,
                      child: Row(
                        children: [
                          if (message.iconUrl != null) _icon(message.iconUrl!),
                          Expanded(
                            child: Text(
                              // A slideup carries one line of copy. `body` is the
                              // slot the backend fills; `header` is accepted as a
                              // fallback so a campaign that used the wrong field
                              // still says something.
                              message.body ?? message.header ?? '',
                              key: const Key('gb_iam_slideup_text'),
                              textAlign: style.bodyAlign ?? TextAlign.start,
                              // Three lines then ellipsis, matching Braze. A
                              // banner that grows with its copy would eventually
                              // cover the screen it is meant not to block.
                              maxLines: SlideupMetrics.maxTextLines,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: style.bodyColor),
                            ),
                          ),
                          if (message.clickAction != null)
                            Padding(
                              padding:
                                  SlideupMetrics.chevronSpacing,
                              child: Icon(
                                // One icon, never swapped by hand.
                                // `Icons.chevron_right` carries
                                // `matchTextDirection: true`, so the Icon widget
                                // mirrors the glyph itself under RTL — which is
                                // what makes it point left in Arabic, where a
                                // right-pointing chevron reads as "go back"
                                // rather than "open".
                                //
                                // Choosing `chevron_left` here as well flipped it
                                // twice and it came out pointing right. A test
                                // cannot catch that by name: `find.byIcon`
                                // matches the codepoint, not the rendered
                                // geometry, so assert the direction the customer
                                // actually sees.
                                Icons.chevron_right,
                                size: SlideupMetrics.chevronSize,
                                color: style.bodyColor ??
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Makes the banner tappable only when the campaign supplied an action.
  ///
  /// Without one it stays inert rather than absorbing taps, and the chevron is
  /// omitted too — so the affordance matches the behaviour.
  Widget _wrapTappable(Widget child) {
    if (widget.message.clickAction == null) return child;
    return InkWell(
      key: const Key('gb_iam_slideup_tap'),
      onTap: widget.onMessagePressed,
      child: child,
    );
  }

  /// A fixed square, unlike the modal's proportional artwork.
  ///
  /// A banner has a fixed height, so an icon that sized itself to its own aspect
  /// ratio would change the banner's height with every campaign.
  Widget _icon(String url) {
    return Padding(
      // `end`, not `right`: the Row itself flips for Arabic, so a hard-coded
      // right margin would put the gap on the outside of the banner.
      padding: SlideupMetrics.iconSpacing,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SlideupMetrics.iconCornerRadius),
        child: Image.network(
          url,
          key: const Key('gb_iam_slideup_icon'),
          width: SlideupMetrics.iconSize,
          height: SlideupMetrics.iconSize,
          fit: BoxFit.cover,
          // An icon that fails to load must not leave a gap where it would have
          // been, or every broken image shifts the copy.
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
