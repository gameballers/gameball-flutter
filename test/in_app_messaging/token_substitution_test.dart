import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/in_app_messaging/models/in_app_message.dart';
import 'package:gameball_sdk/in_app_messaging/personalisation/token_substitution.dart';

GameballInAppMessage message({
  String? header,
  String? body,
  List<GameballMessageButton> buttons = const <GameballMessageButton>[],
}) =>
    GameballInAppMessage(
      id: 'm',
      type: GameballMessageType.modal,
      header: header,
      body: body,
      buttons: buttons,
    );

GameballMessageButton button(String text) => GameballMessageButton(
      id: 'b',
      text: text,
      action: const GameballDismissAction(),
    );

void main() {
  group('substituteTokens', () {
    const values = <String, String>{
      'first_name': 'Ahmed',
      'points_balance': '1,250',
    };

    test('replaces a known token', () {
      expect(substituteTokens('Hi {first_name}!', values), 'Hi Ahmed!');
    });

    test('replaces every occurrence', () {
      expect(
          substituteTokens('{first_name} {first_name}', values), 'Ahmed Ahmed');
    });

    test('inserts pre-formatted values verbatim', () {
      expect(substituteTokens('You have {points_balance}', values),
          'You have 1,250');
    });

    test('leaves an unknown token exactly as written', () {
      expect(substituteTokens('Hi {nickname}!', values), 'Hi {nickname}!',
          reason: 'a newer server may know tokens this SDK does not; blanking '
              'them would silently delete copy a marketer wrote');
    });

    test('leaves malformed braces alone', () {
      expect(substituteTokens('a { b } {2} {', values), 'a { b } {2} {');
    });

    test('an empty map changes nothing', () {
      expect(substituteTokens('Hi {first_name}', const <String, String>{}),
          'Hi {first_name}');
    });

    test('text with no braces is returned untouched', () {
      expect(substituteTokens('plain copy', values), 'plain copy');
    });

    test('a value containing braces is not substituted again', () {
      expect(
        substituteTokens('{a}', const <String, String>{'a': '{b}', 'b': 'no'}),
        '{b}',
        reason: 'one pass only — a value is data, not a template',
      );
    });
  });

  group('messageHasTokens', () {
    test('is false for plain copy', () {
      expect(messageHasTokens(message(header: 'Hi', body: 'there')), isFalse);
    });

    test('finds a token in the header', () {
      expect(messageHasTokens(message(header: 'Hi {first_name}')), isTrue);
    });

    test('finds a token in the body', () {
      expect(
          messageHasTokens(message(body: '{points_balance} points')), isTrue);
    });

    test('finds a token in a button label', () {
      expect(
        messageHasTokens(message(buttons: [button('Spend {points_balance}')])),
        isTrue,
      );
    });

    test('a bare brace with no token name does not count', () {
      expect(messageHasTokens(message(body: 'a { b')), isFalse,
          reason: 'this is the check that keeps the feature inert, so a false '
              'positive costs a network round trip before every display');
    });
  });

  group('tokensIn', () {
    test('finds every token across header, body and buttons', () {
      expect(
        tokensIn(message(
          header: 'Hi {first_name}',
          body: 'You have {points_balance} of {tier_target}',
          buttons: [button('Spend {points_balance}')],
        )),
        {'first_name', 'points_balance', 'tier_target'},
      );
    });

    test('is empty for copy with no tokens', () {
      expect(tokensIn(message(header: 'Hi', body: 'there')), isEmpty);
    });

    test('ignores malformed braces', () {
      expect(tokensIn(message(body: 'a { b } {2} {')), isEmpty);
    });

    test('reports a token once however often it appears', () {
      expect(tokensIn(message(body: '{a} {a} {a}')), {'a'});
    });
  });

  group('substituteInto', () {
    test('rewrites header, body and button labels together', () {
      final result = substituteInto(
        message(
          header: 'Hi {first_name}',
          body: 'You have {points_balance}',
          buttons: [button('Spend {points_balance}')],
        ),
        const <String, String>{'first_name': 'Ahmed', 'points_balance': '1,250'},
      );

      expect(result.header, 'Hi Ahmed');
      expect(result.body, 'You have 1,250');
      expect(result.buttons.single.text, 'Spend 1,250');
    });

    test('leaves everything else identical', () {
      final original = message(header: 'Hi {first_name}');
      final result =
          substituteInto(original, const <String, String>{'first_name': 'A'});

      expect(result.id, original.id);
      expect(result.type, original.type);
      expect(result.layout, original.layout);
      expect(result.showCloseButton, original.showCloseButton);
      expect(result.dismissOnScrimTap, original.dismissOnScrimTap);
    });

    test('a button keeps its id and action', () {
      final result = substituteInto(
        message(buttons: [button('Spend {points_balance}')]),
        const <String, String>{'points_balance': '1,250'},
      );

      expect(result.buttons.single.id, 'b',
          reason: 'the id is what click analytics report');
      expect(result.buttons.single.action, isA<GameballDismissAction>());
    });

    test('an empty map returns the message unchanged', () {
      final original = message(header: 'Hi {first_name}');

      expect(substituteInto(original, const <String, String>{}),
          same(original));
    });

    test('a null header stays null', () {
      final result = substituteInto(
        message(body: 'hi'),
        const <String, String>{'first_name': 'A'},
      );

      expect(result.header, isNull);
    });
  });
}
