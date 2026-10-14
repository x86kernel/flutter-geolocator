//
//  LocationServiceHandler.m
//  geolocator
//
//  Created by Floris Smit on 10/06/2021.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "../include/geolocator_apple/Handlers/LocationServiceStreamHandler.h"
#import "../include/geolocator_apple/Utils/ServiceStatus.h"

@interface LocationServiceStreamHandler()
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (nonatomic) NSUInteger listenerGeneration;
@end

@implementation LocationServiceStreamHandler {
  FlutterEventSink _eventSink;
}

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
  ++self.listenerGeneration;
  self.locationManager.delegate = nil;
  self.locationManager = nil;
  _eventSink = nil;
  return nil;
}

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events {
  ++self.listenerGeneration;
  _eventSink = events;
  if (self.locationManager == nil) {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
  }
  return nil;
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status{
  if (!_eventSink || manager != self.locationManager) return;
  NSUInteger generation = self.listenerGeneration;
  dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    BOOL isEnabled = [CLLocationManager locationServicesEnabled];
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        // Cancellation may occur while the service status is being queried.
        // A queued result also must not be delivered to a replacement listener.
        if (!self->_eventSink || generation != self.listenerGeneration) return;
        if (isEnabled) {
            self->_eventSink([NSNumber numberWithInt:(ServiceStatus)enabled]);
        } else {
            self->_eventSink([NSNumber numberWithInt:(ServiceStatus)disabled]);
        }
    });
  });
}

@end
