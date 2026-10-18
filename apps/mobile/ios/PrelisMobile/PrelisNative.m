#import <AVFoundation/AVFoundation.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTUtils.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <stdlib.h>

static NSString *const PrelisErrorDomain = @"PrelisNative";
static NSUInteger const PrelisMaximumSoundBytes = 10 * 1024 * 1024;

@interface PrelisNative : NSObject <RCTBridgeModule, UIDocumentPickerDelegate, AVAudioPlayerDelegate>
@property(nonatomic, strong) AVAudioPlayer *player;
@property(nonatomic, strong) UIDocumentPickerViewController *picker;
@property(nonatomic, copy) RCTPromiseResolveBlock pickerResolve;
@property(nonatomic, copy) RCTPromiseRejectBlock pickerReject;
@end

@implementation PrelisNative

RCT_EXPORT_MODULE(PrelisNative)

+ (BOOL)requiresMainQueueSetup { return YES; }
- (dispatch_queue_t)methodQueue { return dispatch_get_main_queue(); }

- (NSError *)error:(NSString *)message {
  return [NSError errorWithDomain:PrelisErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (void)reject:(RCTPromiseRejectBlock)reject error:(NSError *)error {
  reject(@"PRELIS_ERROR", error.localizedDescription ?: @"処理に失敗しました。", error);
}

- (NSURL *)supportURL {
  return [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                  inDomains:NSUserDomainMask] firstObject];
}

- (BOOL)ensureDirectory:(NSURL *)url error:(NSError **)error {
  return [[NSFileManager defaultManager] createDirectoryAtURL:url
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error];
}

- (BOOL)validDate:(NSString *)date {
  return date.length == 10 &&
      [date rangeOfString:@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
                 options:NSRegularExpressionSearch].location != NSNotFound;
}

- (BOOL)validSoundID:(NSString *)identifier {
  return identifier.length == 36 &&
      [identifier rangeOfString:@"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
                        options:NSRegularExpressionSearch].location != NSNotFound;
}

- (NSURL *)soundDirectory {
  return [[self supportURL] URLByAppendingPathComponent:@"timer/sounds" isDirectory:YES];
}

- (NSURL *)soundIndex {
  return [[self supportURL] URLByAppendingPathComponent:@"timer/sounds.json"];
}

- (NSURL *)soundURL:(NSString *)identifier error:(NSError **)error {
  if (![self validSoundID:identifier]) {
    if (error) *error = [self error:@"音声IDが不正です。"];
    return nil;
  }
  return [[self soundDirectory] URLByAppendingPathComponent:identifier];
}

- (NSMutableDictionary *)library:(NSError **)error {
  NSURL *index = [self soundIndex];
  if (![[NSFileManager defaultManager] fileExistsAtPath:index.path]) {
    return [@{@"version": @1, @"sounds": [NSMutableArray array], @"selectedId": [NSNull null]} mutableCopy];
  }
  NSData *data = [NSData dataWithContentsOfURL:index options:0 error:error];
  if (!data) return nil;
  id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
  if (![value isKindOfClass:[NSMutableDictionary class]] ||
      ![value[@"version"] isEqual:@1] || ![value[@"sounds"] isKindOfClass:[NSMutableArray class]]) {
    if (error) *error = [self error:@"音声一覧が不正です。"];
    return nil;
  }
  return value;
}

- (NSString *)libraryJSON:(NSDictionary *)library error:(NSError **)error {
  NSData *data = [NSJSONSerialization dataWithJSONObject:library options:0 error:error];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (BOOL)writeLibrary:(NSDictionary *)library error:(NSError **)error {
  if (![self ensureDirectory:[[self soundIndex] URLByDeletingLastPathComponent] error:error]) return NO;
  NSData *data = [NSJSONSerialization dataWithJSONObject:library options:0 error:error];
  return data && [data writeToURL:[self soundIndex] options:NSDataWritingAtomic error:error];
}

RCT_EXPORT_METHOD(readDiary:(NSString *)date
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  if (![self validDate:date]) { [self reject:reject error:[self error:@"日付が正しくありません。"]]; return; }
  NSURL *file = [[[self supportURL] URLByAppendingPathComponent:@"diary" isDirectory:YES]
                 URLByAppendingPathComponent:[date stringByAppendingPathExtension:@"txt"]];
  if (![[NSFileManager defaultManager] fileExistsAtPath:file.path]) { resolve(@""); return; }
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:&error];
  if (error) [self reject:reject error:error]; else resolve(content);
}

RCT_EXPORT_METHOD(saveDiary:(NSString *)date
                  content:(NSString *)content
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  if (![self validDate:date]) { [self reject:reject error:[self error:@"日付が正しくありません。"]]; return; }
  NSURL *directory = [[self supportURL] URLByAppendingPathComponent:@"diary" isDirectory:YES];
  NSError *error = nil;
  if (![self ensureDirectory:directory error:&error]) { [self reject:reject error:error]; return; }
  NSURL *file = [directory URLByAppendingPathComponent:[date stringByAppendingPathExtension:@"txt"]];
  if (![content writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    [self reject:reject error:error]; return;
  }
  resolve(@YES);
}

RCT_EXPORT_METHOD(copyText:(NSString *)value
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  [UIPasteboard generalPasteboard].string = value;
  resolve(@YES);
}

RCT_EXPORT_METHOD(randomBytes:(nonnull NSNumber *)count
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  NSInteger length = count.integerValue;
  if (length < 1 || length > 4096) {
    [self reject:reject error:[self error:@"乱数の長さが不正です。"]]; return;
  }
  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
  arc4random_buf(data.mutableBytes, data.length);
  const uint8_t *bytes = data.bytes;
  NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:data.length];
  for (NSUInteger index = 0; index < data.length; index++) [result addObject:@(bytes[index])];
  resolve(result);
}

RCT_EXPORT_METHOD(loadSounds:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  NSError *error = nil;
  NSMutableDictionary *library = [self library:&error];
  if (!library) { [self reject:reject error:error]; return; }
  NSString *json = [self libraryJSON:library error:&error];
  if (json) resolve(json); else [self reject:reject error:error];
}

RCT_EXPORT_METHOD(selectSound:(NSString *_Nullable)identifier
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  NSError *error = nil;
  NSMutableDictionary *library = [self library:&error];
  if (!library) { [self reject:reject error:error]; return; }
  if (identifier) {
    BOOL found = NO;
    for (NSDictionary *sound in library[@"sounds"]) {
      if ([sound[@"id"] isEqual:identifier]) { found = YES; break; }
    }
    if (!found) { [self reject:reject error:[self error:@"音声が見つかりません。"]]; return; }
  }
  [self stopSoundInternal];
  library[@"selectedId"] = identifier ?: [NSNull null];
  if (![self writeLibrary:library error:&error]) { [self reject:reject error:error]; return; }
  resolve([self libraryJSON:library error:&error]);
}

RCT_EXPORT_METHOD(deleteSound:(NSString *)identifier
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  NSError *error = nil;
  NSMutableDictionary *library = [self library:&error];
  if (!library) { [self reject:reject error:error]; return; }
  NSMutableArray *remaining = [NSMutableArray array];
  BOOL found = NO;
  for (NSDictionary *sound in library[@"sounds"]) {
    if ([sound[@"id"] isEqual:identifier]) found = YES; else [remaining addObject:sound];
  }
  if (!found) { [self reject:reject error:[self error:@"音声が見つかりません。"]]; return; }
  NSURL *file = [self soundURL:identifier error:&error];
  if (!file) { [self reject:reject error:error]; return; }
  library[@"sounds"] = remaining;
  if ([library[@"selectedId"] isEqual:identifier]) {
    [self stopSoundInternal];
    library[@"selectedId"] = [NSNull null];
  }
  if (![self writeLibrary:library error:&error]) { [self reject:reject error:error]; return; }
  [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
  resolve([self libraryJSON:library error:&error]);
}

RCT_EXPORT_METHOD(pickSound:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  if (self.pickerResolve) { reject(@"PICKER_BUSY", @"音声の選択中です。", nil); return; }
  UIViewController *presenter = RCTPresentedViewController();
  if (!presenter) { reject(@"NO_ACTIVITY", @"画面を開けませんでした。", nil); return; }
  UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
      initForOpeningContentTypes:@[UTTypeMP3, UTTypeWAV] asCopy:YES];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  self.picker = picker;
  self.pickerResolve = resolve;
  self.pickerReject = reject;
  [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
  RCTPromiseResolveBlock resolve = self.pickerResolve;
  self.pickerResolve = nil;
  self.pickerReject = nil;
  self.picker = nil;
  if (resolve) resolve([NSNull null]);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  RCTPromiseResolveBlock resolve = self.pickerResolve;
  RCTPromiseRejectBlock reject = self.pickerReject;
  self.pickerResolve = nil;
  self.pickerReject = nil;
  self.picker = nil;
  if (!resolve || !reject) return;
  NSError *error = nil;
  NSString *json = urls.firstObject ? [self importSound:urls.firstObject error:&error] : nil;
  if (json) resolve(json); else [self reject:reject error:error ?: [self error:@"音声を開けませんでした。"]];
}

- (NSString *)importSound:(NSURL *)source error:(NSError **)error {
  NSString *name = source.lastPathComponent ?: @"sound";
  NSString *extension = name.pathExtension.lowercaseString;
  if (![@[@"mp3", @"wav"] containsObject:extension]) {
    if (error) *error = [self error:@"MP3 または WAV ファイルを選択してください。"];
    return nil;
  }
  NSString *identifier = [NSUUID UUID].UUIDString.lowercaseString;
  NSURL *file = [self soundURL:identifier error:error];
  if (![self ensureDirectory:[self soundDirectory] error:error]) return nil;

  BOOL scoped = [source startAccessingSecurityScopedResource];
  NSInputStream *input = [NSInputStream inputStreamWithURL:source];
  NSOutputStream *output = [NSOutputStream outputStreamToFileAtPath:file.path append:NO];
  [input open];
  [output open];
  uint8_t buffer[8192];
  NSUInteger total = 0;
  BOOL success = YES;
  while (success) {
    NSInteger count = [input read:buffer maxLength:sizeof(buffer)];
    if (count <= 0) { if (count < 0) success = NO; break; }
    total += (NSUInteger)count;
    if (total > PrelisMaximumSoundBytes) {
      if (error) *error = [self error:@"音声ファイルは 10 MB 以下にしてください。"];
      success = NO;
      break;
    }
    NSInteger offset = 0;
    while (offset < count) {
      NSInteger written = [output write:buffer + offset maxLength:(NSUInteger)(count - offset)];
      if (written <= 0) { success = NO; break; }
      offset += written;
    }
  }
  NSError *streamError = input.streamError ?: output.streamError;
  [input close];
  [output close];
  if (scoped) [source stopAccessingSecurityScopedResource];
  if (!success || total == 0) {
    [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
    if (error && !*error) *error = streamError ?: [self error:total == 0 ? @"空の音声ファイルです。" : @"音声を読み込めませんでした。"];
    return nil;
  }

  NSMutableDictionary *library = [self library:error];
  if (!library) { [[NSFileManager defaultManager] removeItemAtURL:file error:nil]; return nil; }
  [library[@"sounds"] addObject:@{@"id": identifier, @"name": name,
                                  @"mimeType": [extension isEqual:@"mp3"] ? @"audio/mpeg" : @"audio/wav"}];
  [self stopSoundInternal];
  library[@"selectedId"] = identifier;
  if (![self writeLibrary:library error:error]) {
    [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
    return nil;
  }
  return [self libraryJSON:library error:error];
}

RCT_EXPORT_METHOD(playSound:(NSString *)identifier
                  loop:(BOOL)loop
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  NSError *error = nil;
  NSURL *file = [self soundURL:identifier error:&error];
  if (!file) { [self reject:reject error:error]; return; }
  if (![[NSFileManager defaultManager] fileExistsAtPath:file.path]) {
    [self reject:reject error:[self error:@"音声が見つかりません。"]]; return;
  }
  [self stopSoundInternal];
  AVAudioSession *session = [AVAudioSession sharedInstance];
  if (![session setCategory:AVAudioSessionCategoryPlayback
               withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error] ||
      ![session setActive:YES error:&error]) {
    [self reject:reject error:error]; return;
  }
  AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:file error:&error];
  if (!player) { [self reject:reject error:error]; return; }
  player.delegate = self;
  player.numberOfLoops = loop ? -1 : 0;
  if (![player play]) { [self reject:reject error:[self error:@"音声を再生できませんでした。"]]; return; }
  self.player = player;
  resolve(@YES);
}

RCT_EXPORT_METHOD(stopSound:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
  [self stopSoundInternal];
  resolve(@YES);
}

- (void)stopSoundInternal {
  if (!self.player) return;
  [self.player stop];
  self.player.delegate = nil;
  self.player = nil;
  [[AVAudioSession sharedInstance] setActive:NO
                                withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  if (player == self.player) [self stopSoundInternal];
}

- (void)invalidate {
  [self stopSoundInternal];
  if (self.pickerReject) self.pickerReject(@"PICK_CANCELLED", @"音声の選択を終了しました。", nil);
  self.pickerResolve = nil;
  self.pickerReject = nil;
  self.picker = nil;
}

@end
