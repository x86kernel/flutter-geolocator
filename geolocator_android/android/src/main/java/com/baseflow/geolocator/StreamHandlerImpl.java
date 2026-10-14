package com.baseflow.geolocator;

import android.app.Activity;
import android.content.Context;
import android.util.Log;

import androidx.annotation.Nullable;

import com.baseflow.geolocator.errors.ErrorCodes;
import com.baseflow.geolocator.errors.PermissionUndefinedException;
import com.baseflow.geolocator.location.ForegroundNotificationOptions;
import com.baseflow.geolocator.location.GeolocationManager;
import com.baseflow.geolocator.location.LocationClient;
import com.baseflow.geolocator.location.LocationMapper;
import com.baseflow.geolocator.location.LocationOptions;
import com.baseflow.geolocator.permission.PermissionManager;

import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

class StreamHandlerImpl implements EventChannel.StreamHandler {
  private static final String TAG = "FlutterGeolocator";

  private final PermissionManager permissionManager;

  @Nullable private EventChannel channel;
  @Nullable private Context context;
  @Nullable private Activity activity;
  @Nullable private GeolocatorLocationService foregroundLocationService;
  @Nullable private GeolocationManager geolocationManager;
  @Nullable private LocationClient locationClient;
  @Nullable private EventChannel.EventSink activeEvents;
  private boolean usesForegroundService;
  private boolean forceLocationManager;
  @Nullable private LocationOptions activeOptions;
  private long generation;

  public StreamHandlerImpl(PermissionManager permissionManager, GeolocationManager geolocationManager) {
    this.permissionManager = permissionManager;
    this.geolocationManager = geolocationManager;
  }

  public void setForegroundLocationService(
      @Nullable GeolocatorLocationService foregroundLocationService) {
    this.foregroundLocationService = foregroundLocationService;
  }

  public void setActivity(@Nullable Activity activity) {

    if (activity == null && locationClient != null && channel != null) {
      stopListening();
    }

    this.activity = activity;
  }

  /**
   * Registers this instance as event stream handler on the given {@code messenger}.
   *
   * <p>Stops any previously started and unstopped calls.
   *
   * <p>This should be cleaned with {@link #stopListening} once the messenger is disposed of.
   */
  void startListening(Context context, BinaryMessenger messenger) {
    if (channel != null) {
      Log.w(TAG, "Setting a event call handler before the last was disposed.");
      stopListening();
    }

    channel = new EventChannel(messenger, "flutter.baseflow.com/geolocator_updates_android");
    channel.setStreamHandler(this);
    this.context = context;
  }

  /**
   * Clears this instance from listening to method calls.
   *
   * <p>Does nothing if {@link #startListening} hasn't been called, or if we're already stopped.
   */
  void stopListening() {
    if (channel == null) {
      Log.d(TAG, "Tried to stop listening when no MethodChannel had been initialized.");
      return;
    }

    disposeListeners();
    channel.setStreamHandler(null);
    channel = null;
  }

  @SuppressWarnings({"ConstantConditions", "unchecked"})
  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    try {
      if (!permissionManager.hasPermission(this.context)) {
        events.error(
            ErrorCodes.permissionDenied.toString(),
            ErrorCodes.permissionDenied.toDescription(),
            null);
        return;
      }
    } catch (PermissionUndefinedException e) {
      events.error(
          ErrorCodes.permissionDefinitionsNotFound.toString(),
          ErrorCodes.permissionDefinitionsNotFound.toDescription(),
          null);
      return;
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> map = (Map<String, Object>) arguments;
    forceLocationManager = false;
    if (map != null && map.get("forceLocationManager") != null) {
      forceLocationManager = (boolean) map.get("forceLocationManager");
    }
    LocationOptions locationOptions = LocationOptions.parseArguments(map);
    ForegroundNotificationOptions foregroundNotificationOptions = null;

    if (map != null) {
      foregroundNotificationOptions =
          ForegroundNotificationOptions.parseArguments(
              (Map<String, Object>) map.get("foregroundNotificationConfig"));
    }
    if (activeEvents != null) disposeListeners();
    activeEvents = events;
    activeOptions = locationOptions;
    usesForegroundService = foregroundNotificationOptions != null;
    try {
      if (usesForegroundService) {
        if (foregroundLocationService == null) {
          throw new IllegalStateException("Location background service is not connected yet");
        }
        // Foreground promotion must succeed before requesting updates.
        foregroundLocationService.enableBackgroundMode(foregroundNotificationOptions, events);
        foregroundLocationService.startLocationService(forceLocationManager, locationOptions, events);
      } else {
        startDirectUpdates(events);
      }
    } catch (RuntimeException error) {
      disposeListeners();
      ErrorCodes code = error instanceof SecurityException ? ErrorCodes.permissionDenied
          : ErrorCodes.errorWhileAcquiringPosition;
      events.error(code.toString(), error.getMessage(), null);
    }
  }

  private void startDirectUpdates(EventChannel.EventSink events) {
    long requestGeneration = ++generation;
    locationClient = geolocationManager.createLocationClient(context, forceLocationManager, activeOptions);
    geolocationManager.startPositionUpdates(locationClient, activity,
        location -> {
          if (activeEvents == events && generation == requestGeneration) {
            events.success(LocationMapper.toHashMap(location));
          }
        },
        error -> {
          if (activeEvents == events && generation == requestGeneration) {
            events.error(error.toString(), error.toDescription(), null);
          }
        });
  }

  void restartPositionUpdates(MethodChannel.Result result) {
    if (activeEvents == null) {
      result.success(false);
      return;
    }
    try {
      if (!permissionManager.hasPermission(context)) {
        result.error(ErrorCodes.permissionDenied.toString(), ErrorCodes.permissionDenied.toDescription(), null);
        return;
      }
      if (usesForegroundService) {
        if (foregroundLocationService == null) {
          result.error(ErrorCodes.errorWhileAcquiringPosition.toString(), "Location service is disconnected", null);
          return;
        }
        result.success(foregroundLocationService.restartLocationService(activeEvents));
      } else {
        ++generation;
        if (locationClient != null) geolocationManager.stopPositionUpdates(locationClient);
        startDirectUpdates(activeEvents);
        result.success(true);
      }
    } catch (PermissionUndefinedException error) {
      result.error(ErrorCodes.permissionDefinitionsNotFound.toString(), error.getMessage(), null);
    } catch (RuntimeException error) {
      ErrorCodes code = error instanceof SecurityException ? ErrorCodes.permissionDenied
          : ErrorCodes.errorWhileAcquiringPosition;
      result.error(code.toString(), error.getMessage(), null);
    }
  }

  @Override
  public void onCancel(Object arguments) {
    disposeListeners();
  }

  private void disposeListeners() {
    ++generation;
    EventChannel.EventSink events = activeEvents;
    activeEvents = null;
    activeOptions = null;
    if (usesForegroundService && foregroundLocationService != null) {
      if (events != null) foregroundLocationService.stopLocationService(events);
      if (!foregroundLocationService.hasLocationSessions()) foregroundLocationService.disableBackgroundMode();
    }
    usesForegroundService = false;
    if (locationClient != null && geolocationManager != null) {
      geolocationManager.stopPositionUpdates(locationClient);
      locationClient = null;
    }
  }
}
