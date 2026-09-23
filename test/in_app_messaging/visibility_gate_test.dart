import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/presentation/visibility_gate.dart';

/// Counts how many times its state was created, which is what a torn-down and
/// rebuilt subtree looks like from the inside.
class _Probe extends StatefulWidget {
  const _Probe(this.onInit);
  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('becoming visible does not rebuild the subtree', (tester) async {
    // The bug this guards: a reward campaign's WebView was remounted the moment
    // the message became visible, so the page loaded twice and the SDK logged
    // two impressions for one message.
    var initCount = 0;
    Widget build(bool visible) => Directionality(
          textDirection: TextDirection.ltr,
          child: VisibilityGate(
            visible: visible,
            child: _Probe(() => initCount++),
          ),
        );

    await tester.pumpWidget(build(false));
    expect(initCount, 1);

    await tester.pumpWidget(build(true));
    expect(initCount, 1, reason: 'the child must survive the visibility flip');
  });

  testWidgets('a hidden gate still lays its child out', (tester) async {
    // Offstage and an invisible Visibility both collapse the child to zero
    // size. A WebView measured at 0x0 lays its page out against a zero
    // viewport, which defeats the point of loading it before it is shown.
    // Centre it so the child is laid out at its own size rather than forced to
    // the root's tight constraints, which is what makes the assertion mean
    // something.
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: VisibilityGate(
          visible: false,
          child: SizedBox(width: 320, height: 480, key: Key('child')),
        ),
      ),
    ));

    expect(tester.getSize(find.byKey(const Key('child'))), const Size(320, 480));
  });

  testWidgets('a hidden gate still paints, at a non-zero opacity',
      (tester) async {
    // Load-bearing, and it looks like a typo. Opacity short-circuits at zero —
    // RenderOpacity skips painting the child — and an unpainted platform view
    // is one WebKit stops compositing, whereupon it suspends the page's render
    // loop. Measured on iOS: at zero the widget sat on its loading skeleton for
    // the full 12s timeout and was dropped unshown; at 1/255 it loads normally.
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: VisibilityGate(visible: false, child: SizedBox.shrink()),
    ));

    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, greaterThan(0),
        reason: 'zero opacity stops the WebView loading at all');
    expect(opacity.opacity, lessThan(0.01), reason: 'and must be invisible');
  });

  testWidgets('a hidden gate lets taps through to what is beneath',
      (tester) async {
    var tapsBeneath = 0;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => tapsBeneath++,
            child: const SizedBox.expand(child: ColoredBox(color: Color(0xFF000000))),
          ),
          VisibilityGate(
            visible: false,
            child: GestureDetector(
              onTap: () {},
              child: const SizedBox.expand(
                  child: ColoredBox(color: Color(0xFFFFFFFF))),
            ),
          ),
        ],
      ),
    ));

    await tester.tapAt(const Offset(100, 100));
    expect(tapsBeneath, 1, reason: 'an invisible scrim must not freeze the app');
  });
}
