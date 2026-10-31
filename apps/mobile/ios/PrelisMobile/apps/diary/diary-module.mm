#import "diary-module.h"
#import <React-RCTAppDelegate/RCTDefaultReactNativeFactoryDelegate.h>
#import <AVFoundation/AVFoundation.h>
#import "PrelisMobile-Swift.h"

@implementation DiaryModule {
  DiaryService *_service;
}
+ (NSString *)moduleName { return @"NativeDiary"; }
+ (BOOL)requiresMainQueueSetup { return NO; }
- (instancetype)init {
  if ((self = [super init])) _service = [DiaryService new];
  return self;
}
- (void)readDiary:(NSString *)date resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service readDiary:date resolve:resolve reject:reject]; }
- (void)saveDiary:(NSString *)date content:(NSString *)content resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service saveDiary:date content:content resolve:resolve reject:reject]; }
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeDiarySpecJSI>(params);
}
@end
