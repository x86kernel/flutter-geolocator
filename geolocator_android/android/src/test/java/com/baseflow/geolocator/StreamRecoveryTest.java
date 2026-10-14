package com.baseflow.geolocator;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import android.content.Context;
import com.baseflow.geolocator.errors.PermissionUndefinedException;
import com.baseflow.geolocator.location.*;
import com.baseflow.geolocator.permission.PermissionManager;
import io.flutter.plugin.common.*;
import java.util.HashMap;
import java.util.Map;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.RuntimeEnvironment;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
public class StreamRecoveryTest {
  private StreamHandlerImpl stream;
  private GeolocatorLocationService service;
  private PermissionManager permissions;
  private EventChannel.EventSink events;

  @Before public void setUp() throws PermissionUndefinedException {
    permissions = mock(PermissionManager.class);
    when(permissions.hasPermission(any())).thenReturn(true);
    stream = new StreamHandlerImpl(permissions, mock(GeolocationManager.class));
    stream.startListening(RuntimeEnvironment.getApplication(), mock(BinaryMessenger.class));
    service = mock(GeolocatorLocationService.class);
    events = mock(EventChannel.EventSink.class);
  }

  private Map<String,Object> options() {
    Map<String,Object> notification = new HashMap<>();
    notification.put("notificationTitle", "Recording");
    notification.put("notificationText", "Ride in progress");
    notification.put("enableWakeLock", true);
    notification.put("enableWifiLock", false);
    notification.put("setOngoing", true);
    Map<String,Object> options = new HashMap<>();
    options.put("foregroundNotificationConfig", notification);
    return options;
  }

  @Test public void missingServiceProducesErrorInsteadOfSilentStream() {
    stream.onListen(options(), events);
    verify(events).error(eq("ERROR_WHILE_ACQUIRING_POSITION"), anyString(), isNull());
  }

  @Test public void restartKeepsForegroundModeAndUsesSameStream() {
    stream.setForegroundLocationService(service);
    stream.onListen(options(), events);
    clearInvocations(service);
    when(service.restartLocationService(events)).thenReturn(true);
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    stream.restartPositionUpdates(result);
    verify(service).restartLocationService(events);
    verify(service, never()).disableBackgroundMode();
    verify(service, never()).enableBackgroundMode(any(), any());
    verify(result).success(true);
    stream.onCancel(null);
    verify(service).stopLocationService(events);
    verify(service).disableBackgroundMode();
  }

  @Test public void cancellationDoesNotDisableAnotherStreamsService() {
    stream.setForegroundLocationService(service);
    stream.onListen(options(), events);
    when(service.hasLocationSessions()).thenReturn(true);
    stream.onCancel(null);
    verify(service).stopLocationService(events);
    verify(service, never()).disableBackgroundMode();
  }

  @Test public void failedForegroundPromotionDoesNotStartLocation() {
    stream.setForegroundLocationService(service);
    doThrow(new SecurityException("permission revoked")).when(service).enableBackgroundMode(any(), any());
    stream.onListen(options(), events);
    verify(service, never()).startLocationService(anyBoolean(), any(), any());
    verify(events).error(eq("PERMISSION_DENIED"), anyString(), isNull());
  }

  @Test public void restartWithoutSubscriptionReturnsFalse() {
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    stream.restartPositionUpdates(result);
    verify(result).success(false);
    verifyNoInteractions(service);
  }
}
