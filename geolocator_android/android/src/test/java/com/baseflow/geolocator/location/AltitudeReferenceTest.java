package com.baseflow.geolocator.location;

import static org.junit.Assert.*;
import android.location.Location;
import android.os.Bundle;
import java.util.Map;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, manifest = Config.NONE)
public class AltitudeReferenceTest {
  private Location fix(boolean useMsl) {
    Location fix = new Location("gps");
    fix.setAltitude(100);
    fix.setVerticalAccuracyMeters(3);
    Bundle extras = new Bundle();
    extras.putBoolean(LocationOptions.USE_MSL_ALTITUDE_EXTRA, useMsl);
    fix.setExtras(extras);
    return fix;
  }

  @Test public void defaultKeepsEllipsoidDespiteNativeAndNmeaMsl() {
    Location fix = fix(false);
    fix.setMslAltitudeMeters(70);
    fix.getExtras().putDouble(NmeaClient.NMEA_ALTITUDE_EXTRA, 65);
    Map<String,Object> map = LocationMapper.toHashMap(fix);
    assertEquals(100.0, map.get("altitude"));
    assertEquals("ellipsoid", map.get("altitude_reference"));
    assertEquals(3.0f, map.get("altitude_accuracy"));
  }

  @Test public void explicitMslUsesNativeAccuracy() {
    Location fix = fix(true);
    fix.setMslAltitudeMeters(70);
    fix.setMslAltitudeAccuracyMeters(5);
    Map<String,Object> map = LocationMapper.toHashMap(fix);
    assertEquals(70.0, map.get("altitude"));
    assertEquals("meanSeaLevel", map.get("altitude_reference"));
    assertEquals(5.0f, map.get("altitude_accuracy"));
  }

  @Test public void mslWithoutAccuracyDoesNotBorrowEllipsoidAccuracy() {
    Location fix = fix(true); fix.setMslAltitudeMeters(70);
    assertFalse(LocationMapper.toHashMap(fix).containsKey("altitude_accuracy"));
  }

  @Test public void nmeaMslIsIdentifiedAndHasNoInventedAccuracy() {
    Location fix = fix(true); fix.getExtras().putDouble(NmeaClient.NMEA_ALTITUDE_EXTRA, 65);
    Map<String,Object> map = LocationMapper.toHashMap(fix);
    assertEquals(65.0, map.get("altitude"));
    assertEquals("meanSeaLevel", map.get("altitude_reference"));
    assertFalse(map.containsKey("altitude_accuracy"));
  }

  @Test public void missingMslFallsBackToExplicitEllipsoid() {
    assertEquals("ellipsoid", LocationMapper.toHashMap(fix(true)).get("altitude_reference"));
  }

  @Test public void missingAltitudeHasNoDatum() {
    assertFalse(LocationMapper.toHashMap(new Location("gps")).containsKey("altitude_reference"));
  }
}
