import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_apple/geolocator_apple.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('flutter.baseflow.com/geolocator_updates_apple');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late GeolocatorApple plugin;
  late List<MethodCall> calls;
  StreamSubscription<Position>? subscription;

  Future<void> emit(Object event) async {
    await messenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeSuccessEnvelope(event), (_) {});
    await pumpEventQueue();
  }

  setUp(() {
    plugin = GeolocatorApple();
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() async {
    await subscription?.cancel();
    subscription = null;
    await pumpEventQueue();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('waits for native acknowledgement and keeps it out of positions',
      () async {
    final positions = <Position>[];
    subscription = plugin
        .getPositionStream(
          locationSettings: AppleSettings(allowBackgroundLocationUpdates: true),
          requireForeground: true,
        )
        .listen(positions.add);
    var started = false;
    final ready =
        plugin.waitForPositionStreamStart().then((_) => started = true);
    await pumpEventQueue();
    expect(calls.single.arguments['requireForeground'], isTrue);
    expect(started, isFalse);
    await emit({'event': 'positionStreamStarted'});
    await ready;
    expect(positions, isEmpty);
    await emit({
      'latitude': 37.0,
      'longitude': 127.0,
      'timestamp': 1000,
      'accuracy': 5.0,
      'altitude': 0.0,
      'altitude_accuracy': 0.0,
      'heading': 0.0,
      'heading_accuracy': 0.0,
      'speed': 0.0,
      'speed_accuracy': 0.0,
    });
    expect(positions, hasLength(1));
    expect(calls.where((c) => c.method == 'listen'), hasLength(1));
  });

  test(
      'cancellation while waiting fails acknowledgement and allows fresh settings',
      () async {
    subscription =
        plugin.getPositionStream(requireForeground: true).listen((_) {});
    final failure =
        expectLater(plugin.waitForPositionStreamStart(), throwsStateError);
    await subscription!.cancel();
    subscription = null;
    await failure;
    await pumpEventQueue();
    subscription =
        plugin.getPositionStream(requireForeground: true).listen((_) {});
    await pumpEventQueue();
    await emit({'event': 'positionStreamStarted'});
    await plugin.waitForPositionStreamStart();
    expect(calls.where((c) => c.method == 'listen'), hasLength(2));
  });

  test('startup error fails acknowledgement and is delivered to the subscriber',
      () async {
    final errors = <Object>[];
    subscription = plugin
        .getPositionStream(requireForeground: true)
        .listen((_) {}, onError: errors.add);
    final failure = expectLater(
        plugin.waitForPositionStreamStart(), throwsA(isA<PlatformException>()));
    await pumpEventQueue();
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeErrorEnvelope(code: 'BACKGROUND_LOCATION_UNAVAILABLE'),
        (_) {});
    await failure;
    expect(errors, hasLength(1));
  });

  test('does not silently reuse preparation settings for guarded startup',
      () async {
    subscription = plugin
        .getPositionStream(
          locationSettings:
              AppleSettings(allowBackgroundLocationUpdates: false),
        )
        .listen((_) {});
    await pumpEventQueue();
    expect(() => plugin.getPositionStream(requireForeground: true),
        throwsStateError);
    await subscription!.cancel();
    subscription = null;
    await pumpEventQueue();
    subscription = plugin
        .getPositionStream(
          locationSettings: AppleSettings(allowBackgroundLocationUpdates: true),
          requireForeground: true,
        )
        .listen((_) {});
    await pumpEventQueue();
    expect(calls.last.arguments['allowBackgroundLocationUpdates'], isTrue);
    await emit({'event': 'positionStreamStarted'});
    await plugin.waitForPositionStreamStart();
  });
}
