import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gameball_sdk/gameball_sdk.dart';
import 'package:gameball_sdk/models/requests/event.dart';
import 'package:gameball_sdk/models/requests/initialize_customer_request.dart';
import 'package:gameball_sdk/models/requests/gameball_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Sends one event against a stubbed transport and returns what the host was
/// told.
Future<({bool? success, Object? error})> sendEventWithStatus(int status) async {
  final app = GameballApp.getInstance();
  app.init(GameballConfigBuilder().apiKey('key').lang('en').build());

  bool? reported;
  Object? reportedError;

  await http.runWithClient(
    () async {
      final done = Completer<void>();
      app.sendEvent(
        EventBuilder().customerId('c1').eventName('view_product_page').build(),
        (success, error) {
          reported = success;
          reportedError = error;
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 5));
    },
    () => MockClient((_) async => http.Response('', status)),
  );

  return (success: reported, error: reportedError);
}

/// Initializes a customer against a stubbed transport and returns what the host
/// was told.
Future<({dynamic response, Object? error, bool calledBack})>
    initializeWithStatus(int status, {String body = '{"gameballId": 1}'}) async {
  final app = GameballApp.getInstance();
  app.init(GameballConfigBuilder().apiKey('key').lang('en').build());

  Object? reportedResponse;
  Object? reportedError;
  var calledBack = false;

  await http.runWithClient(
    () async {
      final done = Completer<void>();
      await app.initializeCustomer(
        InitializeCustomerRequestBuilder().customerId('c1').build(),
        (response, error) {
          calledBack = true;
          reportedResponse = response;
          reportedError = error;
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    },
    () => MockClient((_) async => http.Response(body, status)),
  );

  return (
    response: reportedResponse,
    error: reportedError,
    calledBack: calledBack
  );
}

void main() {
  group('sendEvent reports the backend verdict', () {
    test('an accepted event is a success', () async {
      // The events endpoint answers 202, not 200 — confirmed against alpha and
      // already the default in the analytics request tests.
      final result = await sendEventWithStatus(202);

      expect(result.error, isNull);
      expect(result.success, isTrue,
          reason: '202 Accepted means the backend took the event');
    });

    test('a 200 is still a success', () async {
      final result = await sendEventWithStatus(200);

      expect(result.success, isTrue);
    });

    test('a rejected event is a failure', () async {
      final result = await sendEventWithStatus(400);

      expect(result.success, isNot(isTrue));
    });
  });

  group('initializeCustomer reports the backend verdict', () {
    test('a created customer is a success', () async {
      final result = await initializeWithStatus(200);

      expect(result.calledBack, isTrue);
      expect(result.error, isNull);
      expect(result.response, isNotNull);
    });

    test('a rejected registration invokes the callback with the error',
        () async {
      // The host has no other way to learn the call failed: the SDK's future
      // chain has no catchError, so the exception escapes the zone instead.
      final result = await initializeWithStatus(401, body: '');

      expect(result.calledBack, isTrue,
          reason: 'a failure must reach the host, not vanish into the zone');
      expect(result.error, isNotNull);
    });
  });
}
