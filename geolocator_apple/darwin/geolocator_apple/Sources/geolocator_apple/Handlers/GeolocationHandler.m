//
//  LocationManager.m
//  geolocator
//
//  Created by Maurits van Beusekom on 20/06/2020.
//

#import "../include/geolocator_apple/Handlers/GeolocationHandler.h"
#import "../include/geolocator_apple/Handlers/GeolocationHandler_Test.h"
#import "../include/geolocator_apple/Constants/ErrorCodes.h"

double const kMaxLocationLifeTimeInSeconds = 5.0;

@interface GeolocationHandler() <CLLocationManagerDelegate>

@property(strong, nonatomic, nonnull) CLLocationManager *locationManager;
@property(strong, nonatomic) GeolocatorError errorHandler;

@property(strong, nonatomic, nonnull) CLLocationManager *oneTimeLocationManager;
@property(strong, nonatomic) GeolocatorError oneTimeErrorHandler;

@property(strong, nonatomic) GeolocatorResult currentLocationResultHandler;
@property(strong, nonatomic) GeolocatorResult listenerResultHandler;
@property(nonatomic) NSUInteger listenerGeneration;

@end

@implementation GeolocationHandler

- (id) init {
  self = [super init];
  
  if (!self) {
    return nil;
  }
  
  return self;
}

- (CLLocationManager *) getLocationManager {
  if (!self.locationManager) {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
  }
  return self.locationManager;
}

- (void)setLocationManagerOverride:(CLLocationManager *)locationManager {
  self.locationManager = locationManager;
}

- (CLLocationManager *) getOneTimeLocationManager {
  if (!self.oneTimeLocationManager) {
    self.oneTimeLocationManager = [[CLLocationManager alloc] init];
    self.oneTimeLocationManager.delegate = self;
  }
  return self.oneTimeLocationManager;
}

- (void)setOneTimeLocationManagerOverride:(CLLocationManager *)locationManager {
  self.oneTimeLocationManager = locationManager;
}

- (CLLocation *) getLastKnownPosition {
  CLLocationManager *locationManager = [self getLocationManager];
  CLLocation *cashedLocation = [locationManager location];
  if (cashedLocation != nil) {
    return cashedLocation;
  }
  CLLocationManager *persistentLocationManager = [self getOneTimeLocationManager];
  return [persistentLocationManager location];
}

- (void)requestPositionWithDesiredAccuracy:(CLLocationAccuracy)desiredAccuracy
                             resultHandler:(GeolocatorResult _Nonnull)resultHandler
                              errorHandler:(GeolocatorError _Nonnull)errorHandler {
  self.oneTimeErrorHandler = errorHandler;
  self.currentLocationResultHandler = resultHandler;
  
  BOOL showBackgroundLocationIndicator = NO;
  BOOL allowBackgroundLocationUpdates = NO;
  
  [self startUpdatingLocationWithDesiredAccuracy:desiredAccuracy
                                  distanceFilter:kCLDistanceFilterNone
               pauseLocationUpdatesAutomatically:NO
                                    activityType:CLActivityTypeOther
                   isListeningForPositionUpdates:NO
                 showBackgroundLocationIndicator:showBackgroundLocationIndicator
                  allowBackgroundLocationUpdates:allowBackgroundLocationUpdates];
}

- (void)startListeningWithDesiredAccuracy:(CLLocationAccuracy)desiredAccuracy
                           distanceFilter:(CLLocationDistance)distanceFilter
        pauseLocationUpdatesAutomatically:(BOOL)pauseLocationUpdatesAutomatically
          showBackgroundLocationIndicator:(BOOL)showBackgroundLocationIndicator
                             activityType:(CLActivityType)activityType
           allowBackgroundLocationUpdates:(BOOL)allowBackgroundLocationUpdates
                            resultHandler:(GeolocatorResult _Nonnull )resultHandler
                             errorHandler:(GeolocatorError _Nonnull)errorHandler {
  
  ++self.listenerGeneration;
  self.errorHandler = errorHandler;
  self.listenerResultHandler = resultHandler;
  
  [self startUpdatingLocationWithDesiredAccuracy:desiredAccuracy
                                  distanceFilter:distanceFilter
               pauseLocationUpdatesAutomatically:pauseLocationUpdatesAutomatically
                                    activityType:activityType
                   isListeningForPositionUpdates:YES
                 showBackgroundLocationIndicator:showBackgroundLocationIndicator
                  allowBackgroundLocationUpdates:allowBackgroundLocationUpdates];
}

- (void)startUpdatingLocationWithDesiredAccuracy:(CLLocationAccuracy)desiredAccuracy
                                  distanceFilter:(CLLocationDistance)distanceFilter
               pauseLocationUpdatesAutomatically:(BOOL)pauseLocationUpdatesAutomatically
                                    activityType:(CLActivityType)activityType
                   isListeningForPositionUpdates:(BOOL)isListeningForPositionUpdates
                 showBackgroundLocationIndicator:(BOOL)showBackgroundLocationIndicator
                  allowBackgroundLocationUpdates:(BOOL)allowBackgroundLocationUpdates
{
  
  if (isListeningForPositionUpdates) {
    CLLocationManager *locationManager = [self getLocationManager];
    locationManager.desiredAccuracy = desiredAccuracy;
    locationManager.distanceFilter = distanceFilter;
    if (@available(iOS 6.0, macOS 10.15, *)) {
      locationManager.activityType = activityType;
      locationManager.pausesLocationUpdatesAutomatically = pauseLocationUpdatesAutomatically;
    }
    
#if TARGET_OS_IOS
    locationManager.allowsBackgroundLocationUpdates = allowBackgroundLocationUpdates
    && [GeolocationHandler shouldEnableBackgroundLocationUpdates];
    locationManager.showsBackgroundLocationIndicator = showBackgroundLocationIndicator;
#endif
    [locationManager startUpdatingLocation];
  } else {
    CLLocationManager *locationManager = [self getOneTimeLocationManager];
    locationManager.desiredAccuracy = desiredAccuracy;
    locationManager.distanceFilter = distanceFilter;
    [locationManager startUpdatingLocation];
  }
}

- (void)stopOneTimeLocationListening {
  [[self getOneTimeLocationManager] stopUpdatingLocation];
  self.oneTimeErrorHandler = nil;
  self.currentLocationResultHandler = nil;
}

- (void)stopListening {
    ++self.listenerGeneration;
    [[self getLocationManager] stopUpdatingLocation];
    self.errorHandler = nil;
    self.listenerResultHandler = nil;
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
  if (locations.count == 0) return;

  if (manager == self.oneTimeLocationManager) {
    CLLocation *latest = locations.lastObject;
    if (-[latest.timestamp timeIntervalSinceNow] > kMaxLocationLifeTimeInSeconds) return;
    GeolocatorResult result = self.currentLocationResultHandler;
    // Clear before invoking client code: it may start another one-shot request.
    [self stopOneTimeLocationListening];
    if (result) result(latest);
    return;
  }

  if (manager != self.locationManager) return;
  // A one-shot manager must never inject its fixes into the recording stream.
  // Core Location supplies these fixes in chronological order.
  NSUInteger generation = self.listenerGeneration;
  GeolocatorResult listener = self.listenerResultHandler;
  for (CLLocation *location in locations) {
    if (!listener || self.listenerGeneration != generation) break;
    listener(location);
  }
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(nonnull NSError *)error {
  if ([error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorLocationUnknown) {
    return;
  }

  if (manager == self.oneTimeLocationManager) {
    GeolocatorError handler = self.oneTimeErrorHandler;
    [self stopOneTimeLocationListening];
    if (handler) handler(GeolocatorErrorLocationUpdateFailure, error.localizedDescription);
  } else if (manager == self.locationManager) {
    GeolocatorError handler = self.errorHandler;
    if (handler) handler(GeolocatorErrorLocationUpdateFailure, error.localizedDescription);
  }
}

+ (BOOL) shouldEnableBackgroundLocationUpdates {
  return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"] containsObject: @"location"];
}
@end
