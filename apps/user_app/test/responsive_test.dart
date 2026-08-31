import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/core/responsive.dart';

/// Sizes the real test surface, so MediaQuery and the constraints a child
/// actually receives agree. Overriding MediaQuery alone does not change
/// layout constraints, which makes such a test pass or fail for the wrong
/// reason.
Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

Future<void> resetSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(null);
  tester.view.reset();
}

void main() {
  group('window size classes map to real devices', () {
    test('small and large phones are compact', () {
      expect(Breakpoints.fromWidth(320), WindowSize.compact); // iPhone SE
      expect(Breakpoints.fromWidth(360), WindowSize.compact); // common Android
      expect(Breakpoints.fromWidth(390), WindowSize.compact); // iPhone 15
      expect(Breakpoints.fromWidth(430), WindowSize.compact); // iPhone Pro Max
    });

    test('phone landscape and small tablets are medium', () {
      expect(Breakpoints.fromWidth(640), WindowSize.medium);
      expect(Breakpoints.fromWidth(768), WindowSize.medium); // iPad portrait
    });

    test('large tablets are expanded', () {
      expect(Breakpoints.fromWidth(1024), WindowSize.expanded); // iPad landscape
      expect(Breakpoints.fromWidth(1180), WindowSize.expanded); // iPad Pro 11"
    });

    test('desktop browsers are large', () {
      expect(Breakpoints.fromWidth(1280), WindowSize.large);
      expect(Breakpoints.fromWidth(1920), WindowSize.large);
    });

    test('boundaries land on the correct side', () {
      expect(Breakpoints.fromWidth(599), WindowSize.compact);
      expect(Breakpoints.fromWidth(600), WindowSize.medium);
      expect(Breakpoints.fromWidth(839), WindowSize.medium);
      expect(Breakpoints.fromWidth(840), WindowSize.expanded);
      expect(Breakpoints.fromWidth(1199), WindowSize.expanded);
      expect(Breakpoints.fromWidth(1200), WindowSize.large);
    });
  });

  group('navigation switches at the right size', () {
    test('phones get a bottom bar, never a rail', () {
      expect(WindowSize.compact.usesNavigationRail, isFalse);
    });
    test('tablets and desktop get a rail', () {
      expect(WindowSize.medium.usesNavigationRail, isTrue);
      expect(WindowSize.expanded.usesNavigationRail, isTrue);
      expect(WindowSize.large.usesNavigationRail, isTrue);
    });
    test('only the widest layout extends the rail with labels', () {
      expect(WindowSize.medium.usesExtendedRail, isFalse);
      expect(WindowSize.expanded.usesExtendedRail, isFalse);
      expect(WindowSize.large.usesExtendedRail, isTrue);
    });
  });

  group('extra width becomes more columns, not wider rows', () {
    test('grid columns grow with the window', () {
      expect(WindowSize.compact.gridColumns, 1);
      expect(WindowSize.medium.gridColumns, 2);
      expect(WindowSize.large.gridColumns, 3);
    });
    test('forms stay single column on phones', () {
      expect(WindowSize.compact.formColumns, 1);
      expect(WindowSize.medium.formColumns, 2);
    });
  });

  testWidgets('reading width is capped on a desktop browser', (tester) async {
    await pumpAt(
      tester,
      const Size(1920, 1080),
      const ContentWidth.reading(child: SizedBox(key: Key('c'), height: 10)),
    );
    // Must actually be the cap, not a collapsed zero-width child.
    expect(
      tester.getSize(find.byKey(const Key('c'))).width,
      Breakpoints.readingWidth,
    );
    await resetSurface(tester);
  });

  testWidgets('a phone uses the full width', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 800),
      const ContentWidth.reading(child: SizedBox(key: Key('c'), height: 10)),
    );
    expect(tester.getSize(find.byKey(const Key('c'))).width, 360);
    await resetSurface(tester);
  });

  testWidgets('card grid is one column on a phone', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 900),
      ResponsiveCardGrid(
        children:
            List.generate(4, (i) => SizedBox(key: Key('card$i'), height: 60)),
      ),
    );
    final xs = List.generate(
        4, (i) => tester.getTopLeft(find.byKey(Key('card$i'))).dx).toSet();
    expect(xs.length, 1, reason: 'a phone should stack cards in one column');
    await resetSurface(tester);
  });

  testWidgets('card grid splits into columns on a tablet', (tester) async {
    await pumpAt(
      tester,
      const Size(1024, 900),
      ResponsiveCardGrid(
        children:
            List.generate(4, (i) => SizedBox(key: Key('card$i'), height: 60)),
      ),
    );
    final xs = List.generate(
        4, (i) => tester.getTopLeft(find.byKey(Key('card$i'))).dx).toSet();
    expect(xs.length, greaterThan(1),
        reason: 'wide windows should lay cards out in multiple columns');
    await resetSurface(tester);
  });

  testWidgets('form fields stack on a phone', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 800),
      const ResponsiveFieldRow(children: [
        SizedBox(key: Key('a'), height: 40),
        SizedBox(key: Key('b'), height: 40),
      ]),
    );
    final ys = {
      tester.getTopLeft(find.byKey(const Key('a'))).dy,
      tester.getTopLeft(find.byKey(const Key('b'))).dy,
    };
    expect(ys.length, 2, reason: 'phones stack fields vertically');
    await resetSurface(tester);
  });

  testWidgets('form fields sit side by side on a tablet', (tester) async {
    await pumpAt(
      tester,
      const Size(1024, 800),
      const ResponsiveFieldRow(children: [
        SizedBox(key: Key('a'), height: 40),
        SizedBox(key: Key('b'), height: 40),
      ]),
    );
    final ys = {
      tester.getTopLeft(find.byKey(const Key('a'))).dy,
      tester.getTopLeft(find.byKey(const Key('b'))).dy,
    };
    expect(ys.length, 1, reason: 'tablets place fields on one row');
    await resetSurface(tester);
  });

  testWidgets('no overflow at the narrowest supported phone', (tester) async {
    // 320dp is the smallest width Omelo supports. A RenderFlex overflow here
    // would be a visible yellow-and-black stripe on a real device.
    await pumpAt(
      tester,
      const Size(320, 640),
      ContentWidth(
        child: ResponsiveCardGrid(
          children: List.generate(
            3,
            (i) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Delivery Executive $i, Sector 18 Noida'),
                    ),
                    const Text('4.1 km'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await resetSurface(tester);
  });
}
