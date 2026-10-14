import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_apple/geolocator_apple.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator_apple');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('timeout cancels only its request while another call completes',
      () async {
    final pending = <String, Completer<Object?>>{};
    final cancelled = <String>[];
    final cancellation = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final id = (call.arguments as Map)['requestId'] as String;
      if (call.method == 'getCurrentPosition') {
        expect(pending.containsKey(id), isFalse);
        final result = Completer<Object?>();
        pending[id] = result;
        return result.future;
      }
      expect(call.method, 'cancelGetCurrentPosition');
      cancelled.add(id);
      pending[id]!.complete(null);
      cancellation.complete();
      return null;
    });
    final timedOut = GeolocatorApple().getCurrentPosition(
      locationSettings: const LocationSettings(
        timeLimit: Duration(milliseconds: 20),
      ),
    );
    final remaining = GeolocatorApple().getCurrentPosition();
    await expectLater(timedOut, throwsA(isA<TimeoutException>()));
    await cancellation.future;
    expect(pending.length, 2);
    expect(cancelled, [pending.keys.first]);
    pending.values.last.complete({'latitude': 37.0, 'longitude': 127.0});
    expect((await remaining).latitude, 37.0);
    expect(cancelled.length, 1);
  });

  for (final failure in <Object>[
    PlatformException(code: 'CANCEL_FAILED'),
    MissingPluginException(),
  ]) {
    test('cancellation failure preserves timeout: ${failure.runtimeType}',
        () async {
      final pending = Completer<Object?>();
      final attempted = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCurrentPosition') return pending.future;
        attempted.complete();
        throw failure;
      });
      await expectLater(
        GeolocatorApple().getCurrentPosition(
          locationSettings: const LocationSettings(
            timeLimit: Duration(milliseconds: 5),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await attempted.future;
      pending.complete(null);
      await Future<void>.delayed(Duration.zero);
    });
  }

  test('successful and failed requests do not send cancellation', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {'latitude': 37.0, 'longitude': 127.0};
    });
    await GeolocatorApple().getCurrentPosition(
      locationSettings: const LocationSettings(timeLimit: Duration(seconds: 1)),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw PlatformException(code: 'PERMISSION_DENIED');
    });
    await expectLater(
      GeolocatorApple().getCurrentPosition(),
      throwsA(isA<PermissionDeniedException>()),
    );
    expect(calls, ['getCurrentPosition', 'getCurrentPosition']);
  });
}
