//
//  CDVScreenCapture.h
//  CordovaMobileSpecScreenCapture
//
//  Created by Aaron on 3/19/13.
//
//

#ifndef CordovaMobileSpecScreenCapture_CDVScreenCapture_h
#define CordovaMobileSpecScreenCapture_CDVScreenCapture_h
#import <Cordova/CDV.h>
@interface CDVScreenCapture : CDVPlugin
@property (nonatomic, retain) NSString * mFileName;
@property (nonatomic, assign) int mCaptureCount;
- (void)capture:(CDVInvokedUrlCommand*)command;
- (void)captureAndCompare:(CDVInvokedUrlCommand*)command;
- (void) getScreenBitsWithOptions:(NSObject*)captureOptions compareOptions: (NSObject*)compareOptions captureCount : (int) captureCount command : (CDVInvokedUrlCommand*)command;
- (void)getRawDataFromImage:(UIImage *) image rawData : (unsigned char *)rawData;
- (NSString *) writeImageToFile: (UIImage*) image fileName : (NSString* ) fileName;
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
@end


#endif
