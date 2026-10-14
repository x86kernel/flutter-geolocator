import 'dart:async';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// An implementation of [GeolocatorPlatform] that uses method channels.
class GeolocatorApple extends GeolocatorPlatform {
  /// The method channel used to interact with the native platform.
  static const _methodChannel =
      MethodChannel('flutter.baseflow.com/geolocator_apple');

  /// The event channel used to receive [Position] updates from the native
  /// platform.
  static const _eventChannel =
      EventChannel('flutter.baseflow.com/geolocator_updates_apple');

  /// The event channel used to receive [LocationServiceStatus] updates from the
  /// native platform.
  static const _serviceStatusEventChannel =
      EventChannel('flutter.baseflow.com/geolocator_service_updates_apple');

  /// Registers this class as the default instance of [GeolocatorPlatform].
  static void registerWith() {
    GeolocatorPlatform.instance = GeolocatorApple();
  }

  /// On Android devices you can set [forcedLocationManager]
  /// to true to force the plugin to use the [LocationManager] to determine the
  /// position instead of the [FusedLocationProviderClient]. On iOS this is
  /// ignored.
  bool forcedLocationManager = false;

  Stream<Position>? _positionStream;
  Completer<void>? _positionStreamStarted;
  Stream<ServiceStatus>? _serviceStatusStream;

  @override
  Future<LocationPermission> checkPermission() async {
    try {
      // ignore: omit_local_variable_types
      final int permission =
          await _methodChannel.invokeMethod('checkPermission');

      return permission.toLocationPermission();
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Future<LocationPermission> requestPermission() async {
    try {
      // ignore: omit_local_variable_types
      final int permission =
          await _methodChannel.invokeMethod('requestPermission');

      return permission.toLocationPermission();
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async => _methodChannel
      .invokeMethod<bool>('isLocationServiceEnabled')
      .then((value) => value ?? false);

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    try {
      final parameters = <String, dynamic>{
        'forceLocationManager': forceLocationManager,
      };

      final positionMap =
          await _methodChannel.invokeMethod('getLastKnownPosition', parameters);

      return positionMap != null ? Position.fromMap(positionMap) : null;
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    final int accuracy =
        await _methodChannel.invokeMethod('getLocationAccuracy');
    return LocationAccuracyStatus.values[accuracy];
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final requestId = const Uuid().v4();
    try {
      Future<dynamic> positionFuture;

      final timeLimit = locationSettings?.timeLimit;
      positionFuture = _methodChannel.invokeMethod(
        'getCurrentPosition',
        {
          ...?locationSettings?.toJson(),
          'requestId': requestId,
        },
      );
      if (timeLimit != null) {
        positionFuture = positionFuture.timeout(timeLimit);
      }

      final positionMap = await positionFuture;
      return Position.fromMap(positionMap);
    } on TimeoutException {
      // Do not delay the timeout if the platform channel is unresponsive.
      unawaited(_cancelCurrentPosition(requestId));
      rethrow;
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  Future<void> _cancelCurrentPosition(String requestId) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'cancelGetCurrentPosition',
        {'requestId': requestId},
      );
    } on PlatformException {
      // Preserve the original timeout if cancellation itself fails.
    } on MissingPluginException {
      // An older native implementation may not support cancellation yet.
    }
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() {
    if (_serviceStatusStream != null) {
      return _serviceStatusStream!;
    }
    var serviceStatusStream =
        _serviceStatusEventChannel.receiveBroadcastStream();

    _serviceStatusStream = serviceStatusStream
        .map((dynamic element) => ServiceStatus.values[element as int])
        .handleError((error) {
      _serviceStatusStream = null;
      if (error is PlatformException) {
        error = _handlePlatformException(error);
      }
      throw error;
    });

    return _serviceStatusStream!;
  }

  /// With [requireForeground], iOS defers native startup until the app is
  /// active. Await [waitForPositionStreamStart] after listening to confirm
  /// that startUpdatingLocation has been called. This does not guarantee a fix.
  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
    bool requireForeground = false,
  }) {
    if (_positionStream != null) {
      if (requireForeground && _positionStreamStarted == null) {
        throw StateError('Cancel the existing position stream before starting '
            'a foreground-confirmed stream.');
      }
      return _positionStream!;
    }
    final started = requireForeground ? Completer<void>() : null;
    _positionStreamStarted = started;
    // A listener may cancel without ever awaiting the acknowledgement.
    if (started != null) {
      unawaited(started.future.then<void>((_) {}, onError: (Object _) {}));
    }
    var originalStream = _eventChannel.receiveBroadcastStream(
      requireForeground
          ? {...?locationSettings?.toJson(), 'requireForeground': true}
          : locationSettings?.toJson(),
    );
    var positionStream = _wrapStream(originalStream).where((dynamic event) {
      if (started != null &&
          event is Map &&
          event['event'] == 'positionStreamStarted') {
        if (!started.isCompleted) started.complete();
        return false;
      }
      return true;
    });

    var timeLimit = locationSettings?.timeLimit;

    if (timeLimit != null) {
      positionStream = positionStream.timeout(
        timeLimit,
        onTimeout: (s) {
          _positionStream = null;
          s.addError(TimeoutException(
            'Time limit reached while waiting for position update.',
            timeLimit,
          ));
          s.close();
        },
      );
    }

    _positionStream = positionStream
        .map<Position>((dynamic element) =>
            Position.fromMap(element.cast<String, dynamic>()))
        .handleError(
      (error) {
        if (error is PlatformException) {
          error = _handlePlatformException(error);
        }
        if (started != null && !started.isCompleted) {
          started.completeError(error);
        }
        throw error;
      },
    );
    return _positionStream!;
  }

  /// Waits for native startup of the current foreground-confirmed stream.
  /// The caller must listen first, bound the wait, and cancel on failure.
  Future<void> waitForPositionStreamStart() {
    final started = _positionStreamStarted;
    if (started == null) {
      throw StateError('Create a stream with requireForeground: true first.');
    }
    return started.future;
  }

  Stream<dynamic> _wrapStream(Stream<dynamic> incoming) {
    return incoming.asBroadcastStream(onCancel: (subscription) {
      subscription.cancel();
      final started = _positionStreamStarted;
      _positionStreamStarted = null;
      if (started != null && !started.isCompleted) {
        started.completeError(StateError('Position stream cancelled.'));
      }
      _positionStream = null;
    });
  }

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    try {
      final int status = await _methodChannel.invokeMethod(
        'requestTemporaryFullAccuracy',
        <String, dynamic>{
          'purposeKey': purposeKey,
        },
      );
      return LocationAccuracyStatus.values[status];
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);
      throw error;
    }
  }

  @override
  Future<bool> openAppSettings() async => _methodChannel
      .invokeMethod<bool>('openAppSettings')
      .then((value) => value ?? false);

  @override
  Future<bool> openLocationSettings() async => _methodChannel
      .invokeMethod<bool>('openLocationSettings')
      .then((value) => value ?? false);

  Exception _handlePlatformException(PlatformException exception) {
    switch (exception.code) {
      case 'ACTIVITY_MISSING':
        return ActivityMissingException(exception.message);
      case 'LOCATION_SERVICES_DISABLED':
        return const LocationServiceDisabledException();
      case 'LOCATION_SUBSCRIPTION_ACTIVE':
        return const AlreadySubscribedException();
      case 'PERMISSION_DEFINITIONS_NOT_FOUND':
        return PermissionDefinitionsNotFoundException(exception.message);
      case 'PERMISSION_DENIED':
        return PermissionDeniedException(exception.message);
      case 'PERMISSION_REQUEST_IN_PROGRESS':
        return PermissionRequestInProgressException(exception.message);
      case 'LOCATION_UPDATE_FAILURE':
        return PositionUpdateException(exception.message);
      default:
        return exception;
    }
  }
}
