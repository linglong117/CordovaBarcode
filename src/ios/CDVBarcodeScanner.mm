/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AudioToolbox/AudioToolbox.h>

//------------------------------------------------------------------------------
// use the all-in-one version of zxing that we built
//------------------------------------------------------------------------------
#import "zxing-all-in-one.h"

#import <Cordova/CDVPlugin.h>


//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        isFlipped;


- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController alterateOverlayXib:(NSString *)alternateXib;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format;
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer;
- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr;
- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource;
- (void)dumpImage:(UIImage*)image;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UIView* overlayView;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;

//=======add code by xyl==========================
@property (nonatomic, strong) UIView *line;
@property (assign) Boolean isBottom;
@property (nonatomic, strong) NSTimer  *lineTimer;
@property (assign) Boolean upOrdown;
@property (assign) NSInteger num;
@property (assign) CGRect reticleRect;
@property (assign) CGFloat lineHeight;
//=======add code by xyl==========================


- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImage;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;

@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner

AVAudioPlayer *player;

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;
    
    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }
    
    return result;
}


- (void)requestCameraPermissionWithSuccess:(void (^)(BOOL success))successBlock {
    if (![self cameraIsPresent]) {
        successBlock(NO);
        return;
    }
    
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusAuthorized:
            successBlock(YES);
            break;
            
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            successBlock(NO);
            break;
            
        case AVAuthorizationStatusNotDetermined:
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                     completionHandler:^(BOOL granted) {
                                         
                                         dispatch_async(dispatch_get_main_queue(), ^{
                                             successBlock(granted);
                                         });
                                         
                                     }];
            break;
    }
}

- (BOOL)scanningIsProhibited {
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            return YES;
            break;
            
        default:
            return NO;
            break;
    }
}

- (BOOL)cameraIsPresent {
    return [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
}
- (void)displayPermissionMissingAlert {
    NSString *message = nil;
    if ([self scanningIsProhibited]) {
        message = @"请在“设置－隐私－相机”选项中，允许程序访问您的相机";
    } else if (![self cameraIsPresent]) {
        message = @"没有相机";
    } else {
        message = @"发生一个未知错误";
    }
    
    [[[UIAlertView alloc] initWithTitle:@""
                                message:message
                               delegate:nil
                      cancelButtonTitle:@"确认"
                      otherButtonTitles:nil] show];
}


//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {

    NSString*       callback;
    //NSString*       capabilityError;
    
    callback = command.callbackId;
    
    NSLog(@"command  >>  %@ ",command);
    
    
    [self requestCameraPermissionWithSuccess:^(BOOL success) {
        if (success) {
           
//            RootViewController * rt = [[RootViewController alloc]initWithPlugin:self callback:callback];
//            [self.viewController presentViewController:rt animated:YES completion:^{
            
//            }];
            
             NSString*       capabilityError;
            CDVbcsProcessor* processor;
            
            // We allow the user to define an alternate xib file for loading the overlay.
            NSString *overlayXib = nil;
            if ( [command.arguments count] >= 1 )
            {
                overlayXib = [command.arguments objectAtIndex:0];
            }
            
            capabilityError = [self isScanNotPossible];
            if (capabilityError) {
                [self returnError:capabilityError callback:callback];
                return;
            }
            
            processor = [[CDVbcsProcessor alloc]
                         initWithPlugin:self
                         callback:callback
                         parentViewController:self.viewController
                         alterateOverlayXib:overlayXib
                         ];
            [processor retain];
            //[processor retain];
            //    [processor retain];
            // queue [processor scanBarcode] to run on the event loop
            [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
            
            
        } else {
            [self displayPermissionMissingAlert];
        }
    }];
    
    
    
//    // We allow the user to define an alternate xib file for loading the overlay.
//    NSString *overlayXib = nil;
//    if ( [command.arguments count] >= 1 )
//    {
//        overlayXib = [command.arguments objectAtIndex:0];
//    }
//    
//    capabilityError = [self isScanNotPossible];
//    if (capabilityError) {
//        [self returnError:capabilityError callback:callback];
//        return;
//    }
//    
//    processor = [[CDVbcsProcessor alloc]
//                 initWithPlugin:self
//                 callback:callback
//                 parentViewController:self.viewController
//                 alterateOverlayXib:overlayXib
//                 ];
//    [processor retain];
//    //[processor retain];
//    //    [processor retain];
//    // queue [processor scanBarcode] to run on the event loop
//    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    [self returnError:@"encode function not supported" callback:command.callbackId];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback{
    NSNumber* cancelledNumber = [NSNumber numberWithInt:(cancelled?1:0)];
    
    NSMutableDictionary* resultDict = [[[NSMutableDictionary alloc] init] autorelease];
    [resultDict setObject:scannedText     forKey:@"text"];
    [resultDict setObject:format          forKey:@"format"];
    [resultDict setObject:cancelledNumber forKey:@"cancelled"];
    
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary: resultDict
                               ];
    
    NSString* js = [result toSuccessCallbackString:callback];
    if (!flipped) {
        [self writeJavascript:js];
    }
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsString: message
                               ];
    
    NSString* js = [result toErrorCallbackString:callback];
    
    [self writeJavascript:js];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;


//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController
  alterateOverlayXib:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;
    
    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;
    self.alternateXib         = alternateXib;
    
    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    
    self.capturing = NO;
    
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)scanBarcode {
    
    //    self.captureSession = nil;
    //    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }
    
    self.viewController = [[[CDVbcsViewController alloc] initWithProcessor: self alternateOverlay:self.alternateXib] autorelease];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;
    
    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:0];
}

//by  xyl  modify
//--------------------------------------------------------------------------
- (void)openDialog {
    
    //[self.parentViewController presentModalViewController:self.viewController animated:YES];
    [self.parentViewController presentViewController:self.viewController animated:YES completion:nil];
}

//by  xyl  modify
//--------------------------------------------------------------------------
- (void)barcodeScanDone {
    
    //    AVAudioPlayer *player;
    //
    //    NSBundle *mainBundle = [NSBundle mainBundle];
    //    NSURL *soundUrl = [NSURL fileURLWithPath:[mainBundle pathForResource:@"beep-beep" ofType:@"aiff"] isDirectory:NO];
    //    player=[[AVAudioPlayer alloc] initWithContentsOfURL:soundUrl error:nil];
    //    [player prepareToPlay];
    //    //[player play];
    //    [soundUrl release];
    //    //AudioServicesPlaySystemSound(SystemSoundID);
    
    
    self.capturing = NO;
    [self.captureSession stopRunning];
    //[self.parentViewController dismissModalViewControllerAnimated: YES];
    [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
    
    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
    
    // delayed [self release];
    [self performSelector:@selector(release) withObject:nil afterDelay:1];
}

static SystemSoundID beep_id = 0;

-(void) playSound

{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"beep-beep" ofType:@"caf"];
    if (path) {
        //注册声音到系统
        AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath:path],&beep_id);
        AudioServicesPlaySystemSound(beep_id);
        //        AudioServicesPlaySystemSound(shake_sound_male_id);//如果无法再下面播放，可以尝试在此播放
    }
    AudioServicesPlaySystemSound(beep_id);   //播放注册的声音，（此句代码，可以在本类中的任意位置调用，不限于本方法中）
    //    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);   //让手机震动
}

- (void)initSound
{
    NSString *soundPath=[[NSBundle mainBundle] pathForResource:@"beep-beep" ofType:@"caf"];
    NSURL *soundUrl=[[NSURL alloc] initFileURLWithPath:soundPath];
    player=[[AVAudioPlayer alloc] initWithContentsOfURL:soundUrl error:nil];
    [player prepareToPlay];
    [soundUrl release];
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    
    
    [self initSound];
    [player play];
    
    
    [self barcodeScanDone];
    [self.plugin returnSuccess:text format:format cancelled:FALSE flipped:FALSE callback:self.callback];
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    [self barcodeScanDone];
    [self.plugin returnError:message callback:self.callback];
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone];
    [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE flipped:self.isFlipped callback:self.callback];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}


- (void)flipCamera
{
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
    [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;
    
    AVCaptureSession* captureSession = [[[AVCaptureSession alloc] init] autorelease];
    self.captureSession = captureSession;
    
    AVCaptureDevice* __block device = nil;
    if (self.isFrontCamera) {
        
        NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        [devices enumerateObjectsUsingBlock:^(AVCaptureDevice *obj, NSUInteger idx, BOOL *stop) {
            if (obj.position == AVCaptureDevicePositionFront) {
                device = obj;
            }
        }];
    } else {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device) return @"unable to obtain video capture device";
        
    }
    
    
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";
    
    AVCaptureVideoDataOutput* output = [[[AVCaptureVideoDataOutput alloc] init] autorelease];
    if (!output) return @"unable to obtain video capture output";
    
    NSDictionary* videoOutputSettings = [NSDictionary
                                         dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey
                                         ];
    
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = videoOutputSettings;
    
    [output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    if (![captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        return @"unable to preset medium quality video capture";
    }
    
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    
    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }
    
    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }
    
    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];
    
    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection {
    
    if (!self.capturing) return;
    
#if USE_SHUTTER
    if (!self.viewController.shutterPressed) return;
    self.viewController.shutterPressed = NO;
    
    UIView* flashView = [[[UIView alloc] initWithFrame:self.viewController.view.frame] autorelease];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [self.viewController.view.window addSubview:flashView];
    
    [UIView
     animateWithDuration:.4f
     animations:^{
         [flashView setAlpha:0.f];
     }
     completion:^(BOOL finished){
         [flashView removeFromSuperview];
     }
     ];
    
    //         [self dumpImage: [[self getImageFromSample:sampleBuffer] autorelease]];
#endif
    
    
    using namespace zxing;
    
    // LuminanceSource is pretty dumb; we have to give it a pointer to
    // a byte array, but then can't get it back out again.  We need to
    // get it back to free it.  Saving it in imageBytes.
    uint8_t* imageBytes;
    
    //        NSTimeInterval timeStart = [NSDate timeIntervalSinceReferenceDate];
    
    try {
        DecodeHints decodeHints;
        decodeHints.addFormat(BarcodeFormat_QR_CODE);
        decodeHints.addFormat(BarcodeFormat_DATA_MATRIX);
        decodeHints.addFormat(BarcodeFormat_UPC_E);
        decodeHints.addFormat(BarcodeFormat_UPC_A);
        decodeHints.addFormat(BarcodeFormat_EAN_8);
        decodeHints.addFormat(BarcodeFormat_EAN_13);
        decodeHints.addFormat(BarcodeFormat_CODE_128);
        decodeHints.addFormat(BarcodeFormat_CODE_39);
        decodeHints.addFormat(BarcodeFormat_ITF);
        
        // here's the meat of the decode process
        Ref<LuminanceSource>   luminanceSource   ([self getLuminanceSourceFromSample: sampleBuffer imageBytes:&imageBytes]);
        //            [self dumpImage: [[self getImageFromLuminanceSource:luminanceSource] autorelease]];
        Ref<Binarizer>         binarizer         (new HybridBinarizer(luminanceSource));
        Ref<BinaryBitmap>      bitmap            (new BinaryBitmap(binarizer));
        Ref<MultiFormatReader> reader            (new MultiFormatReader());
        Ref<Result>            result            (reader->decode(bitmap, decodeHints));
        Ref<String>            resultText        (result->getText());
        BarcodeFormat          formatVal =       result->getBarcodeFormat();
        NSString*              format    =       [self formatStringFrom:formatVal];
        
        
        const char* cString      = resultText->getText().c_str();
        NSString*   resultString = [[[NSString alloc] initWithCString:cString encoding:NSUTF8StringEncoding] autorelease];
        
        [self barcodeScanSucceeded:resultString format:format];
        
    }
    catch (zxing::ReaderException &rex) {
        //            NSString *message = [[[NSString alloc] initWithCString:rex.what() encoding:NSUTF8StringEncoding] autorelease];
        //            NSLog(@"decoding: ReaderException: %@", message);
    }
    catch (zxing::IllegalArgumentException &iex) {
        //            NSString *message = [[[NSString alloc] initWithCString:iex.what() encoding:NSUTF8StringEncoding] autorelease];
        //            NSLog(@"decoding: IllegalArgumentException: %@", message);
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }
    
    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));
    
    // free the buffer behind the LuminanceSource
    if (imageBytes) {
        free(imageBytes);
    }
}

//--------------------------------------------------------------------------
// convert barcode format to string
//--------------------------------------------------------------------------
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format {
    if (format == zxing::BarcodeFormat_QR_CODE)      return @"QR_CODE";
    if (format == zxing::BarcodeFormat_DATA_MATRIX)  return @"DATA_MATRIX";
    if (format == zxing::BarcodeFormat_UPC_E)        return @"UPC_E";
    if (format == zxing::BarcodeFormat_UPC_A)        return @"UPC_A";
    if (format == zxing::BarcodeFormat_EAN_8)        return @"EAN_8";
    if (format == zxing::BarcodeFormat_EAN_13)       return @"EAN_13";
    if (format == zxing::BarcodeFormat_CODE_128)     return @"CODE_128";
    if (format == zxing::BarcodeFormat_CODE_39)      return @"CODE_39";
    if (format == zxing::BarcodeFormat_ITF)          return @"ITF";
    return @"???";
}

//--------------------------------------------------------------------------
// convert capture's sample buffer (scanned picture) into the thing that
// zxing needs.
//--------------------------------------------------------------------------
- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t   bytesPerRow =            CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t   width       =            CVPixelBufferGetWidth(imageBuffer);
    size_t   height      =            CVPixelBufferGetHeight(imageBuffer);
    uint8_t* baseAddress = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    
    // only going to get 90% of the min(width,height) of the captured image
    size_t    greyWidth  = 9 * MIN(width, height) / 10;
    uint8_t*  greyData   = (uint8_t*) malloc(greyWidth * greyWidth);
    
    // remember this pointer so we can free it later
    *ptr = greyData;
    
    if (!greyData) {
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
        throw new zxing::ReaderException("out of memory");
    }
    
    size_t offsetX = (width  - greyWidth) / 2;
    size_t offsetY = (height - greyWidth) / 2;
    
    // pixel-by-pixel ...
    for (size_t i=0; i<greyWidth; i++) {
        for (size_t j=0; j<greyWidth; j++) {
            // i,j are the coordinates from the sample buffer
            // ni, nj are the coordinates in the LuminanceSource
            // in this case, there's a rotation taking place
            size_t ni = greyWidth-j;
            size_t nj = i;
            
            size_t baseOffset = (j+offsetY)*bytesPerRow + (i + offsetX)*4;
            
            // convert from color to grayscale
            // http://en.wikipedia.org/wiki/Grayscale#Converting_color_to_grayscale
            size_t value = 0.11 * baseAddress[baseOffset] +
            0.59 * baseAddress[baseOffset + 1] +
            0.30 * baseAddress[baseOffset + 2];
            
            greyData[nj*greyWidth + ni] = value;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    using namespace zxing;
    
    Ref<LuminanceSource> luminanceSource (
                                          new GreyscaleLuminanceSource(greyData, greyWidth, greyWidth, 0, 0, greyWidth, greyWidth)
                                          );
    
    return luminanceSource;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource  {
    unsigned char* bytes = luminanceSource->getMatrix();
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(
                                                 bytes,
                                                 luminanceSource->getWidth(), luminanceSource->getHeight(), 8, luminanceSource->getWidth(),
                                                 colorSpace,
                                                 kCGImageAlphaNone
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    free(bytes);
    
    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width       = CVPixelBufferGetWidth(imageBuffer);
    size_t height      = CVPixelBufferGetHeight(imageBuffer);
    
    uint8_t* baseAddress    = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    int      length         = height * bytesPerRow;
    uint8_t* newBaseAddress = (uint8_t*) malloc(length);
    memcpy(newBaseAddress, baseAddress, length);
    baseAddress = newBaseAddress;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
                                                 baseAddress,
                                                 width, height, 8, bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    
    free(baseAddress);
    
    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (void)dumpImage:(UIImage*)image {
    NSLog(@"writing image to library: %dx%d", (int)image.size.width, (int)image.size.height);
    ALAssetsLibrary* assetsLibrary = [[[ALAssetsLibrary alloc] init] autorelease];
    [assetsLibrary
     writeImageToSavedPhotosAlbum:image.CGImage
     orientation:ALAssetOrientationUp
     completionBlock:^(NSURL* assetURL, NSError* error){
         if (error) NSLog(@"   error writing image to library");
         else       NSLog(@"   wrote image to library %@", assetURL);
     }
     ];
}

@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;

//=======add code by xyl==========================
@synthesize line=_line;
@synthesize isBottom;
@synthesize lineTimer;
@synthesize upOrdown;
@synthesize num;
@synthesize reticleRect;
@synthesize lineHeight;
//=======add code by xyl==========================


//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;
    
    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
    //    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame] autorelease];
    
    // setup capture preview layer
    
    //AVCaptureConnection's -setVideoOrientation:
    //AVCaptureConnection
    
    
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    if ([previewLayer respondsToSelector:@selector(connection)])
    {
        if ([previewLayer.connection isVideoOrientationSupported])
        {
            [previewLayer.connection setVideoOrientation:self.interfaceOrientation];
        }
    }
    else
    {
        // Deprecated in 6.0; here for backward compatibility
        if ([previewLayer isOrientationSupported])
        {
            [previewLayer setOrientation:AVCaptureVideoOrientationPortrait];
        }
    }
    //    if ([previewLayer isOrientationSupported]) {
    //        [previewLayer setOrientation:AVCaptureVideoOrientationPortrait];
    //    }
    
    num=0;
    lineHeight=0;
    reticleRect = CGRectMake(0, 0, 0, 0);
    
    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];
    [self.view addSubview:[self buildOverlayView]];
    
    //[self setBorderline];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {
    
    // set video orientation to what the camera sees
    self.processor.previewLayer.orientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    self.processor.previewLayer.frame = self.view.bounds;
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    [self startCapturing];
    
    [super viewDidAppear:animated];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (void)shutterButtonPressed {
    self.shutterPressed = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
    
    [lineTimer invalidate];
}

- (void)flipCameraButtonPressed:(id)sender
{
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView *)buildOverlayViewFromXib
{
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];
    
    if ( self.overlayView == nil )
    {
        NSLog(@"%@", @"An error occurred loading the overlay xib.  It appears that the overlayView outlet is not set.");
        return nil;
    }
    
    return self.overlayView;
}

//by  xyl  modify  2014-08-09 16:23:30
//--------------------------------------------------------------------------
#define kDefaultFont [UIFont fontWithName:@"Helvetica" size:13]

#if __has_feature(objc_arc)
#define MB_AUTORELEASE(exp) exp
#define MB_RELEASE(exp) exp
#define MB_RETAIN(exp) exp
#else
#define MB_AUTORELEASE(exp) [exp autorelease]
#define MB_RELEASE(exp) [exp release]
#define MB_RETAIN(exp) [exp retain]
#endif

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
#define MBLabelAlignmentCenter NSTextAlignmentCenter
#define MBLabelAlignmentLeft   NSTextAlignmentLeft
#define MBLabelAlignmentRight   NSTextAlignmentRight
#else
#define MBLabelAlignmentCenter UITextAlignmentCenter
#define MBLabelAlignmentLeft UITextAlignmentLeft
#define MBLabelAlignmentRight   UITextAlignmentRight

#endif

//by xyl 2013-11-27 16:04:09
#if __IPHONE_6_0 >=60000
# define LINE_BREAK_WORD_WRAP NSLineBreakByWordWrapping
#else
# define LINE_BREAK_WORD_WRAP UILineBreakModeWordWrap
#endif

#if __IPHONE_6_0 >=60000
# define LINE_BREAK_BY_TAIL NSLineBreakByTruncatingTail
#else
# define LINE_BREAK_BY_TAIL UILineBreakModeTailTruncation
#endif


#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
#define MB_TEXTSIZE(text, font) [text length] > 0 ? [text \
sizeWithAttributes:@{NSFontAttributeName:font}] : CGSizeZero;
#else
#define MB_TEXTSIZE(text, font) [text length] > 0 ? [text sizeWithFont:font] : CGSizeZero;
#endif

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
#define MB_MULTILINE_TEXTSIZE(text, font, maxSize, mode) [text length] > 0 ? [text \
boundingRectWithSize:maxSize options:(NSStringDrawingUsesLineFragmentOrigin) \
attributes:@{NSFontAttributeName:font} context:nil].size : CGSizeZero;
#else
#define MB_MULTILINE_TEXTSIZE(text, font, maxSize, mode) [text length] > 0 ? [text \
sizeWithFont:font constrainedToSize:maxSize lineBreakMode:mode] : CGSizeZero;
#endif




#define RETICLE_SIZE    500.0f
#define RETICLE_WIDTH    1.0f
#define RETICLE_WIDTH_REDLINE    2.0f
#define RETICLE_OFFSET   60.0f
#define RETICLE_ALPHA     0.5f
#define kLine_Width 4.0f
#define kLine_Length 80.0f

#define kReticleX  37*2
//#define kReticle
#define kQRWidth 15
#define kORHeight 15


//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {
    
    if ( nil != self.alternateXib )
    {
        return [self buildOverlayViewFromXib];
    }
    CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    
    UIView* overlayView = [[[UIView alloc] initWithFrame:bounds] autorelease];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;
    
    UIToolbar* toolbar = [[[UIToolbar alloc] init] autorelease];
    toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    
    id cancelButton = [[[UIBarButtonItem alloc] autorelease]
                       initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                       target:(id)self
                       action:@selector(cancelButtonPressed:)
                       ];
    
    //    id cancelButton = [[[UIBarButtonItem alloc] autorelease]
    //                       initWithTitle:@"取消" style:UIBarButtonItemStylePlain
    //                       target:(id)self
    //                       action:@selector(cancelButtonPressed:)
    //                       ];
    
    
    id flexSpace = [[[UIBarButtonItem alloc] autorelease]
                    initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                    target:nil
                    action:nil
                    ];
    
    //    id flipCamera = [[[UIBarButtonItem alloc] autorelease]
    //                       initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
    //                       target:(id)self
    //                       action:@selector(flipCameraButtonPressed:)
    //                       ];
    
    
#if USE_SHUTTER
    id shutterButton = [[UIBarButtonItem alloc]
                        initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                        target:(id)self
                        action:@selector(shutterButtonPressed)
                        ];
    
    //toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace, flipCamera ,shutterButton,nil];
    toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace ,shutterButton,nil];
    
#else
    //toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace, flipCamera,nil];
    toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace,nil];
    
#endif
    bounds = overlayView.bounds;
    
    [toolbar sizeToFit];
    CGFloat toolbarHeight  = [toolbar frame].size.height;
    CGFloat rootViewHeight = CGRectGetHeight(bounds);
    CGFloat rootViewWidth  = CGRectGetWidth(bounds);
    CGRect  rectArea       = CGRectMake(0, rootViewHeight - toolbarHeight, rootViewWidth, toolbarHeight);
    [toolbar setFrame:rectArea];
    
    [overlayView addSubview: toolbar];
    
    UIImage* reticleImage = [self buildReticleImage];
    
    UIView* reticleView = [[[UIImageView alloc] initWithImage: reticleImage] autorelease];
    CGFloat minAxis = MIN(rootViewHeight, rootViewWidth);
    
    //CGRect rect1 = reticleView.frame;
    
    rectArea = CGRectMake(
                          0.5 * (rootViewWidth  - minAxis),
                          0.5 * (rootViewHeight - minAxis),
                          minAxis,
                          minAxis
                          );
    [reticleView setFrame:rectArea];
    
    reticleView.opaque           = NO;
    reticleView.contentMode      = UIViewContentModeScaleAspectFit;
    reticleView.autoresizingMask = 0
    | UIViewAutoresizingFlexibleLeftMargin
    | UIViewAutoresizingFlexibleRightMargin
    | UIViewAutoresizingFlexibleTopMargin
    | UIViewAutoresizingFlexibleBottomMargin;
    
    //reticleView.backgroundColor = [UIColor purpleColor];
    reticleRect = reticleView.frame;
    
    NSLog(@"x: %f, Y: %f,width : %f, height: %f",reticleRect.origin.x,reticleRect.origin.y,reticleRect.size.width,reticleRect.size.height);
    //CGRect rect2 = overlayView.frame;
    //扫描线
    //CGFloat lineOffset = RETICLE_OFFSET+(0.5*RETICLE_WIDTH);
    //self.line = [[UIView alloc] initWithFrame:CGRectMake(38.5, 38.5, 320-38.5*2, 3)];
    //self.line = [[UIView alloc] initWithFrame:CGRectMake(92.16, 92.16, 768-92.16*2, 3)];
    
    //CGFloat linex = fabsf(minAxis - rect1.size.width) ;
    CGFloat linex = minAxis*RETICLE_OFFSET/RETICLE_SIZE;
    
    CGFloat reticleWidth = minAxis*(RETICLE_SIZE-2*RETICLE_OFFSET)/RETICLE_SIZE;
    
    //    double rowNum = 20/(double)3;
    //    NSString *str = [self roundUp:linex afterPoint:2];
    
    
    //四个角
    UIImageView * imageqr1 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr1"]];
    imageqr1.frame = CGRectMake(linex, linex, kQRWidth, kORHeight);
    [reticleView addSubview:imageqr1];
    
    UIImageView * imageqr3 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr3"]];
    imageqr3.frame = CGRectMake(linex, reticleWidth+linex-kQRWidth, kQRWidth, kORHeight);
    //imageqr3.backgroundColor = [UIColor orangeColor];
    [reticleView addSubview:imageqr3];
    
    
    UIImageView * imageqr2 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr2"]];
    imageqr2.frame = CGRectMake(reticleWidth+linex-kQRWidth, linex, kQRWidth, kORHeight);
    [reticleView addSubview:imageqr2];
    
    UIImageView * imageqr4 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr4"]];
    imageqr4.frame = CGRectMake(reticleWidth+linex-kQRWidth, reticleWidth+linex-kQRWidth, kQRWidth, kORHeight);
    [reticleView addSubview:imageqr4];
    
    
    
    
    self.line = [[UIView alloc] initWithFrame:CGRectMake(linex, linex, minAxis-linex*2, RETICLE_WIDTH_REDLINE)];
    //self.line.backgroundColor = [UIColor greenColor];
    UIImageView *ivline = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, minAxis-linex*2, RETICLE_WIDTH_REDLINE)];
    //ivline.image = [UIImage imageNamed:@"qrcode_scan_line"];
    ivline.image = [UIImage imageNamed:@"line"];
    [self.line addSubview:ivline];
    
    //定时器，设定时间过1.5秒，
    // timer = [NSTimer scheduledTimerWithTimeInterval:.02 target:self selector:@selector(animation1) userInfo:nil repeats:YES];
    [reticleView addSubview:self.line];
    lineHeight = minAxis-linex*2; //激光线移动的距离
    lineTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(moveLine) userInfo:nil repeats:YES];
    [lineTimer fire];
    
    //[self scanline1:reticleView];
    [overlayView addSubview: reticleView];
    //    reticleView.alpha = 1;
    //    overlayView.backgroundColor = [UIColor lightGrayColor];
    //    overlayView.alpha = 0.6;
    
    
    UILabel * labIntroudction= [[UILabel alloc] initWithFrame:CGRectMake(linex, 60, rootViewWidth-linex*2, 60)];
    labIntroudction.backgroundColor = [UIColor clearColor];
    labIntroudction.numberOfLines=0;
    labIntroudction.textColor=[UIColor whiteColor];
    labIntroudction.font = kDefaultFont;
    //文字居中显示
    labIntroudction.textAlignment = MBLabelAlignmentCenter;
    //自动折行设置
    labIntroudction.lineBreakMode = LINE_BREAK_WORD_WRAP;
    labIntroudction.text=@"请将二维码图像置于矩形方框内，离手机摄像头10CM左右，系统会自动识别。";
    [self.view addSubview:labIntroudction];
    
    return overlayView;
}


//number:需要处理的数字， position：保留小数点第几位，
-(NSString *)roundUp:(float)number afterPoint:(int)position{
    NSDecimalNumberHandler* roundingBehavior = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundUp scale:position raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO];
    NSDecimalNumber *ouncesDecimal;
    NSDecimalNumber *roundedOunces;
    ouncesDecimal = [[NSDecimalNumber alloc] initWithFloat:number];
    roundedOunces = [ouncesDecimal decimalNumberByRoundingAccordingToBehavior:roundingBehavior];
    [ouncesDecimal release];
    return [NSString stringWithFormat:@"%@",roundedOunces];
}


//by  xyl  modify  2014-08-09 16:23:30
//--------------------------------------------------------------------------

//#define RETICLE_SIZE    500.0f
//#define RETICLE_WIDTH    5.0f
//#define RETICLE_WIDTH_REDLINE    3.0f
//#define RETICLE_OFFSET   60.0f
//#define RETICLE_ALPHA     0.5f
//-------------------------------------------------------------------------
// builds the green box and red line
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage {
    
    UIImage* result;
    UIGraphicsBeginImageContext(CGSizeMake(RETICLE_SIZE, RETICLE_SIZE));
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if (self.processor.is1D) {
        
        UIColor* color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH_REDLINE);
        CGContextBeginPath(context);
        CGFloat lineOffset = RETICLE_OFFSET+(0.5*RETICLE_WIDTH);
        float lengths[] = {10,5};
        //CGContextSetLineDash(context, 0, lengths, 2);  //画虚线
        CGContextMoveToPoint(context, lineOffset, RETICLE_SIZE/2);
        CGContextAddLineToPoint(context, RETICLE_SIZE-lineOffset, 0.5*RETICLE_SIZE);
        //CGContextStrokePath(context);
        //[self DrawLineInImageView];
        UIImageView * image = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pick_bg.png"]];
        image.frame = CGRectMake(20, 80, 280, 280);
        //[self.view addSubview:image];
        
    }
    
    if (self.processor.is2D) {
        
        UIColor* color = [UIColor colorWithRed:255.0 green:255.0 blue:255.0 alpha:RETICLE_ALPHA];
        
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextStrokeRect(context,
                            CGRectMake(
                                       RETICLE_OFFSET,
                                       RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET
                                       )
                            );
        
        
        /*
         //绘画四角的直角效果
         //左上角 横线
         UIColor* linecolor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:0.8];
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         //CGFloat lineOffset1 = RETICLE_OFFSET+(kLine_Width-RETICLE_WIDTH)/2;
         CGFloat lineOffset1 = RETICLE_OFFSET+(kLine_Width-RETICLE_WIDTH)/2;
         CGContextMoveToPoint(context, RETICLE_OFFSET, lineOffset1);
         CGContextAddLineToPoint(context, kLine_Length, lineOffset1);
         CGContextStrokePath(context);
         //左上角 竖线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         //CGContextMoveToPoint(context, lineOffset1, RETICLE_OFFSET+kLine_Width-RETICLE_WIDTH);
         CGContextMoveToPoint(context, lineOffset1, RETICLE_OFFSET);
         CGContextAddLineToPoint(context, lineOffset1, kLine_Length);
         CGContextStrokePath(context);
         
         
         CGFloat lineOffset2 = RETICLE_OFFSET+(RETICLE_SIZE-2*RETICLE_OFFSET)-(kLine_Width-RETICLE_WIDTH)/2;
         CGFloat lineOffset3 = RETICLE_OFFSET+(RETICLE_SIZE-2*RETICLE_OFFSET)+(kLine_Width-RETICLE_WIDTH)/2;
         
         //左下角 横线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         CGContextMoveToPoint(context, RETICLE_OFFSET, lineOffset2);
         CGContextAddLineToPoint(context, kLine_Length, lineOffset2);
         CGContextStrokePath(context);
         //左下角 竖线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         CGContextMoveToPoint(context, lineOffset1, lineOffset3-kLine_Width/2);
         CGContextAddLineToPoint(context, lineOffset1, lineOffset3-20);
         CGContextStrokePath(context);
         
         
         //CGFloat lineOffset4 = RETICLE_OFFSET+(RETICLE_SIZE-2*RETICLE_OFFSET)-(kLine_Width-RETICLE_WIDTH)/2+5;
         CGFloat lineOffset4 = RETICLE_OFFSET+(RETICLE_SIZE-2*RETICLE_OFFSET);
         
         
         //右上角 横线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         //CGFloat lineOffset3 = RETICLE_OFFSET+(kLine_Width-RETICLE_WIDTH)/2;
         CGContextMoveToPoint(context, lineOffset4, lineOffset1);
         CGContextAddLineToPoint(context, lineOffset2-20, lineOffset1);
         CGContextStrokePath(context);
         //右上角 竖线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         CGContextMoveToPoint(context, lineOffset2, RETICLE_OFFSET);
         CGContextAddLineToPoint(context, lineOffset2, kLine_Length);
         CGContextStrokePath(context);
         
         
         CGFloat lineOffset5 = RETICLE_OFFSET+(RETICLE_SIZE-2*RETICLE_OFFSET)+(kLine_Width-RETICLE_WIDTH)/2;
         //右下角 横线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         CGContextMoveToPoint(context, lineOffset4, lineOffset2);
         CGContextAddLineToPoint(context, lineOffset3-20, lineOffset2);
         CGContextStrokePath(context);
         //右下角 竖线
         CGContextSetStrokeColorWithColor(context, linecolor.CGColor);
         CGContextSetLineWidth(context, kLine_Width);
         CGContextBeginPath(context);
         CGContextMoveToPoint(context, lineOffset2, lineOffset3-kLine_Width/2);
         CGContextAddLineToPoint(context, lineOffset2, lineOffset2-20);
         CGContextStrokePath(context);
         */
        CGRect rect = CGRectMake(
                                 RETICLE_OFFSET,
                                 RETICLE_OFFSET,
                                 RETICLE_SIZE-2*RETICLE_OFFSET,
                                 RETICLE_SIZE-2*RETICLE_OFFSET
                                 );
        
        NSLog(@"x: %f, Y: %f,width : %f, height: %f",rect.origin.x,rect.origin.y,rect.size.width,rect.size.height);
    }
    
    result = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return result;
}

//=======add code by xyl==========================

- (void)setBorderline
{
    CGRect rect = CGRectMake(0, 124, 320, 320);
    
    //reticleRect =rect;
    
    UIImageView * imageqr1 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr1"]];
    imageqr1.frame = CGRectMake(kReticleX, reticleRect.origin.y, kQRWidth, kORHeight);
    [self.view addSubview:imageqr1];
    
    UIImageView * imageqr3 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr3"]];
    imageqr3.frame = CGRectMake(kReticleX, 354*2, kQRWidth, kORHeight);
    [self.view addSubview:imageqr3];
    
    UIImageView * imageqr2 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr2"]];
    imageqr2.frame = CGRectMake(268*2, reticleRect.origin.y, kQRWidth, kORHeight);
    [self.view addSubview:imageqr2];
    
    UIImageView * imageqr4 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"scanqr4"]];
    imageqr4.frame = CGRectMake(268*2, 354*2, kQRWidth, kORHeight);
    [self.view addSubview:imageqr4];
    
}

//方法一
-(void)DrawLineInImageView
{
    UIImageView *imageView1 = [[UIImageView alloc]initWithFrame:CGRectMake(0, 100, 320, 100)];
    [self.view addSubview:imageView1];
    [imageView1 setBackgroundColor:[[UIColor grayColor] colorWithAlphaComponent:0.2]];
    
    UIGraphicsBeginImageContext(imageView1.frame.size);   //开始画线
    float lengths[] = {10,5};
    CGContextRef line = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(line, [UIColor redColor].CGColor);
    
    //CGContextSetLineDash(line, 0, lengths, 2);  //画虚线
    CGContextMoveToPoint(line, 10.0, 20.0);    //开始画线  起点
    //CGContextMoveToPoint：原点移动到这个点   CGContextAddLineToPoint 上个点移动到这个点
    CGContextAddLineToPoint(line, 310.0, 20.0); // 上个点连线到下一个点
    CGContextAddLineToPoint(line, 310.0, 80.0); //上个点连线到下一个点
    CGContextAddLineToPoint(line, 10.0, 80.0); //上个点连线到下一个点
    CGContextAddLineToPoint(line, 10.0, 20.0); // 上个点连线到下一个点
    CGContextStrokePath(line);
    
    imageView1.image = UIGraphicsGetImageFromCurrentImageContext();
}



#pragma custom code
#define viewWidth 300
#define width1 100
#define origin_y 200
#define kLineWidth 240
#define kLineHeight 3

- (void)setScanLine
{
    self.line = [[UIView alloc] initWithFrame:CGRectMake((viewWidth - width1)/2, origin_y, width1, 1)];
    
    [self.view addSubview:self.line];
    self.line.backgroundColor = [UIColor redColor];
    
    [UIView beginAnimations:@"animationID" context:NULL];
    [UIView setAnimationDuration:4];
    
    [UIView setAnimationCurve:UIViewAnimationCurveLinear];
    [UIView setAnimationTransition:UIViewAnimationTransitionCurlDown forView:self.line cache:YES];  //这句话估计得注释掉才行，有一次就因为这句话出现个小问题
    [UIView setAnimationRepeatCount:100];
    
    [self.line setFrame:CGRectMake((viewWidth - width1)/2, origin_y+width1, width1, 1)];
    [UIView commitAnimations];
    
}

- (void)scanline1:(UIView*)reticleView
{
    //扫描线
    CGFloat lineOffset = RETICLE_OFFSET+(0.5*RETICLE_WIDTH);
    //self.reticleRect = self.view.frame;
    
    //    CGFloat lineOffset = RETICLE_OFFSET+(0.5*RETICLE_WIDTH);
    //    CGContextMoveToPoint(context, lineOffset, RETICLE_SIZE/2);
    //    CGContextAddLineToPoint(context, RETICLE_SIZE-lineOffset, 0.5*RETICLE_SIZE);
    
    
    //self.line = [[UIView alloc] initWithFrame:CGRectMake(40, 124, kLineWidth, kLineHeight)];
    self.line = [[UIView alloc] initWithFrame:CGRectMake(lineOffset, lineOffset+ RETICLE_SIZE/2, RETICLE_SIZE-lineOffset, kLineHeight)];
    
    //self.line.backgroundColor = [UIColor greenColor];
    
    UIImageView *ivline = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, RETICLE_SIZE-lineOffset, kLineHeight)];
    ivline.image = [UIImage imageNamed:@"line"];
    [self.line addSubview:ivline];
    
    //定时器，设定时间过1.5秒，
    // timer = [NSTimer scheduledTimerWithTimeInterval:.02 target:self selector:@selector(animation1) userInfo:nil repeats:YES];
    [reticleView addSubview:self.line];
    lineTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(moveLine) userInfo:nil repeats:YES];
    [lineTimer fire];
    
    
    UIImage *scanningBg = [UIImage imageNamed:@"pick_bg"];
    
    CGSize size  = [UIScreen mainScreen].bounds.size;
    UIImageView *scanningView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    scanningView.image = scanningBg;
    //[self.view addSubview:scanningView];
    
    //用于取消操作的button
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    UIImage *bimage = [UIImage imageNamed:@"icon.png"];
    [cancelButton setBackgroundImage:bimage forState:UIControlStateDisabled];
    [cancelButton setBackgroundColor:[UIColor whiteColor]];
    [cancelButton setTitleColor:[UIColor orangeColor] forState:UIControlStateNormal];
    [cancelButton setFrame:CGRectMake(20, size.height - 84, 280, 40)];
    [cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [cancelButton.titleLabel setFont:[UIFont boldSystemFontOfSize:20]];
    [cancelButton addTarget:self action:@selector(dismissOverlayView:)forControlEvents:UIControlEventTouchUpInside];
    
    //[self.view addSubview:cancelButton];
    
}

// 点击cancel  button事件
- (void)dismissOverlayView:(id)sender{
    [lineTimer invalidate];
    //[reader dismissModalViewControllerAnimated:YES];
}

//屏幕移动扫描线。
-(void)moveLine{
    
    CGRect lineFrame = self.line.frame;
    CGFloat y = lineFrame.origin.y;
    if (!isBottom) {
        isBottom = YES;
        y=y + self.lineHeight;
        lineFrame.origin.y = y;
        [UIView animateWithDuration:1.5 animations:^{
            self.line.frame = lineFrame;
        }];
    }else if(isBottom){
        isBottom = NO;
        y = y - self.lineHeight;
        lineFrame.origin.y = y;
        [UIView animateWithDuration:1.5 animations:^{
            self.line.frame = lineFrame;
        }];
    }
}
//=======add code by xyl==========================
-(void)animation1
{
    if (upOrdown == NO) {
        num ++;
        _line.frame = CGRectMake(50, 110+2*num, 220, 2);
        if (2*num == 280) {
            upOrdown = YES;
        }
    }
    else {
        num --;
        _line.frame = CGRectMake(50, 110+2*num, 220, 2);
        if (num == 0) {
            upOrdown = NO;
        }
    }
    
}


#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
    
    return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [CATransaction begin];
    
    self.processor.previewLayer.orientation = orientation;
    [self.processor.previewLayer layoutSublayers];
    self.processor.previewLayer.frame = self.view.bounds;
    
    [CATransaction commit];
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
}

@end
