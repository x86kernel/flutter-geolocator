package com.baseflow.geolocator;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import com.baseflow.geolocator.location.*;
import android.os.PowerManager;
import java.util.HashMap;
import java.util.Map;
import org.robolectric.shadows.ShadowPowerManager;
import static org.robolectric.Shadows.shadowOf;
import io.flutter.plugin.common.EventChannel;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
public class GeolocatorLocationServiceTest {
  @Test public void restartAndCancelOnlyAffectOwningStream() {
    GeolocatorLocationService service = Robolectric.buildService(GeolocatorLocationService.class).create().get();
    GeolocationManager manager = mock(GeolocationManager.class);
    LocationClient first = mock(LocationClient.class), second = mock(LocationClient.class), replacement = mock(LocationClient.class);
    when(manager.createLocationClient(any(), anyBoolean(), any())).thenReturn(first, second, replacement);
    service.setGeolocationManager(manager);
    EventChannel.EventSink one = mock(EventChannel.EventSink.class), two = mock(EventChannel.EventSink.class);
    service.startLocationService(false, LocationOptions.parseArguments(null), one);
    service.startLocationService(false, LocationOptions.parseArguments(null), two);
    assertTrue(service.restartLocationService(one));
    verify(manager).stopPositionUpdates(first);
    verify(manager, never()).stopPositionUpdates(second);
    service.stopLocationService(one);
    verify(manager).stopPositionUpdates(replacement);
    assertTrue(service.hasLocationSessions());
    service.stopLocationService(two);
    assertFalse(service.hasLocationSessions());
    assertFalse(service.restartLocationService(one));
  }
  @Test public void restartRetainsForegroundNotificationAndSameHeldWakeLock() {
    GeolocatorLocationService service = Robolectric.buildService(GeolocatorLocationService.class).create().get();
    GeolocationManager manager = mock(GeolocationManager.class);
    when(manager.createLocationClient(any(), anyBoolean(), any())).thenReturn(mock(LocationClient.class));
    service.setGeolocationManager(manager);
    Map<String,Object> icon = new HashMap<>();
    icon.put("name", "ic_launcher"); icon.put("defType", "mipmap");
    Map<String,Object> options = new HashMap<>();
    options.put("notificationTitle", "Recording");
    options.put("notificationText", "Ride in progress");
    options.put("notificationChannelName", "Location");
    options.put("notificationIcon", icon);
    options.put("enableWakeLock", true);
    options.put("enableWifiLock", false);
    options.put("setOngoing", true);
    EventChannel.EventSink events = mock(EventChannel.EventSink.class);
    service.enableBackgroundMode(ForegroundNotificationOptions.parseArguments(options), events);
    PowerManager.WakeLock lock = ShadowPowerManager.getLatestWakeLock();
    assertTrue(lock.isHeld());
    Object notification = shadowOf(service).getLastForegroundNotification();
    assertNotNull(notification);
    service.startLocationService(false, LocationOptions.parseArguments(null), events);
    assertTrue(service.restartLocationService(events));
    assertSame(lock, ShadowPowerManager.getLatestWakeLock());
    assertTrue(lock.isHeld());
    assertSame(notification, shadowOf(service).getLastForegroundNotification());
    assertFalse(shadowOf(service).isForegroundStopped());
    service.stopLocationService(events);
    service.disableBackgroundMode();
    assertFalse(lock.isHeld());
    assertTrue(shadowOf(service).isForegroundStopped());
  }
  @Test public void synchronousRestartFailureCanBeRetriedOnSameStream() {
    GeolocatorLocationService service = Robolectric.buildService(GeolocatorLocationService.class).create().get();
    GeolocationManager manager = mock(GeolocationManager.class);
    LocationClient first = mock(LocationClient.class), failed = mock(LocationClient.class), recovered = mock(LocationClient.class);
    when(manager.createLocationClient(any(), anyBoolean(), any())).thenReturn(first, failed, recovered);
    doThrow(new IllegalStateException("provider temporarily unavailable"))
        .when(manager).startPositionUpdates(eq(failed), any(), any(), any());
    service.setGeolocationManager(manager);
    EventChannel.EventSink events = mock(EventChannel.EventSink.class);
    service.startLocationService(false, LocationOptions.parseArguments(null), events);
    assertThrows(IllegalStateException.class, () -> service.restartLocationService(events));
    assertTrue(service.restartLocationService(events));
    verify(manager).startPositionUpdates(eq(recovered), any(), any(), any());
    service.stopLocationService(events);
  }

  @Test public void anotherStreamsOptionsCannotReleaseRecordingWakeLock() {
    GeolocatorLocationService service = Robolectric.buildService(GeolocatorLocationService.class).create().get();
    GeolocationManager manager = mock(GeolocationManager.class);
    when(manager.createLocationClient(any(), anyBoolean(), any())).thenReturn(mock(LocationClient.class));
    service.setGeolocationManager(manager);
    EventChannel.EventSink recording = mock(EventChannel.EventSink.class), other = mock(EventChannel.EventSink.class);
    Map<String,Object> icon = new HashMap<>();
    icon.put("name", "ic_launcher"); icon.put("defType", "mipmap");
    Map<String,Object> options = new HashMap<>();
    options.put("notificationTitle", "Recording");
    options.put("notificationText", "Ride in progress");
    options.put("notificationChannelName", "Location");
    options.put("notificationIcon", icon);
    options.put("enableWakeLock", true);
    options.put("enableWifiLock", false);
    options.put("setOngoing", true);
    service.enableBackgroundMode(ForegroundNotificationOptions.parseArguments(options), recording);
    service.startLocationService(false, LocationOptions.parseArguments(null), recording);
    PowerManager.WakeLock lock = ShadowPowerManager.getLatestWakeLock();
    options.put("enableWakeLock", false);
    service.enableBackgroundMode(ForegroundNotificationOptions.parseArguments(options), other);
    service.startLocationService(false, LocationOptions.parseArguments(null), other);
    assertTrue(lock.isHeld());
    assertSame(lock, ShadowPowerManager.getLatestWakeLock());
    service.stopLocationService(other);
    assertTrue(lock.isHeld());
    service.stopLocationService(recording);
    assertFalse(lock.isHeld());
    service.disableBackgroundMode();
  }

  @Test public void failedGenerationCannotSendEventsAfterRetry() {
    GeolocatorLocationService service = Robolectric.buildService(GeolocatorLocationService.class).create().get();
    GeolocationManager manager = mock(GeolocationManager.class);
    when(manager.createLocationClient(any(), anyBoolean(), any())).thenAnswer(invocation -> mock(LocationClient.class));
    service.setGeolocationManager(manager);
    EventChannel.EventSink events = mock(EventChannel.EventSink.class);
    org.mockito.ArgumentCaptor<PositionChangedCallback> callbacks = org.mockito.ArgumentCaptor.forClass(PositionChangedCallback.class);
    service.startLocationService(false, LocationOptions.parseArguments(null), events);
    service.restartLocationService(events);
    verify(manager, times(2)).startPositionUpdates(any(), any(), callbacks.capture(), any());
    android.location.Location fix = new android.location.Location("gps");
    callbacks.getAllValues().get(0).onPositionChanged(fix);
    verifyNoInteractions(events);
    callbacks.getAllValues().get(1).onPositionChanged(fix);
    verify(events).success(any());
    service.stopLocationService(events);
  }
}
