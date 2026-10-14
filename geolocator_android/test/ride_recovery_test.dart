import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart';

import 'event_channel_mock.dart';
import 'method_channel_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restart keeps the same event subscription receiving positions',
      () async {
    final controller = StreamController<Map<String, dynamic>>();
    final events = EventChannelMock(
      channelName: 'flutter.baseflow.com/geolocator_updates_android',
      stream: controller.stream,
    );
    final methods = MethodChannelMock(
      channelName: 'flutter.baseflow.com/geolocator_android',
      methods: [
        const MethodMock(methodName: 'restartPositionUpdates', result: true)
      ],
    );
    final plugin = GeolocatorAndroid();
    final received = <Position>[];
    final first = Completer<void>();
    final second = Completer<void>();
    final subscription = plugin.getPositionStream().listen((position) {
      received.add(position);
      if (received.length == 1) first.complete();
      if (received.length == 2) second.complete();
    });
    controller.add({'latitude': 1.0, 'longitude': 2.0, 'timestamp': 1000});
    await first.future;
    expect(await plugin.restartPositionUpdates(), isTrue);
    controller.add({'latitude': 1.1, 'longitude': 2.1, 'timestamp': 2000});
    await second.future;
    expect(events.log.map((call) => call.method), ['listen']);
    expect(methods.calledMethodName('restartPositionUpdates'), isTrue);
    expect(
        received.map((p) => p.timestamp.millisecondsSinceEpoch), [1000, 2000]);
    await subscription.cancel();
    await controller.close();
  });

  test('restart reports no active native stream', () async {
    MethodChannelMock(
      channelName: 'flutter.baseflow.com/geolocator_android',
      methods: [
        const MethodMock(methodName: 'restartPositionUpdates', result: false)
      ],
    );
    expect(await GeolocatorAndroid().restartPositionUpdates(), isFalse);
  });

  test('native acquisition failure becomes PositionUpdateException', () async {
    MethodChannelMock(
      channelName: 'flutter.baseflow.com/geolocator_android',
      methods: [
        MethodMock(
            methodName: 'restartPositionUpdates',
            result: PlatformException(code: 'ERROR_WHILE_ACQUIRING_POSITION'))
      ],
    );
    await expectLater(GeolocatorAndroid().restartPositionUpdates(),
        throwsA(isA<PositionUpdateException>()));
  });

  test('altitude datum survives parsing and JSON serialization', () {
    for (final datum in ['ellipsoid', 'meanSeaLevel', null]) {
      final position = AndroidPosition.fromMap({
        'latitude': 1.0,
        'longitude': 2.0,
        'timestamp': 1000,
        'altitude': 50.0,
        'altitude_reference': datum,
      });
      expect(position.altitudeReference, datum);
      expect(AndroidPosition.fromMap(position.toJson()), position);
    }
  });
}
