//
//  BarcodeScan.m
//  QiFei
//
//  Created by 雷彬 on 14-8-6.
//
//

#import "BarcodeScan.h"

@implementation BarcodeScan

//--------------------------------------------------------------------------
- (BOOL)cameraIsPresent {
    return [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
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
- (void)displayPermissionMissingAlert {
    NSString *message = nil;
    if ([self scanningIsProhibited]) {
        message = @"请在“设置－隐私－相机”选项中，允许秦丝进销存访问你的相机";
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
    
    callback = command.callbackId;
    
    [self requestCameraPermissionWithSuccess:^(BOOL success) {
        if (success) {
            RootViewController * rt = [[RootViewController alloc]initWithPlugin:self callback:callback];
            [self.viewController presentViewController:rt animated:YES completion:^{
                
            }];
            
        } else {
            [self displayPermissionMissingAlert];
        }
    }];
    
    
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    [self returnError:@"encode function not supported" callback:command.callbackId];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled callback:(NSString*)callback {
    NSNumber* cancelledNumber = [NSNumber numberWithInt:(cancelled?1:0)];
    
    NSMutableDictionary* resultDict = [[NSMutableDictionary alloc] init];
    [resultDict setObject:scannedText     forKey:@"text"];
    [resultDict setObject:format          forKey:@"format"];
    [resultDict setObject:cancelledNumber forKey:@"cancelled"];
    
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary: resultDict
                               ];
    
    NSString* js = [result toSuccessCallbackString:callback];
    
    [self writeJavascript:js];
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








@implementation RootViewController

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;

- (id)initWithPlugin:(BarcodeScan *)plugin callback:(NSString*)callback
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        // Custom initialization
        self.plugin = plugin;
        self.callback = callback;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIButton * scanButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [scanButton setTitle:@"取消" forState:UIControlStateNormal];
    scanButton.frame = CGRectMake(0, self.view.bounds.size.height - 80, self.view.bounds.size.width, 80);
    scanButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    scanButton.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.65];
    [scanButton addTarget:self action:@selector(backAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:scanButton];
    
    UILabel * labIntroudction= [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    labIntroudction.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.65];
    labIntroudction.numberOfLines = 2;
    labIntroudction.textColor = [UIColor whiteColor];
    labIntroudction.textAlignment = NSTextAlignmentCenter;
    labIntroudction.text = @"将条码/二维码置于框内";
    [self.view addSubview:labIntroudction];
    
    
    UIImageView * imageView = [[UIImageView alloc]initWithFrame:CGRectMake(self.view.bounds.size.width/2-150, self.view.bounds.size.height/2-150, 300, 300)];
    imageView.image = [UIImage imageNamed:@"pick_bg"];
    [self.view addSubview:imageView];
    
    upOrdown = NO;
    num =0;
    _line = [[UIImageView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width/2-110, self.view.bounds.size.height/2, 220, 2)];
    _line.image = [UIImage imageNamed:@"line.png"];
    [self.view addSubview:_line];
    
    timer = [NSTimer scheduledTimerWithTimeInterval:.02 target:self selector:@selector(animation1) userInfo:nil repeats:YES];
}

-(void)animation1
{
    if (upOrdown == NO) {
        num ++;
        _line.frame = CGRectMake(self.view.bounds.size.width/2-110, self.view.bounds.size.height/2-140+2*num, 220, 2);
        if (2*num == 280) {
            upOrdown = YES;
        }
    }
    else {
        num --;
        _line.frame = CGRectMake(self.view.bounds.size.width/2-110, self.view.bounds.size.height/2-140+2*num, 220, 2);
        if (num == 0) {
            upOrdown = NO;
        }
    }
    
}

-(void)backAction
{
    
    [self dismissViewControllerAnimated:YES completion:^{
        [timer invalidate];
        [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE callback:self.callback];
    }];
}

-(void)viewWillAppear:(BOOL)animated
{
    [self setupCamera];
}

- (void)setupCamera
{
    NSError *error = nil;
    // Device
    _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (_device.isAutoFocusRangeRestrictionSupported) {
        if ([_device lockForConfiguration:&error]) {
            [_device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
            [_device unlockForConfiguration];
        }
    }
    
    // Input
    _input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:nil];
    
    // Output
    _output = [[AVCaptureMetadataOutput alloc]init];
    [_output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    
    // Session
    _session = [[AVCaptureSession alloc]init];
    [_session setSessionPreset:AVCaptureSessionPresetHigh];
    if ([_session canAddInput:self.input])
    {
        [_session addInput:self.input];
    }
    
    if ([_session canAddOutput:self.output])
    {
        [_session addOutput:self.output];
    }
    
    // 条码类型
    _output.metadataObjectTypes =@[AVMetadataObjectTypeQRCode, AVMetadataObjectTypeUPCECode, AVMetadataObjectTypeCode39Code,
                                   AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeCode128Code, AVMetadataObjectTypeCode39Mod43Code,
                                   AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypePDF417Code,
                                   AVMetadataObjectTypeAztecCode];
    
    //_output.metadataObjectTypes =@[AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code];
    
    // Preview
    _preview =[AVCaptureVideoPreviewLayer layerWithSession:self.session];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _preview.frame = self.view.bounds;
    
    if (_preview.connection.supportsVideoOrientation) {
        _preview.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    [self.view.layer insertSublayer:self.preview atIndex:0];
    
    // Start
    [_session startRunning];
}


// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotate {
    // Return YES for supported orientations.
    return NO;
}


#pragma mark AVCaptureMetadataOutputObjectsDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    
    NSString *stringValue;
    
    if ([metadataObjects count] >0)
    {
        AVMetadataMachineReadableCodeObject * metadataObject = [metadataObjects objectAtIndex:0];
        stringValue = metadataObject.stringValue;
    }
    
    [_session stopRunning];
    [self dismissViewControllerAnimated:YES completion:^
     {
         [timer invalidate];
         NSLog(@"%@",stringValue);
         [self.plugin returnSuccess:stringValue format:@"" cancelled:FALSE callback:self.callback];
     }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    self.plugin = nil;
    self.callback = nil;
}

@end

