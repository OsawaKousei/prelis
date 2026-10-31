#import "timer-sound-module.h"
#import <React-RCTAppDelegate/RCTDefaultReactNativeFactoryDelegate.h>
#import <AVFoundation/AVFoundation.h>
#import "PrelisMobile-Swift.h"

@implementation TimerSoundModule {
  TimerSoundService *_service;
}
+ (NSString *)moduleName { return @"NativeTimerSound"; }
+ (BOOL)requiresMainQueueSetup { return NO; }
- (instancetype)init {
  if ((self = [super init])) _service = [TimerSoundService new];
  return self;
}
- (void)readLibrary:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service readLibrary:resolve reject:reject]; }
- (void)writeLibrary:(NSString *)content resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service writeLibrary:content resolve:resolve reject:reject]; }
- (void)deleteSoundFile:(NSString *)identifier resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service deleteSoundFile:identifier resolve:resolve reject:reject]; }
- (void)pickSound:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service pickSound:resolve reject:reject]; }
- (void)playSound:(NSString *)identifier loop:(BOOL)loop resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service playSound:identifier loop:loop resolve:resolve reject:reject]; }
- (void)stopSound:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service stopSound:resolve reject:reject]; }
- (void)invalidate { [_service invalidate]; }
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeTimerSoundSpecJSI>(params);
}
@end
