#import "password-module.h"
#import <React-RCTAppDelegate/RCTDefaultReactNativeFactoryDelegate.h>
#import <AVFoundation/AVFoundation.h>
#import "PrelisMobile-Swift.h"

@implementation PasswordModule {
  PasswordService *_service;
}
+ (NSString *)moduleName { return @"NativePassword"; }
+ (BOOL)requiresMainQueueSetup { return NO; }
- (instancetype)init {
  if ((self = [super init])) _service = [PasswordService new];
  return self;
}
- (void)copyText:(NSString *)value resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service copyText:value resolve:resolve reject:reject]; }
- (void)randomBytes:(double)count resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject { [_service randomBytes:count resolve:resolve reject:reject]; }
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativePasswordSpecJSI>(params);
}
@end
