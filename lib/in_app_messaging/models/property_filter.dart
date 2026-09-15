import '../iam_log.dart';

/// How a [GameballPropertyFilter] compares.
enum GameballFilterOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  contains,

  /// Inclusive numeric range. The dashboard authors it as one value, `"min,max"`.
  between,
}

/// One condition on a trigger's properties, e.g. `price > 100`.
///
/// Filters on the properties carried by the event, which is what lets a
/// campaign say "add_to_cart, but only above 100". Without this, a trigger can
/// only match on a name.
class GameballPropertyFilter {
  const GameballPropertyFilter({
    required this.property,
    required this.operator,
    required this.value,
  });

  final String property;
  final GameballFilterOperator operator;
  final Object value;

  /// Whether [properties] satisfies this condition.
  ///
  /// A missing property never matches: a filter is a requirement, so absence is
  /// a failure rather than something to ignore.
  bool matches(Map<String, Object> properties) {
    final actual = properties[property];
    if (actual == null) return false;

    switch (operator) {
      case GameballFilterOperator.equals:
        return _looseEquals(actual, value);
      case GameballFilterOperator.notEquals:
        return !_looseEquals(actual, value);
      case GameballFilterOperator.contains:
        return actual.toString().toLowerCase().contains(
              value.toString().toLowerCase(),
            );
      case GameballFilterOperator.greaterThan:
      case GameballFilterOperator.greaterThanOrEqual:
      case GameballFilterOperator.lessThan:
      case GameballFilterOperator.lessThanOrEqual:
        return _compareNumeric(actual);
      case GameballFilterOperator.between:
        return _isBetween(actual);
    }
  }

  /// [value] is `"min,max"` as the dashboard sends it, or a two-element list.
  /// Spaces around either bound are fine; both bounds are inclusive.
  bool _isBetween(Object actual) {
    final a = _asNum(actual);
    final bounds = _bounds();
    if (a == null || bounds == null) {
      iamLog('filter "$property" between skipped: "$actual" and "$value" do '
          'not give a number and a numeric range');
      return false;
    }
    final (low, high) = bounds;
    return a >= low && a <= high;
  }

  (num, num)? _bounds() {
    final parts = switch (value) {
      final List<Object?> list => list,
      final String text => text.split(','),
      _ => const <Object?>[],
    };
    if (parts.length != 2) return null;
    final low =
        _asNum(parts[0] is String ? (parts[0] as String).trim() : parts[0]);
    final high =
        _asNum(parts[1] is String ? (parts[1] as String).trim() : parts[1]);
    if (low == null || high == null) return null;
    return low <= high ? (low, high) : (high, low);
  }

  bool _compareNumeric(Object actual) {
    final a = _asNum(actual);
    final b = _asNum(value);
    if (a == null || b == null) {
      // Ordering a non-number is meaningless, so refuse rather than guess.
      iamLog('filter "$property" ${operator.name} skipped: '
          '"$actual" and "$value" are not both numeric');
      return false;
    }
    return switch (operator) {
      GameballFilterOperator.greaterThan => a > b,
      GameballFilterOperator.greaterThanOrEqual => a >= b,
      GameballFilterOperator.lessThan => a < b,
      GameballFilterOperator.lessThanOrEqual => a <= b,
      _ => false,
    };
  }

  /// Compares across numeric types and stringly-typed numbers, so a campaign
  /// authored with `"quantity": "2"` still matches an int `2`.
  static bool _looseEquals(Object a, Object b) {
    if (a == b) return true;
    final na = _asNum(a);
    final nb = _asNum(b);
    if (na != null && nb != null) return na == nb;
    return a.toString() == b.toString();
  }

  static num? _asNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}

/// Whether every filter in [filters] is satisfied. An empty list matches
/// anything, so a campaign with no filters behaves exactly as before.
bool allFiltersMatch(
  List<GameballPropertyFilter> filters,
  Map<String, Object> properties,
) {
  for (final filter in filters) {
    if (!filter.matches(properties)) return false;
  }
  return true;
}
