package com.baseflow.geolocator.location;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.IntentSender;
import android.location.Location;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.baseflow.geolocator.errors.ErrorCallback;
import com.baseflow.geolocator.errors.ErrorCodes;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.ResolvableApiException;
import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationAvailability;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.LocationSettingsRequest;
import com.google.android.gms.location.LocationSettingsResponse;
import com.google.android.gms.location.LocationSettingsStates;
import com.google.android.gms.location.LocationSettingsStatusCodes;
import com.google.android.gms.location.Priority;
import com.google.android.gms.location.SettingsClient;

import java.security.SecureRandom;

class FusedLocationClient implements LocationClient {
  private static final String TAG = "FlutterGeolocator";

  private final Context context;
  private LocationCallback locationCallback;
  private final SettingsClient settingsClient;
  private long generation = 0;
  private boolean active = false;
  private boolean awaitingResolution = false;
  private final FusedLocationProviderClient fusedLocationProviderClient;
  private final NmeaClient nmeaClient;
  private int activityRequestCode;
  @Nullable private final LocationOptions locationOptions;

  @Nullable private ErrorCallback errorCallback;
  @Nullable private PositionChangedCallback positionChangedCallback;

  public FusedLocationClient(@NonNull Context context, @Nullable LocationOptions locationOptions) {
    this(context, locationOptions, LocationServices.getFusedLocationProviderClient(context),
        LocationServices.getSettingsClient(context), new NmeaClient(context, locationOptions));
  }

  // Dependencies are injectable so delayed Google Play services tasks can be tested.
  FusedLocationClient(Context context, LocationOptions locationOptions,
      FusedLocationProviderClient provider, SettingsClient settingsClient, NmeaClient nmeaClient) {
    this.context = context;
    this.locationOptions = locationOptions;
    this.fusedLocationProviderClient = provider;
    this.settingsClient = settingsClient;
    this.nmeaClient = nmeaClient;
  }

  private boolean isActive(long requestGeneration) {
    return active && generation == requestGeneration;
  }

  private LocationCallback createLocationCallback(long requestGeneration) {
    return new LocationCallback() {
      @Override
      public void onLocationResult(@NonNull LocationResult result) {
        if (!isActive(requestGeneration)) return;
        // This client also backs getCurrentPosition: a one-shot consumer stops
        // on its first callback, so retain Android's newest-fix semantics.
        Location source = result.getLastLocation();
        if (source == null || positionChangedCallback == null) return;
        Location location = new Location(source);
        location.setExtras(source.getExtras() == null ? new Bundle() : new Bundle(source.getExtras()));
        location.getExtras().putBoolean(LocationOptions.USE_MSL_ALTITUDE_EXTRA,
            locationOptions != null && locationOptions.isUseMSLAltitude());
        nmeaClient.enrichExtrasWithNmea(location);
        positionChangedCallback.onPositionChanged(location);
      }

      @Override
      public void onLocationAvailability(@NonNull LocationAvailability availability) {
        if (isActive(requestGeneration) && !availability.isLocationAvailable()
            && !checkLocationService(context) && errorCallback != null) {
          errorCallback.onError(ErrorCodes.locationServicesDisabled);
        }
      }
    };
  }

  private static LocationRequest buildLocationRequest(@Nullable LocationOptions options) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      return buildLocationRequestDeprecated(options);
    }

    LocationRequest.Builder builder = new LocationRequest.Builder(0);

    if (options != null) {
      builder.setPriority(toPriority(options.getAccuracy()));
      builder.setIntervalMillis(options.getTimeInterval());
      builder.setMinUpdateIntervalMillis(options.getTimeInterval());
      builder.setMinUpdateDistanceMeters(options.getDistanceFilter());
    }

    return builder.build();
  }

  @SuppressWarnings("deprecation")
  private static LocationRequest buildLocationRequestDeprecated(@Nullable LocationOptions options) {
    LocationRequest locationRequest = LocationRequest.create();

    if (options != null) {
      locationRequest.setPriority(toPriority(options.getAccuracy()));
      locationRequest.setInterval(options.getTimeInterval());
      locationRequest.setFastestInterval(options.getTimeInterval() / 2);
      locationRequest.setSmallestDisplacement(options.getDistanceFilter());
    }

    return locationRequest;
  }

  private static LocationSettingsRequest buildLocationSettingsRequest(
      LocationRequest locationRequest) {
    LocationSettingsRequest.Builder builder = new LocationSettingsRequest.Builder();
    builder.addLocationRequest(locationRequest);

    return builder.build();
  }

  private static int toPriority(LocationAccuracy locationAccuracy) {
    switch (locationAccuracy) {
      case lowest:
        return Priority.PRIORITY_PASSIVE;
      case low:
        return Priority.PRIORITY_LOW_POWER;
      case medium:
        return Priority.PRIORITY_BALANCED_POWER_ACCURACY;
      default:
        return Priority.PRIORITY_HIGH_ACCURACY;
    }
  }

  private synchronized int generateActivityRequestCode() {
    SecureRandom random = new SecureRandom();
    return random.nextInt(1 << 16);
  }

  @SuppressLint("MissingPermission")
  private void requestPositionUpdates(long requestGeneration) {
    if (!isActive(requestGeneration)) return;
    final LocationCallback callback = locationCallback;
    try {
      nmeaClient.start();
      fusedLocationProviderClient.requestLocationUpdates(
          buildLocationRequest(locationOptions), callback, Looper.getMainLooper())
          .addOnSuccessListener(unused -> {
            // Registration may finish after cancellation. Remove that registration only,
            // never the callback belonging to a newer request.
            if (!isActive(requestGeneration)) removeLocationUpdates(callback);
          })
          .addOnCanceledListener(() -> fail(requestGeneration, ErrorCodes.errorWhileAcquiringPosition))
          .addOnFailureListener(error -> fail(requestGeneration,
              error instanceof SecurityException ? ErrorCodes.permissionDenied
                  : ErrorCodes.errorWhileAcquiringPosition));
    } catch (RuntimeException error) {
      fail(requestGeneration, error instanceof SecurityException ? ErrorCodes.permissionDenied
          : ErrorCodes.errorWhileAcquiringPosition);
    }
  }

  private void fail(long requestGeneration, ErrorCodes code) {
    if (!isActive(requestGeneration)) return;
    ErrorCallback callback = errorCallback;
    stopPositionUpdates();
    if (callback != null) callback.onError(code);
  }

  private void removeLocationUpdates(LocationCallback callback) {
    if (callback == null) return;
    try {
      fusedLocationProviderClient.removeLocationUpdates(callback)
          .addOnFailureListener(error -> Log.w(TAG, "Failed to remove location updates", error));
    } catch (RuntimeException error) {
      Log.w(TAG, "Failed to remove location updates", error);
    }
  }

  @Override
  public void isLocationServiceEnabled(LocationServiceListener listener) {
    LocationServices.getSettingsClient(context)
        .checkLocationSettings(new LocationSettingsRequest.Builder().build())
        .addOnCompleteListener(
            (response) -> {
              if (!response.isSuccessful()) {
                listener.onLocationServiceError(ErrorCodes.locationServicesDisabled);
              } else {
                LocationSettingsResponse lsr = response.getResult();
                if (lsr != null) {
                    LocationSettingsStates settingsStates = lsr.getLocationSettingsStates();
                    boolean isGpsUsable = settingsStates != null && settingsStates.isGpsUsable();
                    boolean isNetworkUsable =
                            settingsStates != null && settingsStates.isNetworkLocationUsable();
                    listener.onLocationServiceResult(isGpsUsable || isNetworkUsable);
                } else {
                    listener.onLocationServiceError(ErrorCodes.locationServicesDisabled);
                }
              }
            });
  }

  @SuppressLint("MissingPermission")
  @Override
  public void getLastKnownPosition(
      PositionChangedCallback positionChangedCallback, ErrorCallback errorCallback) {

    fusedLocationProviderClient
        .getLastLocation()
        .addOnSuccessListener(positionChangedCallback::onPositionChanged)
        .addOnFailureListener(
            e -> {
              Log.e("Geolocator", "Error trying to get last the last known GPS location");
              if (errorCallback != null) {
                errorCallback.onError(ErrorCodes.errorWhileAcquiringPosition);
              }
            });
  }

  public boolean onActivityResult(int requestCode, int resultCode) {
    if (!active || !awaitingResolution || requestCode != activityRequestCode) return false;
    awaitingResolution = false;
    if (resultCode == Activity.RESULT_OK) {
      requestPositionUpdates(generation);
    } else {
      fail(generation, ErrorCodes.locationServicesDisabled);
    }
    return true;
  }

  @SuppressLint("MissingPermission")
  public void startPositionUpdates(
      @Nullable Activity activity,
      @NonNull PositionChangedCallback positionChangedCallback,
      @NonNull ErrorCallback errorCallback) {
    if (active) stopPositionUpdates();
    final long requestGeneration = ++generation;
    active = true;
    awaitingResolution = false;
    activityRequestCode = generateActivityRequestCode();
    this.positionChangedCallback = positionChangedCallback;
    this.errorCallback = errorCallback;
    locationCallback = createLocationCallback(requestGeneration);

    try {
      settingsClient.checkLocationSettings(
          buildLocationSettingsRequest(buildLocationRequest(locationOptions)))
          .addOnSuccessListener(response -> requestPositionUpdates(requestGeneration))
          .addOnCanceledListener(() -> fail(requestGeneration, ErrorCodes.errorWhileAcquiringPosition))
          .addOnFailureListener(error -> {
            if (!isActive(requestGeneration)) return;
            if (error instanceof ResolvableApiException) {
              ResolvableApiException resolvable = (ResolvableApiException) error;
              if (activity == null
                  || resolvable.getStatusCode() != LocationSettingsStatusCodes.RESOLUTION_REQUIRED) {
                fail(requestGeneration, ErrorCodes.locationServicesDisabled);
                return;
              }
              try {
                awaitingResolution = true;
                resolvable.startResolutionForResult(activity, activityRequestCode);
              } catch (IntentSender.SendIntentException exception) {
                fail(requestGeneration, ErrorCodes.locationServicesDisabled);
              }
            } else if (error instanceof ApiException
                && ((ApiException) error).getStatusCode()
                    == LocationSettingsStatusCodes.SETTINGS_CHANGE_UNAVAILABLE) {
              requestPositionUpdates(requestGeneration);
            } else {
              fail(requestGeneration, error instanceof SecurityException
                  ? ErrorCodes.permissionDenied : ErrorCodes.locationServicesDisabled);
            }
          });
    } catch (RuntimeException error) {
      fail(requestGeneration, error instanceof SecurityException ? ErrorCodes.permissionDenied
          : ErrorCodes.errorWhileAcquiringPosition);
    }
  }

  public void stopPositionUpdates() {
    // Invalidate first: queued settings, registration and location callbacks are stale.
    active = false;
    ++generation;
    awaitingResolution = false;
    positionChangedCallback = null;
    errorCallback = null;
    LocationCallback callback = locationCallback;
    locationCallback = null;
    try {
      nmeaClient.stop();
    } catch (RuntimeException error) {
      Log.w(TAG, "Failed to remove auxiliary location listeners", error);
    } finally {
      removeLocationUpdates(callback);
    }
  }
}
