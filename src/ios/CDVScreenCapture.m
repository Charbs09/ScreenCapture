//
//  CDVScreenCapture.m
//  CordovaMobileSpecScreenCapture
//
//  Created by Aaron on 3/19/13.
//
//

#import "CDVScreenCapture.h"
#import <Cordova/CDV.h>

@implementation CDVScreenCapture
@synthesize mFileName, mCaptureCount; //global variables retained between plugin calls

-(void)pluginInitialize {
    //the filename used for saved files
    self.mFileName = @"screenshot";
    //number used to make unique file names for each capture taken with the same fileName
    self.mCaptureCount = 0;
}

//capture function called from Javascript.  Capture only takes a capture of the current screen (with optional sub-rect) and saves the file,
//then returns the location of the saved file in the CDVPluginResult.  Due to the threaded nature of doing capture and file io on different threads
//the callback is executed in the getScreenBits function
- (void)capture:(CDVInvokedUrlCommand*)command
{
    NSObject* captureOptions = [command.arguments objectAtIndex:0];
    
    //get a capture
    [self getScreenBitsWithOptions:captureOptions compareOptions:nil captureCount:self.mCaptureCount++ command:command];
}

//captureAndCompare called from Javascript.  CaptureAndCompare takes a screenshot, saved the image file if asked to, then does a comparison against
//a provided image url and returns the result and the file locations to Javascript in the cordova callback.  
- (void)captureAndCompare:(CDVInvokedUrlCommand*)command
{
    NSObject* captureOptions = [command.arguments objectAtIndex:0];
    NSObject* compareOptions = [command.arguments objectAtIndex:1];
    
    //get a capture
    [self getScreenBitsWithOptions:captureOptions compareOptions:compareOptions captureCount:self.mCaptureCount++ command:command];
    
}

//getScreenBits takes in sizeing and other options for the screen capture, then does a comparison if compareOptions is defined
//the screen capture is done on the ui thread, and the file io and comparison is done on a background thread.  When all the work is done
//it executes the command callback to javascript
- (void) getScreenBitsWithOptions:(NSObject*)captureOptions compareOptions: (NSObject*)compareOptions captureCount : (int) captureCount command : (CDVInvokedUrlCommand*)command
{
    //get the capture parameters
    NSInteger width = [[captureOptions valueForKey:@"width"] intValue];
    NSInteger height = [[captureOptions valueForKey:@"height"]intValue];
    NSInteger x = [[captureOptions valueForKey:@"x"] intValue];
    NSInteger y = [[captureOptions valueForKey:@"y"]intValue];
    NSString* fileName = [captureOptions valueForKey:@"fileName"];
    //async tells us to return immediatly or only after the file io and comparison is complete
    bool async = [[captureOptions valueForKey:@"asynchronous"] boolValue];
    //if the call was to 'capture' then writing the file is automatic, if the call was 'captureAndCompare' writing the actual file is optional
    bool writeActual = (compareOptions != nil) ? [[compareOptions valueForKey:@"writeActualToFile"] boolValue] : true;
    
    //give a default name if none
    if(fileName.length == 0)
        fileName = @"screenshot";
    //determine if we have a new fileName and reset counter if so
    if(![fileName isEqualToString:self.mFileName ])
    {
        self.mFileName = [NSString stringWithString: fileName];
        self.mCaptureCount = 0;
    }
    
    //copy the current view so that we can restore it after moving it around for our capture
    CGRect tmpFrame = self.webView.frame;
    CGRect tmpBounds = self.webView.bounds;
    //get screen width to determine if the desired area is larger than the screen or not
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    //get the document size
    int docWidth = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.width;"] intValue];
    int docHeight = [[self.webView stringByEvaluatingJavaScriptFromString:@"document.height;"] intValue];
    
    //clip x/y to 0 if < 0
    x = (x < 0) ? 0 : x;
    y = (y < 0) ? 0 : y;
    
    //determine if we want a subrect or the full document
    if(width > 0 && height > 0 &&
       width < docWidth && height < docHeight) {
        //if the area is larger than the screen we need to set the webView frame so that it encapsulates the area
        if(width > screenWidth || height > screenHeight) {
            self.webView.frame = CGRectMake(0,0,width,height);
        }
        
        //scroll to the location we need to start from
        //need current scrollY/X to know how much to scroll, use javascript to determine
        int scrollYPosition = [[self.webView stringByEvaluatingJavaScriptFromString:@"window.pageYOffset"] intValue];
        int scrollXPosition = [[self.webView stringByEvaluatingJavaScriptFromString:@"window.pageXOffset"] intValue];
        x = x - scrollXPosition;
        y = y - scrollYPosition;
        //scroll to the location
        self.webView.scrollView.contentOffset = CGPointMake(x,y);
        UIGraphicsBeginImageContext(CGSizeMake(width, height));
    }
    else {
        //Capture the full document, create a temporary bounds the size of the document
        CGRect aFrame = self.webView.bounds;
        aFrame.size.width = self.webView.frame.size.width;
        aFrame.size.height = self.webView.frame.size.height;
        self.webView.frame = aFrame;
        aFrame.size.height = [self.webView sizeThatFits:[[UIScreen mainScreen] bounds].size].height;
        aFrame.size.width = [self.webView sizeThatFits:[[UIScreen mainScreen] bounds].size].width;
        self.webView.frame = aFrame;
        UIGraphicsBeginImageContext([self.webView sizeThatFits:[[UIScreen mainScreen] bounds].size]);
        width = [[UIScreen mainScreen] bounds].size.width;
        height = [[UIScreen mainScreen] bounds].size.height;
    }
    
    //set current view to our new size/location
    CGContextRef resizedContext = UIGraphicsGetCurrentContext();
    [self.webView.layer renderInContext:resizedContext]; // crash
    
    //take the capture
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    //reset our previous view
    self.webView.frame = tmpFrame;
    self.webView.bounds = tmpBounds;
    self.webView.scrollView.contentOffset = CGPointMake(0, 0);
    
    //run the call back immediatly if async is defined, this will allow the JS to run as fast as it can
    if(async) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"capture taken"];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:true]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    
    
    /**** File IO and Compare Code ****/
    //perform the heavy operations on a background thread
    [self.commandDelegate runInBackground:^ {
        //write the image to file
        NSString *actualFileLocation = @"";
        if(writeActual) {
            //construct the diff image file name
            NSString * actualFileName = [NSString stringWithFormat:@"%@_%d",fileName, captureCount];
            actualFileLocation = [self writeImageToFile:image fileName:actualFileName];
        }
        
        /*** COMPARE CODE ***/
        if(compareOptions != nil) {
            NSString * diffFileLocation = @" ";
            int offCount;
            
            //load the compare image
            UIImage *compareImage = [UIImage imageNamed:[compareOptions valueForKey:@"compareURL"]];
            if(compareImage == nil) {
                //couldn't load the compare file, so just return
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error: Could not open compare image"];
                [pluginResult setKeepCallback:[NSNumber numberWithBool:false]];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
            else {
                //check that the images are the same size, if not return an error
                if(width != compareImage.size.width ||
                   height != compareImage.size.height) {
                    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error: Actual and expected images are not the same size"];
                    [pluginResult setKeepCallback:[NSNumber numberWithBool:false]];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
                else {
                    //images are the same size so begin the compare
                    //get the compare options
                    float colorTolerance = [[compareOptions valueForKey:@"colorTolerance"] floatValue];
                    float pixelTolerance = [[compareOptions valueForKey:@"pixelTolerance"] floatValue];
                    bool binaryDiff = [[compareOptions valueForKey:@"binaryDiff"] boolValue];
                    bool writeDiffToFile = [[compareOptions valueForKey:@"writeDiffToFile"] boolValue];
                    
                    //clip tolerances to 0 - 1
                    if(colorTolerance < 0)
                        colorTolerance = 0;
                    else if(colorTolerance > 1)
                        colorTolerance = 1;
                    if(pixelTolerance < 0)
                        pixelTolerance = 0;
                    else if(pixelTolerance > 1)
                        pixelTolerance = 1;
                    
                    //create the correct sized temp buffers
                    int arrayLength = height * width * 4;
                    unsigned char *actualData = malloc(arrayLength);
                    unsigned char *compareData = malloc(arrayLength);
                    unsigned char *diffData;
                    //only allocate the space if we want to write it
                    if(writeDiffToFile)
                        diffData = malloc(arrayLength);
                    else
                        diffData = nil;
                    
                    //get the raw data from the images in teh correct pixel format
                    [self getRawDataFromImage:image rawData : actualData];
                    [self getRawDataFromImage:compareImage rawData : compareData];
                    
                    //do compare
                    offCount = [self compareImagePixels: actualData
                                        comparePixels: compareData
                                       colorTolerance: colorTolerance
                                       pixelTolerance: pixelTolerance
                                           diffPixels: diffData
                                           binaryDiff: binaryDiff
                                          arrayLength: arrayLength];
                    
                    //output diffFile
                    if(offCount > 0 && writeDiffToFile && diffData != nil) {
                        // Create a color space
                        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                        if (colorSpace == NULL) {
                            diffFileLocation = @"Error saving diff image";
                        }
                        else {
                            //setup the diff data to be written in the correct format to disk
                            CGContextRef context = CGBitmapContextCreate (diffData, width, height,
                                                                          8, width * 4, colorSpace,
                                                                          kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast
                                                                          );
                            CGColorSpaceRelease(colorSpace );
                            if (context == NULL)
                            {
                                diffFileLocation = @"Error saving diff image";
                            }
                            else {
                                CGImageRef ref = CGBitmapContextCreateImage(context);
                                CGContextRelease(context);
                                
                                UIImage * diffImage = [UIImage imageWithCGImage:ref];
                                CFRelease(ref);
                                
                                //construct the diff image file name
                                NSString * diffFileName = [NSString stringWithFormat:@"%@_%d_Diff",fileName, captureCount];
                                diffFileLocation = [self writeImageToFile:diffImage fileName:diffFileName];
                            }
                        }
                    }
                    
                    //free buffers we've allocated
                    free(actualData);
                    free(compareData);
                    if(diffData)
                        free(diffData);
                    
                    //prepare an array containing the string we will return
                    NSArray *retArray = [[NSArray alloc] initWithObjects:
                                         [NSString stringWithFormat:@"%d", offCount],
                                         actualFileLocation,
                                         diffFileLocation,
                                         nil];
                    //append the string with a space in between
                    NSString *ret = [retArray componentsJoinedByString:@" "];
                    
                    //return control to the JS thread
                    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:ret];
                    [pluginResult setKeepCallback:[NSNumber numberWithBool:false]];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
            }
        } //end compare code
        
        
        else { //this is a capture call only, just return the image location
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:actualFileLocation];
            [pluginResult setKeepCallback:[NSNumber numberWithBool:false]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
        
    }]; //end background thread work
    
}

- (int) compareImagePixels: (unsigned char *) actualPixels comparePixels: (unsigned char *) comparePixels colorTolerance : (float) colorTolerance pixelTolerance :(float) pixelTolerance diffPixels : (unsigned char *) diffPixels binaryDiff : (bool) binaryDiff arrayLength : (int) arrayLength
{
    bool createDiff = (diffPixels == nil) ? false : true;
    int wholeColorDifference = (255 * colorTolerance)+0.5;
    int aDiff,rDiff,gDiff,bDiff;
    int offCount = 0;
    
    for(int i=0; i < arrayLength; i+=4) {
        //generate the difference
        @try {
            rDiff = abs(actualPixels[i] - comparePixels[i]);
            gDiff = abs(actualPixels[i+1] - comparePixels[i+1]);
            bDiff = abs(actualPixels[i+2] - comparePixels[i+2]);
            aDiff = abs(actualPixels[i+3] - comparePixels[i+3]);
        }
        @catch(NSException * e) {
            
        }
        
        if(aDiff > wholeColorDifference ||
           rDiff > wholeColorDifference ||
           gDiff > wholeColorDifference ||
           bDiff > wholeColorDifference ) {
            offCount++;
            if(createDiff) {
                if(binaryDiff) {
                    diffPixels[i] = 255;
                    diffPixels[i+1] = 255;
                    diffPixels[i+2] = 255;
                    diffPixels[i+3] = 255;
                }
                else {
                    diffPixels[i] = rDiff;
                    diffPixels[i+1] = gDiff;
                    diffPixels[i+2] = bDiff;
                    diffPixels[i+3] = 255;
                }
            }
        }
        else if(createDiff) {
            diffPixels[i] = 0;
            diffPixels[i+1] = 0;
            diffPixels[i+2] = 0;
            diffPixels[i+3] = 255;
        }
    }
    if( ((float)offCount / (arrayLength/4)) <= pixelTolerance) {
        offCount = 0;
    }
    return offCount;
}
//getRawDataFromImage copies the pixel bytes from the UIImage into an unsigned char** in the correct RGBA format
- (void) getRawDataFromImage:(UIImage *) image rawData : (unsigned char *)rawData
{
    CGImageRef imageRef = [image CGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
}
//writeImageToFile writes the given UIImage to the caches directory of the application bundle.  It is possible to specify a subdirectory
//in the provided fileName parameter such as "Screenshots/capture".  writeImageToFile will create the Screenshots directory if it does not already exist
- (NSString *) writeImageToFile: (UIImage*) image fileName : (NSString* ) fileName
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString * actualFileLocation = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png",fileName]];
   
    //this code will account for \ in the path, diabled for now because it's a requirement to have the fileName use / in the JS
   /* NSString * correctedPath = [path stringByReplacingOccurrencesOfString:@"\r" withString:@"/r"];
    correctedPath = [path stringByReplacingOccurrencesOfString:@"\n" withString:@"/n"];
    correctedPath = [correctedPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];*/
    
    NSString * justPath = [actualFileLocation stringByDeletingLastPathComponent];
    
    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:justPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error != nil) {
        NSLog(@"error creating directory: %@", error);
        actualFileLocation = @"error creating directory";
    }
    else {
        [UIImagePNGRepresentation(image) writeToFile:actualFileLocation options:NSDataWritingAtomic error:&error];
    }
    return actualFileLocation;
    
}
//error callback for saving a file
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error != NULL) {
         NSLog(@"error saving picture image");
    }
}

@end
