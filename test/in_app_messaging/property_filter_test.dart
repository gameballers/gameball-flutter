import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/property_filter.dart';

GameballPropertyFilter filter(
  String property,
  GameballFilterOperator operator,
  Object value,
) {
  return GameballPropertyFilter(
    property: property,
    operator: operator,
    value: value,
  );
}

void main() {
  group('equality', () {
    test('matches an identical value', () {
      expect(
        filter('tier', GameballFilterOperator.equals, 'gold')
            .matches(<String, Object>{'tier': 'gold'}),
        isTrue,
      );
    });

    test('does not match a different value', () {
      expect(
        filter('tier', GameballFilterOperator.equals, 'gold')
            .matches(<String, Object>{'tier': 'silver'}),
        isFalse,
      );
    });

    test('matches across numeric types', () {
      expect(
        filter('quantity', GameballFilterOperator.equals, 2)
            .matches(<String, Object>{'quantity': 2.0}),
        isTrue,
        reason: 'JSON gives no control over int vs double',
      );
    });

    test('matches a stringly-typed number', () {
      expect(
        filter('quantity', GameballFilterOperator.equals, '2')
            .matches(<String, Object>{'quantity': 2}),
        isTrue,
        reason: 'a campaign authored with a quoted number should still work',
      );
    });

    test('notEquals is the inverse', () {
      expect(
        filter('tier', GameballFilterOperator.notEquals, 'gold')
            .matches(<String, Object>{'tier': 'silver'}),
        isTrue,
      );
      expect(
        filter('tier', GameballFilterOperator.notEquals, 'gold')
            .matches(<String, Object>{'tier': 'gold'}),
        isFalse,
      );
    });
  });

  group('ordering', () {
    test('greaterThan compares numerically', () {
      final f = filter('price', GameballFilterOperator.greaterThan, 100);

      expect(f.matches(<String, Object>{'price': 189.0}), isTrue);
      expect(f.matches(<String, Object>{'price': 100}), isFalse);
      expect(f.matches(<String, Object>{'price': 12.99}), isFalse);
    });

    test('greaterThanOrEqual includes the boundary', () {
      final f = filter('price', GameballFilterOperator.greaterThanOrEqual, 100);

      expect(f.matches(<String, Object>{'price': 100}), isTrue);
      expect(f.matches(<String, Object>{'price': 99.99}), isFalse);
    });

    test('lessThan and lessThanOrEqual mirror them', () {
      expect(
        filter('price', GameballFilterOperator.lessThan, 100)
            .matches(<String, Object>{'price': 99}),
        isTrue,
      );
      expect(
        filter('price', GameballFilterOperator.lessThanOrEqual, 100)
            .matches(<String, Object>{'price': 100}),
        isTrue,
      );
    });

    test('ordering a non-number refuses rather than guessing', () {
      expect(
        filter('tier', GameballFilterOperator.greaterThan, 100)
            .matches(<String, Object>{'tier': 'gold'}),
        isFalse,
      );
    });
  });

  group('contains', () {
    test('matches a substring, case-insensitively', () {
      final f = filter('category', GameballFilterOperator.contains, 'SHOE');

      expect(f.matches(<String, Object>{'category': 'running shoes'}), isTrue);
      expect(f.matches(<String, Object>{'category': 'headphones'}), isFalse);
    });
  });

  group('missing properties', () {
    test('never match, whatever the operator', () {
      for (final operator in GameballFilterOperator.values) {
        expect(
          filter('absent', operator, 'x').matches(<String, Object>{'other': 1}),
          isFalse,
          reason: 'a filter is a requirement, so absence is a failure — '
              'operator ${operator.name}',
        );
      }
    });
  });

  group('allFiltersMatch', () {
    const properties = <String, Object>{'price': 189.0, 'tier': 'gold'};

    test('an empty list matches anything', () {
      expect(allFiltersMatch(const <GameballPropertyFilter>[], properties), isTrue,
          reason: 'a campaign with no filters must behave exactly as before');
    });

    test('every filter must pass', () {
      expect(
        allFiltersMatch([
          filter('price', GameballFilterOperator.greaterThan, 100),
          filter('tier', GameballFilterOperator.equals, 'gold'),
        ], properties),
        isTrue,
      );
    });

    test('one failure fails the set', () {
      expect(
        allFiltersMatch([
          filter('price', GameballFilterOperator.greaterThan, 100),
          filter('tier', GameballFilterOperator.equals, 'silver'),
        ], properties),
        isFalse,
      );
    });
  });
}
