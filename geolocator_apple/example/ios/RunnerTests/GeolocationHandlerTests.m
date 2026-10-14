//
//  RunnerTests.m
//  RunnerTests
//
//  Created by Maurits van Beusekom on 07/02/2022.
//

@import geolocator_apple;
@import geolocator_apple.Private;
@import geolocator_apple.Test;
@import XCTest;

#import <OCMock/OCMock.h>
#import <CoreLocation/CoreLocation.h>

@interface GeolocationHandlerTests : XCTestCase

@end

@implementation GeolocationHandlerTests {
  CLLocationManager *_mockLocationManager;
  CLLocationManager *_mockOneTimeLocationManager;
  
  GeolocationHandler *_geolocationHandler;
}

- (void)setUp {
  _mockLocationManager = OCMClassMock(CLLocationManager.class);
  _mockOneTimeLocationManager = OCMClassMock(CLLocationManager.class);
  
  _geolocationHandler = [[GeolocationHandler alloc] init];
  [_geolocationHandler setLocationManagerOverride:_mockLocationManager];
  [_geolocationHandler setOneTimeLocationManagerOverride:_mockOneTimeLocationManager];
}

#pragma mark - Test requesting current location

- (void)testGetCurrentPositionShouldCallStartUpdatingLocation {
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
                                            resultHandler:^(CLLocation * _Nullable location) {}
                                             errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {}];
  
  OCMVerify(times(1), [self->_mockOneTimeLocationManager setDesiredAccuracy:kCLLocationAccuracyBest]);
  OCMVerify(times(1), [self->_mockOneTimeLocationManager startUpdatingLocation]);
}

- (void)testRequestPositionShouldReturnLocationWithinTimeConstraints {
  NSDate *now = [NSDate date];
  NSCalendar *calendar = [NSCalendar currentCalendar];
  
  CLLocation *firstLocation = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(54.0, 6.4)
                                                            altitude:0.0
                                                  horizontalAccuracy:0
                                                    verticalAccuracy:0
                                                           timestamp:[calendar dateByAddingUnit:NSCalendarUnitSecond value:-6 toDate:now options:0]];
  CLLocation *secondLocation = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(54.1, 6.4)
                                                             altitude:0.0
                                                   horizontalAccuracy:0
                                                     verticalAccuracy:0
                                                            timestamp:now];
  
  
  XCTestExpectation *expectation = [self expectationWithDescription:@"expect result return third location"];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
                                            resultHandler:^(CLLocation * _Nullable location) {
    XCTAssertEqual(location, secondLocation);
    [expectation fulfill];
  }
                                             errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {}];
  
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations: @[firstLocation]];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations: @[secondLocation]];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(times(1), [self->_mockOneTimeLocationManager stopUpdatingLocation]);
}

- (void)testRequestPositionShouldStopListeningOnResult {
  CLLocation *location = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(54.1, 6.4)
                                                       altitude:0.0
                                             horizontalAccuracy:0
                                               verticalAccuracy:0
                                                      timestamp:[NSDate date]];
  
  XCTestExpectation *expectation = [self expectationWithDescription:@"expect first result return third location"];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
                                            resultHandler:^(CLLocation * _Nullable location) {
    [expectation fulfill];
  }
                                             errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations: @[location]];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(times(1), [self->_mockOneTimeLocationManager stopUpdatingLocation]);
}

- (void)testRequestPositionShouldStopListeningOnError {
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
  
  XCTestExpectation *expectation = [self expectationWithDescription:@"expect result return third location"];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
                                            resultHandler:^(CLLocation * _Nullable location) {
  }
                                             errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    [expectation fulfill];
    
  }];
  
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didFailWithError: error];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(times(1), [self->_mockOneTimeLocationManager stopUpdatingLocation]);
}

- (void)testRequestPositionShouldNotStopListeningOnErrorDomainAndErrorLocationUnknown {
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorLocationUnknown userInfo:nil];
  
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
                                            resultHandler:^(CLLocation * _Nullable location) {
  }
                                             errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    XCTFail();
  }];
  
  [_geolocationHandler locationManager:_mockLocationManager didFailWithError: error];
}


#pragma mark - Test listening to location stream

- (void)testStartListeningShouldNotStopListeningWhenListeningToStream {
  CLLocation *mockLocation = [[CLLocation alloc] initWithLatitude:54.0 longitude:6.4];
  
  XCTestExpectation *expectation = [self expectationWithDescription:@"expect result return third location"];
  [_geolocationHandler startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                          distanceFilter:0
                       pauseLocationUpdatesAutomatically:NO
                         showBackgroundLocationIndicator:NO
                                            activityType:CLActivityTypeOther
                          allowBackgroundLocationUpdates:NO
                                           resultHandler:^(CLLocation * _Nullable location) {
    XCTAssertEqual(location, mockLocation);
    [expectation fulfill];
  }
                                            errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations: @[mockLocation]];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(never(), [self->_mockLocationManager stopUpdatingLocation]);
}

- (void)testRequestingPositionWhileListeningDoesntStopStream {
  CLLocation *mockLocation = [[CLLocation alloc] initWithLatitude:54.0 longitude:6.4];
  XCTestExpectation *expectationStream = [self expectationWithDescription:@"expect result return third location"];
  XCTestExpectation *expectationForeground = [self expectationWithDescription:@"expect result return third location"];
  [_geolocationHandler startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                          distanceFilter:0
                       pauseLocationUpdatesAutomatically:NO
                         showBackgroundLocationIndicator:NO
                                            activityType:CLActivityTypeOther
                          allowBackgroundLocationUpdates:NO
                                           resultHandler:^(CLLocation * _Nullable location) {
    XCTAssertEqual(location, mockLocation);
    [expectationStream fulfill];
  }
                                            errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyHundredMeters
                                            resultHandler:^(CLLocation * _Nullable location) {
    XCTAssertEqual(location, mockLocation);
    [expectationForeground fulfill];
  } errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations: @[mockLocation]];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations: @[mockLocation]];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(never(), [self->_mockLocationManager stopUpdatingLocation]);
}

- (void)testStartListeningShouldNotStopListeningOnError {
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
  XCTestExpectation *expectation = [self expectationWithDescription:@"expect result return third location"];
  [_geolocationHandler startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                          distanceFilter:0
                       pauseLocationUpdatesAutomatically:NO
                         showBackgroundLocationIndicator:NO
                                            activityType:CLActivityTypeOther
                          allowBackgroundLocationUpdates:NO
                                           resultHandler:^(CLLocation * _Nullable location) {
  }
                                            errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    XCTAssertEqualObjects(errorCode, @"LOCATION_UPDATE_FAILURE");
    [expectation fulfill];
  }];
  
  [_geolocationHandler locationManager:_mockLocationManager didFailWithError:error];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(never(), [self->_mockLocationManager stopUpdatingLocation]);
}

- (void)testStartListeningShouldNotReportErrorOnErrorDomainAndErrorLocationUnknown {
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorLocationUnknown userInfo:nil];
  CLLocation *mockLocation = [[CLLocation alloc] initWithLatitude:54.0 longitude:6.4];
  XCTestExpectation *expectation = [self expectationWithDescription:@"expect result return third location"];
  [_geolocationHandler startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                          distanceFilter:0
                       pauseLocationUpdatesAutomatically:NO
                         showBackgroundLocationIndicator:NO
                                            activityType:CLActivityTypeOther
                          allowBackgroundLocationUpdates:NO
                                           resultHandler:^(CLLocation * _Nullable location) {
    [expectation fulfill];
  }
                                            errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    XCTFail();
  }];
  
  [_geolocationHandler locationManager:_mockLocationManager didFailWithError:error];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations: @[mockLocation]];
  
  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  
  OCMVerify(never(), [self->_mockLocationManager stopUpdatingLocation]);
}

- (void)testListeningBackgroundGeolocationOnlyWhenAllowedAndEnabled {
  id geolocationHandlerMock = OCMPartialMock(_geolocationHandler);
  [geolocationHandlerMock setLocationManagerOverride:_mockLocationManager];
  OCMStub(ClassMethod([geolocationHandlerMock shouldEnableBackgroundLocationUpdates]))._andReturn([NSNumber numberWithBool:YES]);
  [geolocationHandlerMock startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                             distanceFilter:0
                          pauseLocationUpdatesAutomatically:NO
                            showBackgroundLocationIndicator:NO
                                               activityType:CLActivityTypeOther
                             allowBackgroundLocationUpdates:YES
                                              resultHandler:^(CLLocation * _Nullable location) {
  }
                                               errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  OCMVerify([_mockLocationManager setAllowsBackgroundLocationUpdates:YES]);
}

- (void)testNotListeningBackgroundGeolocationWhenNotEnabled {
  id geolocationHandlerMock = OCMPartialMock(_geolocationHandler);
  [geolocationHandlerMock setLocationManagerOverride:_mockLocationManager];
  OCMStub(ClassMethod([geolocationHandlerMock shouldEnableBackgroundLocationUpdates]))._andReturn([NSNumber numberWithBool:YES]);
  [geolocationHandlerMock startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                             distanceFilter:0
                          pauseLocationUpdatesAutomatically:NO
                            showBackgroundLocationIndicator:NO
                                               activityType:CLActivityTypeOther
                             allowBackgroundLocationUpdates:NO
                                              resultHandler:^(CLLocation * _Nullable location) {
  }
                                               errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  OCMVerify(never(), [_mockLocationManager setAllowsBackgroundLocationUpdates:YES]);
}

- (void)testKeepLocationManagerSettingsWhenRequestingCurrentPosition {
  id geolocationHandlerMock = OCMPartialMock(_geolocationHandler);
  [geolocationHandlerMock setLocationManagerOverride:_mockLocationManager];
  OCMStub(ClassMethod([geolocationHandlerMock shouldEnableBackgroundLocationUpdates]))
    ._andReturn([NSNumber numberWithBool:YES]);
  OCMStub([_mockLocationManager allowsBackgroundLocationUpdates])
    ._andReturn([NSNumber numberWithBool:YES]);
  if (@available(iOS 11.0, *)) {
    OCMStub([_mockLocationManager showsBackgroundLocationIndicator])
      ._andReturn([NSNumber numberWithBool:YES]);
  }
  [geolocationHandlerMock startListeningWithDesiredAccuracy: kCLLocationAccuracyBest
                                             distanceFilter:0
                          pauseLocationUpdatesAutomatically:NO
                            showBackgroundLocationIndicator:YES
                                               activityType:CLActivityTypeOther
                             allowBackgroundLocationUpdates:YES
                                              resultHandler:^(CLLocation * _Nullable location) {
  }
                                               errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  OCMVerify([_mockLocationManager setAllowsBackgroundLocationUpdates:YES]);
  if (@available(iOS 11.0, *)) {
    OCMVerify([_mockLocationManager setShowsBackgroundLocationIndicator:YES]);
  }
  [geolocationHandlerMock requestPositionWithDesiredAccuracy: kCLLocationAccuracyBest
                                               resultHandler:^(CLLocation * _Nullable location) {}
                                                errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {}];
  OCMVerify(never(), [_mockLocationManager setAllowsBackgroundLocationUpdates:NO]);
  if (@available(iOS 11.0, *)) {
    OCMVerify(never(), [_mockLocationManager setShowsBackgroundLocationIndicator:NO]);
  }
}

- (void)testKeepLocationManagerSettingsWhenRequestingCurrentPosition1 {
  [_geolocationHandler startListeningWithDesiredAccuracy:kCLLocationAccuracyThreeKilometers
                                          distanceFilter:kCLLocationAccuracyThreeKilometers
                       pauseLocationUpdatesAutomatically:NO
                         showBackgroundLocationIndicator:YES
                                            activityType:CLActivityTypeOther
                          allowBackgroundLocationUpdates:YES
                                           resultHandler:^(CLLocation * _Nullable location) {
  }
                                            errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {
    
  }];
  OCMVerify([_mockLocationManager setDesiredAccuracy:kCLLocationAccuracyThreeKilometers]);
  OCMVerify([_mockLocationManager setDistanceFilter:kCLLocationAccuracyThreeKilometers]);
  
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
                                            resultHandler:^(CLLocation * _Nullable location) {}
                                             errorHandler:^(NSString * _Nonnull errorCode, NSString * _Nonnull errorDescription) {}];
  OCMVerify([_mockOneTimeLocationManager setDesiredAccuracy:kCLLocationAccuracyBest]);
  OCMVerify([_mockOneTimeLocationManager setDistanceFilter:kCLDistanceFilterNone]);
  
  OCMVerify(never(), [_mockLocationManager setDesiredAccuracy:kCLLocationAccuracyBest]);
  OCMVerify(never(), [_mockLocationManager setDistanceFilter:kCLDistanceFilterNone]);
}

- (void)listenForBatchWithHandler:(GeolocatorResult)handler {
  [_geolocationHandler startListeningWithDesiredAccuracy:kCLLocationAccuracyBest
                                         distanceFilter:0
                      pauseLocationUpdatesAutomatically:NO
                        showBackgroundLocationIndicator:NO
                                           activityType:CLActivityTypeFitness
                         allowBackgroundLocationUpdates:NO
                                          resultHandler:handler
                                           errorHandler:^(NSString *code, NSString *description) {
    XCTFail(@"Unexpected error: %@", code);
  }];
}

- (void)testStreamDeliversEntireBatchInOrderIncludingOlderFixes {
  NSDate *now = [NSDate date];
  CLLocation *first = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(54.0, 6.4)
      altitude:10 horizontalAccuracy:5 verticalAccuracy:5 timestamp:[now dateByAddingTimeInterval:-10]];
  CLLocation *second = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(54.1, 6.4)
      altitude:11 horizontalAccuracy:5 verticalAccuracy:5 timestamp:now];
  NSMutableArray<CLLocation *> *received = [NSMutableArray array];
  [self listenForBatchWithHandler:^(CLLocation *location) { [received addObject:location]; }];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations:@[first, second]];
  XCTAssertEqualObjects(received, (@[first, second]));
  XCTAssertEqualObjects(received[0].timestamp, first.timestamp);
  XCTAssertEqualObjects(received[1].timestamp, second.timestamp);
}

- (void)testStoppingStreamDuringBatchStopsRemainingDelivery {
  __block NSUInteger received = 0;
  GeolocationHandler *handler = _geolocationHandler;
  [self listenForBatchWithHandler:^(CLLocation *location) {
    received++;
    [handler stopListening];
  }];
  CLLocation *location = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations:@[location, location]];
  XCTAssertEqual(received, 1u);
}

- (void)testOneShotStillReturnsOnlyNewestFixFromBatch {
  __block NSUInteger received = 0;
  CLLocation *first = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  CLLocation *second = [[CLLocation alloc] initWithLatitude:54.1 longitude:6.4];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      resultHandler:^(CLLocation *location) {
        received++;
        XCTAssertEqual(location, second);
      } errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[first, second]];
  XCTAssertEqual(received, 1u);
}

- (void)testEmptyBatchDoesNotDeliverStreamEvent {
  [self listenForBatchWithHandler:^(CLLocation *location) { XCTFail(); }];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations:@[]];
}

- (void)testOneShotAndStreamDeliverOnlyTheirOwnBatches {
  CLLocation *streamFix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  CLLocation *oneShotFix = [[CLLocation alloc] initWithLatitude:55 longitude:6.4];
  NSMutableArray *streamResults = [NSMutableArray array];
  NSMutableArray *oneShotResults = [NSMutableArray array];
  [self listenForBatchWithHandler:^(CLLocation *location) { [streamResults addObject:location]; }];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      resultHandler:^(CLLocation *location) { [oneShotResults addObject:location]; }
      errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations:@[streamFix]];
  XCTAssertEqual(oneShotResults.count, 0u);
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[oneShotFix]];
  XCTAssertEqualObjects(streamResults, (@[streamFix]));
  XCTAssertEqualObjects(oneShotResults, (@[oneShotFix]));
}

- (void)testOneShotFailureDoesNotFailRecordingStream {
  __block NSUInteger streamFixes = 0;
  __block NSUInteger oneShotErrors = 0;
  [self listenForBatchWithHandler:^(CLLocation *location) { streamFixes++; }];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      resultHandler:^(CLLocation *location) { XCTFail(); }
      errorHandler:^(NSString *code, NSString *description) { oneShotErrors++; }];
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didFailWithError:error];
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations:@[fix]];
  XCTAssertEqual(oneShotErrors, 1u);
  XCTAssertEqual(streamFixes, 1u);
}

- (void)testOneShotCallbackCanStartAnotherRequest {
  __block NSUInteger results = 0;
  GeolocationHandler *handler = _geolocationHandler;
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      resultHandler:^(CLLocation *location) {
        results++;
        [handler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
            resultHandler:^(CLLocation *next) { results++; }
            errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
      } errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  XCTAssertEqual(results, 2u);
}

- (void)testStreamFailureDoesNotConsumeOneShotRequest {
  __block NSUInteger streamErrors = 0;
  __block NSUInteger oneShotResults = 0;
  [_geolocationHandler startListeningWithDesiredAccuracy:kCLLocationAccuracyBest
      distanceFilter:0 pauseLocationUpdatesAutomatically:NO showBackgroundLocationIndicator:NO
      activityType:CLActivityTypeFitness allowBackgroundLocationUpdates:NO
      resultHandler:^(CLLocation *location) {}
      errorHandler:^(NSString *code, NSString *description) { streamErrors++; }];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      resultHandler:^(CLLocation *location) { oneShotResults++; }
      errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
  [_geolocationHandler locationManager:_mockLocationManager didFailWithError:error];
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  XCTAssertEqual(streamErrors, 1u);
  XCTAssertEqual(oneShotResults, 1u);
}


- (void)testConcurrentOneShotsCompleteOnceWithMostAccurateSettings {
  __block NSUInteger first = 0, second = 0;
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBestForNavigation
      requestId:@"first" resultHandler:^(CLLocation *location) { first++; }
      errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyHundredMeters
      requestId:@"second" resultHandler:^(CLLocation *location) { second++; }
      errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  OCMVerify(times(2), [_mockOneTimeLocationManager setDesiredAccuracy:kCLLocationAccuracyBestForNavigation]);
  OCMVerify(never(), [_mockOneTimeLocationManager setDesiredAccuracy:kCLLocationAccuracyHundredMeters]);
  OCMVerify(times(1), [_mockOneTimeLocationManager startUpdatingLocation]);
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  XCTAssertEqual(first, 1u);
  XCTAssertEqual(second, 1u);
  OCMVerify(times(1), [_mockOneTimeLocationManager stopUpdatingLocation]);
}

- (void)testConcurrentOneShotErrorsCompleteEveryRequest {
  __block NSUInteger errors = 0;
  for (NSString *identifier in @[@"first", @"second"]) {
    [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
        requestId:identifier resultHandler:^(CLLocation *location) { XCTFail(); }
        errorHandler:^(NSString *code, NSString *description) { errors++; }];
  }
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didFailWithError:error];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didFailWithError:error];
  XCTAssertEqual(errors, 2u);
  OCMVerify(times(1), [_mockOneTimeLocationManager stopUpdatingLocation]);
}

- (void)testCancellingOneRequestPreservesOtherRequestAndRecording {
  __block NSUInteger cancelled = 0, completed = 0, streamed = 0;
  [self listenForBatchWithHandler:^(CLLocation *location) { streamed++; }];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBestForNavigation
      requestId:@"cancelled" resultHandler:^(CLLocation *location) {
        XCTAssertNil(location);
        cancelled++;
      } errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyHundredMeters
      requestId:@"remaining" resultHandler:^(CLLocation *location) {
        XCTAssertNotNil(location);
        completed++;
      } errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:@"cancelled"];
  OCMVerify(never(), [_mockOneTimeLocationManager stopUpdatingLocation]);
  OCMVerify(times(1), [_mockOneTimeLocationManager setDesiredAccuracy:kCLLocationAccuracyHundredMeters]);
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  [_geolocationHandler locationManager:_mockLocationManager didUpdateLocations:@[fix]];
  XCTAssertEqual(cancelled, 1u);
  XCTAssertEqual(completed, 1u);
  XCTAssertEqual(streamed, 1u);
  OCMVerify(never(), [_mockLocationManager stopUpdatingLocation]);
}

- (void)testCancellingLastRequestStopsManagerAndIgnoresLateEvents {
  __block NSUInteger cancelled = 0;
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      requestId:@"last" resultHandler:^(CLLocation *location) {
        XCTAssertNil(location);
        cancelled++;
      } errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:@"unknown"];
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:nil];
  OCMVerify(never(), [_mockOneTimeLocationManager stopUpdatingLocation]);
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:@"last"];
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:@"last"];
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didFailWithError:error];
  XCTAssertEqual(cancelled, 1u);
  OCMVerify(times(1), [_mockOneTimeLocationManager stopUpdatingLocation]);
}

- (void)testCancellationCallbackCanStartAnotherRequest {
  __block NSUInteger results = 0;
  GeolocationHandler *handler = _geolocationHandler;
  [_geolocationHandler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
      requestId:@"old" resultHandler:^(CLLocation *location) {
        XCTAssertNil(location);
        [handler requestPositionWithDesiredAccuracy:kCLLocationAccuracyBest
            requestId:@"new" resultHandler:^(CLLocation *next) { results++; }
            errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
      } errorHandler:^(NSString *code, NSString *description) { XCTFail(); }];
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:@"old"];
  // A delayed cancellation of the previous request must not consume the new one.
  [_geolocationHandler cancelGetCurrentPositionWithRequestId:@"old"];
  CLLocation *fix = [[CLLocation alloc] initWithLatitude:54 longitude:6.4];
  [_geolocationHandler locationManager:_mockOneTimeLocationManager didUpdateLocations:@[fix]];
  XCTAssertEqual(results, 1u);
}


- (void)testForegroundStreamAcknowledgesAfterNativeStart {
  id application = OCMPartialMock([UIApplication sharedApplication]);
  OCMStub([application applicationState]).andReturn(UIApplicationStateActive);
  id bundle = OCMPartialMock([NSBundle mainBundle]);
  OCMStub([bundle objectForInfoDictionaryKey:@"UIBackgroundModes"]).andReturn(@[@"location"]);
  __block BOOL started = NO;
  OCMStub([_mockLocationManager startUpdatingLocation]).andDo(^(NSInvocation *invocation) { started = YES; });
  PositionStreamHandler *stream = [[PositionStreamHandler alloc] initWithGeolocationHandler:_geolocationHandler];
  __block NSUInteger acknowledgements = 0;
  [stream onListenWithArguments:@{@"requireForeground": @YES, @"allowBackgroundLocationUpdates": @YES}
                     eventSink:^(id event) {
    XCTAssertTrue(started);
    XCTAssertEqualObjects(event[@"event"], @"positionStreamStarted");
    acknowledgements++;
  }];
  XCTAssertEqual(acknowledgements, 1u);
  OCMVerify([_mockLocationManager setAllowsBackgroundLocationUpdates:YES]);
  [stream onCancelWithArguments:nil];
  [bundle stopMocking];
  [application stopMocking];
}

- (void)testForegroundStreamDefersUntilActiveAndDoesNotRestartOnLaterResume {
  __block UIApplicationState state = UIApplicationStateBackground;
  id application = OCMPartialMock([UIApplication sharedApplication]);
  OCMStub([application applicationState]).andDo(^(NSInvocation *invocation) { [invocation setReturnValue:&state]; });
  PositionStreamHandler *stream = [[PositionStreamHandler alloc] initWithGeolocationHandler:_geolocationHandler];
  __block NSUInteger acknowledgements = 0;
  [stream onListenWithArguments:@{@"requireForeground": @YES}
                     eventSink:^(id event) { acknowledgements++; }];
  OCMVerify(times(0), [_mockLocationManager startUpdatingLocation]);
  XCTAssertEqual(acknowledgements, 0u);
  state = UIApplicationStateActive;
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  OCMVerify(times(1), [_mockLocationManager startUpdatingLocation]);
  XCTAssertEqual(acknowledgements, 1u);
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  OCMVerify(times(1), [_mockLocationManager startUpdatingLocation]);
  [stream onCancelWithArguments:nil];
  [application stopMocking];
}

- (void)testCancelledForegroundWaitCannotStartOnResume {
  __block UIApplicationState state = UIApplicationStateInactive;
  id application = OCMPartialMock([UIApplication sharedApplication]);
  OCMStub([application applicationState]).andDo(^(NSInvocation *invocation) { [invocation setReturnValue:&state]; });
  PositionStreamHandler *stream = [[PositionStreamHandler alloc] initWithGeolocationHandler:_geolocationHandler];
  [stream onListenWithArguments:@{@"requireForeground": @YES}
                     eventSink:^(id event) { XCTFail(@"Cancelled startup must not acknowledge"); }];
  [stream onCancelWithArguments:nil];
  state = UIApplicationStateActive;
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  OCMVerify(times(0), [_mockLocationManager startUpdatingLocation]);
  [application stopMocking];
}

- (void)testForegroundStreamRejectsMissingBackgroundMode {
  id bundle = OCMPartialMock([NSBundle mainBundle]);
  OCMStub([bundle objectForInfoDictionaryKey:@"UIBackgroundModes"]).andReturn(@[]);
  PositionStreamHandler *stream = [[PositionStreamHandler alloc] initWithGeolocationHandler:_geolocationHandler];
  __block FlutterError *failure;
  [stream onListenWithArguments:@{@"requireForeground": @YES, @"allowBackgroundLocationUpdates": @YES}
                     eventSink:^(id event) { failure = event; }];
  XCTAssertEqualObjects(failure.code, @"BACKGROUND_LOCATION_UNAVAILABLE");
  OCMVerify(times(0), [_mockLocationManager startUpdatingLocation]);
  [stream onCancelWithArguments:nil];
  [bundle stopMocking];
}

@end
