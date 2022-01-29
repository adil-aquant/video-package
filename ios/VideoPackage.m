#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(VideoPackage, NSObject)

RCT_EXTERN_METHOD(multiply:(float)a withB:(float)b
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(loadCallViewController: (NSString)callId mute:(BOOL)mute serverUrl: (NSString)serverUrl)

@end
