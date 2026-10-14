package com.baseflow.geolocator.location;

import android.location.Location;
import android.os.Build;
import android.os.Bundle;

import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;

public class LocationMapper {
  public static Map<String, Object> toHashMap(Location location) {
    if (location == null) {
      return null;
    }

    Map<String, Object> position = new HashMap<>();

    position.put("latitude", location.getLatitude());
    position.put("longitude", location.getLongitude());
    position.put("timestamp", location.getTime());
    position.put("is_mocked", isMocked(location));

    if (location.hasAltitude()) {
      position.put("altitude", location.getAltitude());
      position.put("altitude_reference", "ellipsoid");
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasVerticalAccuracy())
      position.put("altitude_accuracy", location.getVerticalAccuracyMeters());
    if (location.hasAccuracy()) position.put("accuracy", (double) location.getAccuracy());
    if (location.hasBearing()) position.put("heading", (double) location.getBearing());
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasBearingAccuracy())
      position.put("heading_accuracy", location.getBearingAccuracyDegrees());
    if (location.hasSpeed()) position.put("speed", (double) location.getSpeed());
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasSpeedAccuracy())
      position.put("speed_accuracy", (double) location.getSpeedAccuracyMetersPerSecond());

    if (location.getExtras() != null) {
      boolean useMslAltitude = location.getExtras().getBoolean(LocationOptions.USE_MSL_ALTITUDE_EXTRA, false);
      Double nmeaAltitude = getDoubleExtra(location.getExtras(), NmeaClient.NMEA_ALTITUDE_EXTRA);
      if (useMslAltitude && nmeaAltitude != null) {
        position.put("altitude", nmeaAltitude);
        position.put("altitude_reference", "meanSeaLevel");
        // Ellipsoid uncertainty does not describe an independently sampled NMEA altitude.
        position.remove("altitude_accuracy");
      }
      if (location.getExtras().containsKey(NmeaClient.GNSS_SATELLITE_COUNT_EXTRA)) {
        Double mslSatelliteCount =
            location.getExtras().getDouble(NmeaClient.GNSS_SATELLITE_COUNT_EXTRA);
        position.put("gnss_satellite_count", mslSatelliteCount);
      }
      if (location.getExtras().containsKey(NmeaClient.GNSS_SATELLITES_USED_IN_FIX_EXTRA)) {
        Double mslSatellitesUsedInFix =
            location.getExtras().getDouble(NmeaClient.GNSS_SATELLITES_USED_IN_FIX_EXTRA);
        position.put("gnss_satellites_used_in_fix", mslSatellitesUsedInFix);
      }
      if (useMslAltitude && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && location.hasMslAltitude())
      {
        double mslAltitude = location.getMslAltitudeMeters();
        position.put("altitude", mslAltitude);
        position.put("altitude_reference", "meanSeaLevel");
        position.remove("altitude_accuracy");
        if (location.hasMslAltitudeAccuracy()) {
          float mslAccuracy = location.getMslAltitudeAccuracyMeters();
          position.put("altitude_accuracy", mslAccuracy);
        }
      }
      // Location has no standard vertical-speed getter. Only forward an
      // existing provider extra; altitude accuracy is not speed accuracy.
      Double verticalSpeed =
          getDoubleExtra(
              location.getExtras(),
              NmeaClient.VERTICAL_SPEED_EXTRA,
              "vertical_speed",
              "verticalSpeed",
              "vVel");
      if (verticalSpeed != null) {
        position.put("vertical_speed", verticalSpeed);
      }
      Double verticalSpeedAccuracy =
          getDoubleExtra(
              location.getExtras(),
              NmeaClient.VERTICAL_SPEED_ACCURACY_EXTRA,
              "vertical_speed_accuracy",
              "verticalSpeedAccuracy");
      if (verticalSpeedAccuracy != null && verticalSpeedAccuracy >= 0.0) {
        position.put("vertical_speed_accuracy", verticalSpeedAccuracy);
      }
    }
    return position;
  }

  @Nullable
  private static Double getDoubleExtra(@Nullable Bundle extras, String... keys) {
    if (extras == null) {
      return null;
    }
    for (String key : keys) {
      if (extras.containsKey(key)) {
        Object value = extras.get(key);
        if (value instanceof Number) {
          double d = ((Number) value).doubleValue();
          if (!Double.isNaN(d) && !Double.isInfinite(d)) {
            return d;
          }
        }
      }
    }
    return null;
  }

  @SuppressWarnings("deprecation")
  private static boolean isMocked(Location location) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return location.isMock();
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
      return location.isFromMockProvider();
    } else {
      return false;
    }
  }
}
