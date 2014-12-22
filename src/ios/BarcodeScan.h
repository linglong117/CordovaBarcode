//
//  BarcodeScan.h
//  QiFei
//
//  Created by 雷彬 on 14-8-6.
//
//

#import <UIKit/UIKit.h>
#import <Cordova/CDVPlugin.h>
#import <AVFoundation/AVFoundation.h>

@interface BarcodeScan : CDVPlugin {}
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

@interface RootViewController : UIViewController<AVCaptureMetadataOutputObjectsDelegate>
{
    int num;
    BOOL upOrdown;
    NSTimer * timer;
}
@property (strong,nonatomic)AVCaptureDevice * device;
@property (strong,nonatomic)AVCaptureDeviceInput * input;
@property (strong,nonatomic)AVCaptureMetadataOutput * output;
@property (strong,nonatomic)AVCaptureSession * session;
@property (strong,nonatomic)AVCaptureVideoPreviewLayer * preview;
@property (nonatomic, retain) UIImageView * line;
@property (nonatomic, retain) BarcodeScan * plugin;
@property (nonatomic, retain) NSString * callback;

- (id)initWithPlugin:(BarcodeScan*)plugin callback:(NSString*)callback;
@end