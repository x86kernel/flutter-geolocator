package com.baseflow.geolocator;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Notification;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.Nullable;

import com.baseflow.geolocator.location.BackgroundNotification;
import com.baseflow.geolocator.location.ForegroundNotificationOptions;
import com.baseflow.geolocator.location.GeolocationManager;
import com.baseflow.geolocator.location.LocationClient;
import com.baseflow.geolocator.location.LocationMapper;
import com.baseflow.geolocator.location.LocationOptions;

import io.flutter.plugin.common.EventChannel;
import java.util.IdentityHashMap;
import java.util.Map;

public class GeolocatorLocationService extends Service {
  private static final String TAG = "FlutterGeolocator";
  private static final int ONGOING_NOTIFICATION_ID = 75415;
  private static final String CHANNEL_ID = "geolocator_channel_01";
  private final String WAKELOCK_TAG = "GeolocatorLocationService:Wakelock";
  private final String WIFILOCK_TAG = "GeolocatorLocationService:WifiLock";
  private final LocalBinder binder = new LocalBinder(this);
  // Service is foreground
  private boolean isForeground = false;
  private int connectedEngines = 0;
  // Each engine owns its stream; cancelling one must not tear down another.
  private final Map<EventChannel.EventSink, LocationSession> sessions = new IdentityHashMap<>();
  private final Map<EventChannel.EventSink, ForegroundNotificationOptions> backgroundOptions =
      new IdentityHashMap<>();

  private static class LocationSession {
    final boolean forceLocationManager;
    final LocationOptions options;
    @Nullable LocationClient client;
    long generation;

    LocationSession(boolean forceLocationManager, LocationOptions options) {
      this.forceLocationManager = forceLocationManager;
      this.options = options;
    }
  }
  @Nullable private Activity activity = null;
  @Nullable private GeolocationManager geolocationManager = null;

  @Nullable private PowerManager.WakeLock wakeLock = null;
  @Nullable private WifiManager.WifiLock wifiLock = null;

  @Nullable private BackgroundNotification backgroundNotification = null;

  @Override
  public void onCreate() {
    super.onCreate();
    Log.d(TAG, "Creating service.");
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    return START_STICKY;
  }

  @Nullable
  @Override
  public IBinder onBind(Intent intent) {
    Log.d(TAG, "Binding to location service.");
    return binder;
  }

  @Override
  public boolean onUnbind(Intent intent) {
    Log.d(TAG, "Unbinding from location service.");
    return super.onUnbind(intent);
  }

  @Override
  public void onDestroy() {
    Log.d(TAG, "Destroying location service.");

    stopLocationService();
    disableBackgroundMode();
    geolocationManager = null;
    backgroundNotification = null;

    Log.d(TAG, "Destroyed location service.");
    super.onDestroy();
  }

  public void flutterEngineConnected() {

    connectedEngines++;
    Log.d(TAG, "Flutter engine connected. Connected engine count " + connectedEngines);
  }

  public void flutterEngineDisconnected() {

    connectedEngines--;
    Log.d(TAG, "Flutter engine disconnected. Connected engine count " + connectedEngines);
  }

  public void startLocationService(
      boolean forceLocationManager,
      LocationOptions locationOptions,
      EventChannel.EventSink events) {

    if (geolocationManager == null) {
      throw new IllegalStateException("Location service is not initialized");
    }
    // onListen owns foreground options already; replacing the native request
    // must not release that owner's locks.
    LocationSession previous = sessions.remove(events);
    if (previous != null) stopSession(previous);
    LocationSession session = new LocationSession(forceLocationManager, locationOptions);
    sessions.put(events, session);
    try {
      startSession(events, session);
    } catch (RuntimeException error) {
      stopLocationService(events);
      throw error;
    }
  }

  private void stopSession(LocationSession session) {
    ++session.generation;
    LocationClient client = session.client;
    session.client = null;
    if (client != null && geolocationManager != null) {
      try {
        geolocationManager.stopPositionUpdates(client);
      } catch (RuntimeException error) {
        Log.w(TAG, "Failed to stop location client", error);
      }
    }
  }

  private void startSession(EventChannel.EventSink events, LocationSession session) {
    stopSession(session);
    final long generation = session.generation;
    try {
      session.client = geolocationManager.createLocationClient(
          getApplicationContext(), session.forceLocationManager, session.options);
      geolocationManager.startPositionUpdates(session.client, activity,
          location -> {
            if (sessions.get(events) == session && session.generation == generation) {
              events.success(LocationMapper.toHashMap(location));
            }
          },
          error -> {
            if (sessions.get(events) == session && session.generation == generation) {
              events.error(error.toString(), error.toDescription(), null);
            }
          });
    } catch (RuntimeException error) {
      stopSession(session);
      throw error;
    }
  }

  public boolean restartLocationService(EventChannel.EventSink events) {
    LocationSession session = sessions.get(events);
    if (session == null) return false;
    // Keep configuration even if registration throws, so a later retry works.
    // Foreground state and locks belong to the stream, not this native request.
    startSession(events, session);
    return true;
  }

  public void stopLocationService(EventChannel.EventSink events) {
    LocationSession session = sessions.remove(events);
    if (session != null) stopSession(session);
    backgroundOptions.remove(events);
    updateWakeLocks();
  }

  public boolean hasLocationSessions() {
    return !sessions.isEmpty();
  }

  public void stopLocationService() {
    for (EventChannel.EventSink events : sessions.keySet().toArray(new EventChannel.EventSink[0])) {
      stopLocationService(events);
    }
  }

  public void enableBackgroundMode(ForegroundNotificationOptions options, EventChannel.EventSink events) {
    if (backgroundNotification != null) {
      Log.d(TAG, "Service already in foreground mode.");
      backgroundNotification.updateOptions(options, isForeground);
    } else {
      Log.d(TAG, "Start service in foreground mode.");

      BackgroundNotification notificationBuilder =
          new BackgroundNotification(
              this.getApplicationContext(), CHANNEL_ID, ONGOING_NOTIFICATION_ID, options);
      notificationBuilder.updateChannel(options.getNotificationChannelName());
      Notification notification = notificationBuilder.build();
      startForeground(ONGOING_NOTIFICATION_ID, notification);
      // A failed promotion must not make the next attempt look already active.
      backgroundNotification = notificationBuilder;
      isForeground = true;
    }
    backgroundOptions.put(events, options);
    updateWakeLocks();
  }

  @SuppressWarnings("deprecation")
  public void disableBackgroundMode() {
    if (isForeground) {
      Log.d(TAG, "Stop service in foreground.");
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        stopForeground(Service.STOP_FOREGROUND_REMOVE);
      } else {
        stopForeground(true);
      }
      backgroundOptions.clear();
      releaseWakeLocks();
      isForeground = false;
      backgroundNotification = null;
    }
  }

  public void setActivity(@Nullable Activity activity) {
    this.activity = activity;
  }

  public void setGeolocationManager(@Nullable GeolocationManager geolocationManager) {
      this.geolocationManager = geolocationManager;
  }

  private void releaseWakeLocks() {
    if (wakeLock != null && wakeLock.isHeld()) {
      wakeLock.release();
      wakeLock = null;
    }
    if (wifiLock != null && wifiLock.isHeld()) {
      wifiLock.release();
      wifiLock = null;
    }
  }

  @SuppressLint("WakelockTimeout")
  private void updateWakeLocks() {
    boolean needsWakeLock = false;
    boolean needsWifiLock = false;
    for (ForegroundNotificationOptions options : backgroundOptions.values()) {
      needsWakeLock |= options.isEnableWakeLock();
      needsWifiLock |= options.isEnableWifiLock();
    }
    if (needsWakeLock) {
      if (wakeLock == null || !wakeLock.isHeld()) {
        PowerManager powerManager =
            (PowerManager) getApplicationContext().getSystemService(Context.POWER_SERVICE);
        if (powerManager != null) {
          wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG);
          wakeLock.setReferenceCounted(false);
          wakeLock.acquire();
        }
      }
    } else if (wakeLock != null) {
      if (wakeLock.isHeld()) wakeLock.release();
      wakeLock = null;
    }
    if (needsWifiLock) {
      if (wifiLock == null || !wifiLock.isHeld()) {
        WifiManager wifiManager =
            (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager != null) {
          wifiLock = wifiManager.createWifiLock(getWifiLockType(), WIFILOCK_TAG);
          wifiLock.setReferenceCounted(false);
          wifiLock.acquire();
        }
      }
    } else if (wifiLock != null) {
      if (wifiLock.isHeld()) wifiLock.release();
      wifiLock = null;
    }
  }

  @SuppressWarnings("deprecation")
  private int getWifiLockType() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      return WifiManager.WIFI_MODE_FULL_HIGH_PERF;
    }
    return WifiManager.WIFI_MODE_FULL_LOW_LATENCY;
  }

  class LocalBinder extends Binder {
    private final GeolocatorLocationService locationService;

    LocalBinder(GeolocatorLocationService locationService) {
      this.locationService = locationService;
    }

    public GeolocatorLocationService getLocationService() {
      return locationService;
    }
  }
}
