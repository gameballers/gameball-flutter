import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/message_view_metrics.dart';

/// WCAG 2.1 contrast ratio between two opaque colours.
///
/// `computeLuminance` is Flutter's implementation of the same relative-luminance
/// formula the standard defines, so this is the standard's ratio verbatim rather
/// than an approximation of it.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('the derived close glyph', () {
    test('clears the 3:1 minimum for non-text controls on any background', () {
      // The full grey ramp, because the failure would be at the crossover
      // rather than at either end, plus the saturated colours a campaign is
      // actually likely to pick.
      final backgrounds = <Color>[
        for (var value = 0; value <= 255; value++)
          Color.fromARGB(255, value, value, value),
        const Color(0xFFF5C518), // a yellow promo card
        const Color(0xFF2C6BB0), // mid blue
        const Color(0xFF6DC2EE), // the pool water on the live QA poster
        const Color(0xFF111827), // the live slideup background
        const Color(0xFF1F2937),
        const Color(0xFFF9FAFB),
      ];

      for (final background in backgrounds) {
        final glyph = resolveCloseGlyphColor(backgroundColor: background)!;
        expect(
          _contrast(glyph, background),
          greaterThanOrEqualTo(3.0),
          reason: 'background $background resolved to $glyph',
        );
      }
    });

    test('a fixed glyph colour could not — which is why it is derived', () {
      // Both halves of the pair fail against the background the other half is
      // for. Neither is safe alone, and that is the whole argument for
      // deriving rather than defaulting.
      expect(
        _contrast(MessageMetrics.closeGlyphOnDark, const Color(0xFFFFFFFF)),
        lessThan(3.0),
      );
      expect(
        _contrast(MessageMetrics.closeGlyphOnLight, const Color(0xFF111827)),
        lessThan(3.0),
      );
    });

    test('a campaign colour is used verbatim, contrast or not', () {
      // Deliberately unreadable. The campaign asked for exactly this, and
      // second-guessing it is how a brand colour silently becomes something
      // else.
      expect(
        resolveCloseGlyphColor(
          campaignColor: const Color(0xFFFEFEFE),
          backgroundColor: const Color(0xFFFFFFFF),
        ),
        const Color(0xFFFEFEFE),
      );
    });

    test('no background means no opinion — the host theme decides', () {
      expect(resolveCloseGlyphColor(), isNull);
    });

    test('the threshold is where the two glyph colours change places', () {
      // Pins the direction either side of the documented crossover, so a port
      // that inverts the comparison fails here rather than in a screenshot.
      const justBelow = Color(0xFF747474); // luminance a hair under 0.179
      const justAbove = Color(0xFF767676);

      expect(justBelow.computeLuminance(),
          lessThan(MessageMetrics.closeGlyphLuminanceThreshold));
      expect(justAbove.computeLuminance(),
          greaterThan(MessageMetrics.closeGlyphLuminanceThreshold));

      expect(resolveCloseGlyphColor(backgroundColor: justBelow),
          MessageMetrics.closeGlyphOnDark);
      expect(resolveCloseGlyphColor(backgroundColor: justAbove),
          MessageMetrics.closeGlyphOnLight);
    });
  });
}
