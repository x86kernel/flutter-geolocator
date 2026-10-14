package com.baseflow.geolocator.location;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import android.app.Activity;
import android.content.Context;
import android.location.Location;
import android.os.Looper;
import com.baseflow.geolocator.errors.ErrorCallback;
import com.baseflow.geolocator.errors.ErrorCodes;
import com.google.android.gms.location.*;
import com.google.android.gms.tasks.*;
import java.util.Arrays;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.robolectric.Shadows.shadowOf;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
public class FusedLocationClientTest {
  private FusedLocationProviderClient provider;
  private SettingsClient settings;
  private NmeaClient nmea;
  private FusedLocationClient client;
  private PositionChangedCallback positions;
  private ErrorCallback errors;
  private TaskCompletionSource<LocationSettingsResponse> settingsTask;
  private TaskCompletionSource<Void> registration;

  @Before public void setUp() {
    provider = mock(FusedLocationProviderClient.class);
    settings = mock(SettingsClient.class);
    nmea = mock(NmeaClient.class);
    positions = mock(PositionChangedCallback.class);
    errors = mock(ErrorCallback.class);
    settingsTask = new TaskCompletionSource<>();
    registration = new TaskCompletionSource<>();
    when(settings.checkLocationSettings(any())).thenReturn(settingsTask.getTask());
    when(provider.requestLocationUpdates(any(LocationRequest.class), any(LocationCallback.class), any(Looper.class)))
        .thenReturn(registration.getTask());
    when(provider.removeLocationUpdates(any(LocationCallback.class))).thenReturn(Tasks.forResult(null));
    client = new FusedLocationClient(mock(Context.class), LocationOptions.parseArguments(null), provider, settings, nmea);
  }

  private void finishSettings() {
    settingsTask.setResult(mock(LocationSettingsResponse.class));
    shadowOf(Looper.getMainLooper()).idle();
  }

  private LocationCallback registeredCallback() {
    ArgumentCaptor<LocationCallback> captor = ArgumentCaptor.forClass(LocationCallback.class);
    verify(provider, atLeastOnce()).requestLocationUpdates(any(LocationRequest.class), captor.capture(), any(Looper.class));
    return captor.getValue();
  }

  @Test public void cancelBeforeSettingsSuccessDoesNotRegister() {
    client.startPositionUpdates(null, positions, errors);
    client.stopPositionUpdates();
    finishSettings();
    verify(provider, never()).requestLocationUpdates(any(LocationRequest.class), any(LocationCallback.class), any(Looper.class));
    verify(nmea, never()).start();
    verifyNoInteractions(positions, errors);
  }

  @Test public void cancelBeforeSettingsFailureDoesNotReportError() {
    client.startPositionUpdates(null, positions, errors);
    client.stopPositionUpdates();
    settingsTask.setException(new IllegalStateException("settings unavailable"));
    shadowOf(Looper.getMainLooper()).idle();
    verifyNoInteractions(errors);
    assertFalse(client.onActivityResult(1, Activity.RESULT_OK));
  }

  @Test public void registrationFailureReachesDartCallback() {
    client.startPositionUpdates(null, positions, errors);
    finishSettings();
    registration.setException(new IllegalStateException("registration failed"));
    shadowOf(Looper.getMainLooper()).idle();
    verify(errors).onError(ErrorCodes.errorWhileAcquiringPosition);
    verify(nmea).stop();
    verify(provider).removeLocationUpdates(any(LocationCallback.class));
  }

  @Test public void synchronousPermissionFailureIsReported() {
    when(provider.requestLocationUpdates(any(LocationRequest.class), any(LocationCallback.class), any(Looper.class)))
        .thenThrow(new SecurityException("revoked"));
    client.startPositionUpdates(null, positions, errors);
    finishSettings();
    verify(errors).onError(ErrorCodes.permissionDenied);
  }

  @Test public void lateRegistrationIsRemovedAndLateFixesIgnored() {
    client.startPositionUpdates(null, positions, errors);
    finishSettings();
    LocationCallback callback = registeredCallback();
    client.stopPositionUpdates();
    registration.setResult(null);
    shadowOf(Looper.getMainLooper()).idle();
    callback.onLocationResult(LocationResult.create(Arrays.asList(new Location("gps"))));
    verify(provider, times(2)).removeLocationUpdates(callback);
    verifyNoInteractions(positions, errors);
  }

  @Test public void oldCompletionDoesNotRemoveNewRequest() {
    client.startPositionUpdates(null, positions, errors);
    finishSettings();
    LocationCallback oldCallback = registeredCallback();
    client.stopPositionUpdates();
    when(settings.checkLocationSettings(any())).thenReturn(Tasks.forResult(mock(LocationSettingsResponse.class)));
    when(provider.requestLocationUpdates(any(LocationRequest.class), any(LocationCallback.class), any(Looper.class)))
        .thenReturn(Tasks.forResult(null));
    client.startPositionUpdates(null, positions, errors);
    shadowOf(Looper.getMainLooper()).idle();
    LocationCallback newCallback = registeredCallback();
    assertNotSame(oldCallback, newCallback);
    registration.setResult(null);
    shadowOf(Looper.getMainLooper()).idle();
    verify(provider, times(2)).removeLocationUpdates(oldCallback);
    verify(provider, never()).removeLocationUpdates(newCallback);
  }

  @Test public void oneShotConsumerReceivesNewestFixInProviderBatch() {
    final java.util.List<Location> received = new java.util.ArrayList<>();
    client.startPositionUpdates(null, location -> {
      received.add(location);
      client.stopPositionUpdates();
    }, errors);
    finishSettings();
    Location first = new Location("gps"); first.setTime(1000);
    Location second = new Location("gps"); second.setTime(2000);
    registeredCallback().onLocationResult(LocationResult.create(Arrays.asList(first, second)));
    assertEquals(1, received.size());
    assertEquals(2000, received.get(0).getTime());
    assertNull(second.getExtras());
  }

  @Test public void cleanupExceptionDoesNotHideRegistrationFailure() {
    doThrow(new SecurityException("auxiliary listener cleanup failed")).when(nmea).stop();
    client.startPositionUpdates(null, positions, errors);
    finishSettings();
    registration.setException(new IllegalStateException("registration failed"));
    shadowOf(Looper.getMainLooper()).idle();
    verify(errors).onError(ErrorCodes.errorWhileAcquiringPosition);
    verify(provider).removeLocationUpdates(any(LocationCallback.class));
  }

  @Test public void cancelledRegistrationReportsFailure() {
    CancellationTokenSource cancellation = new CancellationTokenSource();
    TaskCompletionSource<Void> cancellableRegistration = new TaskCompletionSource<>(cancellation.getToken());
    when(provider.requestLocationUpdates(any(LocationRequest.class), any(LocationCallback.class), any(Looper.class)))
        .thenReturn(cancellableRegistration.getTask());
    client.startPositionUpdates(null, positions, errors);
    finishSettings();
    cancellation.cancel();
    shadowOf(Looper.getMainLooper()).idle();
    verify(errors).onError(ErrorCodes.errorWhileAcquiringPosition);
  }
}
