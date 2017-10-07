//
//  ViewController.m
//  RestfullCamera
//
//  Created by Ushio on 2017/10/04.
//  Copyright © 2017年 wow. All rights reserved.
//

#import "ViewController.h"
#import "SelfIP.h"

/*
 TODO
  -Zoom
 */


@interface DataTask : NSObject
@property (nonatomic) NSData *data;
@property (nonatomic) dispatch_semaphore_t semaphore;
- (void)signal;
- (void)wait;
@end
@implementation DataTask
- (instancetype)init {
    self = [super init];
    _semaphore = dispatch_semaphore_create(0);
    return self;
}
- (void)signal {
    dispatch_semaphore_signal(_semaphore);
}
- (void)wait {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
}
@end

// 解像度
// https://wayohoo.com/ios/news/summary-of-iphones-camera-specs.html


@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *labelIP;
@property (weak, nonatomic) IBOutlet UILabel *labelShutterSpeed;
@property (weak, nonatomic) IBOutlet UILabel *labelISO;
@property (weak, nonatomic) IBOutlet UILabel *labelColorTemperature;

@property (weak, nonatomic) IBOutlet UISlider *slider4;
@property (weak, nonatomic) IBOutlet UISlider *slider3;
@property (weak, nonatomic) IBOutlet UISlider *slider2;
@property (weak, nonatomic) IBOutlet UISlider *slider1;

@property (weak, nonatomic) IBOutlet UIImageView *upImageView;

@property (nonatomic) NSMutableArray<DataTask *> *takeQueue;
@end

@implementation ViewController {
    AVCaptureSession *_session;
    AVCaptureDevice *_device;
    AVCapturePhotoOutput *_output;
    AVCaptureVideoPreviewLayer *_previewLayer;
    
    float _iso;
    CMTime _shutterSpeed;
    
    UIImageOrientation _orientation;
    
    NSTimer *_timer;
    
    GCDWebServer *_server;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UILabel *ip = self.labelIP;
    
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        ip.text = selfIP();
        [ip sizeToFit];
    }];
    
    _session = [[AVCaptureSession alloc] init];
    
    _device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
    if(_device == nil) {
        NSLog(@"?");
    }
    
    // フォーマットを探しておく
    AVCaptureDeviceFormat *largeFormat = nil;
    uint32_t area = 0;
    for (AVCaptureDeviceFormat *format in _device.formats) {
        // NSLog(@"%@", format);
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        int thisArea = dimensions.width * dimensions.height;
        if(area < thisArea) {
            largeFormat = format;
        }
    }
    NSError *error;
    
    AVCaptureInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:_device error:&error];
    if(input == nil) {
        NSLog(@"%@", error.localizedDescription);
    }
    
    [_session addInput:input];
    _output = [[AVCapturePhotoOutput alloc] init];
    [_session addOutput:_output];
    
    //画像を表示するレイヤーを生成
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
    _previewLayer.frame = self.view.bounds;
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    //Viewに追加
    // [self.view.layer addSublayer:_previewLayer];
    [self.view.layer insertSublayer:_previewLayer atIndex:0];
    
    
    if([_device lockForConfiguration:&error]) {
        _device.focusMode = AVCaptureFocusModeLocked;
        _device.whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
        
        _device.activeFormat = largeFormat;
        NSLog(@"%@", largeFormat);
        
        [_device unlockForConfiguration];
    }
    
    //セッション開始
    [_session startRunning];
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if([ud objectForKey:@"orientation"]) {
        self.slider1.value = [ud floatForKey:@"slider1"];
        self.slider2.value = [ud floatForKey:@"slider2"];
        self.slider3.value = [ud floatForKey:@"slider3"];
        self.slider4.value = [ud floatForKey:@"slider4"];
        _orientation = [ud integerForKey:@"orientation"];
    }
    
    [self didChangeSlider1:self.slider1];
    [self didChangeSlider2:self.slider2];
    [self didChangeSlider3:self.slider3];
    [self didChangeSlider4:self.slider4];
    
    _takeQueue = [NSMutableArray<DataTask *> array];
    
    _server = [[GCDWebServer alloc] init];
    @weakify(self)
    [_server addDefaultHandlerForMethod:@"GET"
                           requestClass:[GCDWebServerRequest class]
                           processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
                               DataTask *task = [[DataTask alloc] init];
                               dispatch_sync(dispatch_get_main_queue(), ^{
                                   @strongify(self)
                                   [self.takeQueue addObject:task];
                                   [self shoot:nil];
                               });
                               [task wait];
                               return [GCDWebServerDataResponse responseWithData:task.data contentType:@"image/jpeg"];
                               // return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
                           }];
    [_server startWithPort:8080 bonjourName:nil];
}
- (IBAction)didChangeSlider4:(UISlider *)sender {
    NSError *error;
    if([_device lockForConfiguration:&error]) {
        int minColorTemperature00 = 30;
        int maxColorTemperature00 = 80;
        int N = (int)(maxColorTemperature00 - minColorTemperature00 + 1);
        int n = MIN((int)(sender.value * N), N - 1);
        sender.value = (float)n / (float)(N - 1);
        
        int colorTemperature = (minColorTemperature00 + n) * 100;
        
        AVCaptureWhiteBalanceTemperatureAndTintValues temp = {};
        temp.temperature = colorTemperature;
        temp.tint = 0.0f;
        AVCaptureWhiteBalanceGains gains = [_device deviceWhiteBalanceGainsForTemperatureAndTintValues:temp];
        float maxGain = [_device maxWhiteBalanceGain];
        gains.redGain = MIN(MAX(1.0f, gains.redGain), maxGain);
        gains.greenGain = MIN(MAX(1.0f, gains.greenGain), maxGain);
        gains.blueGain = MIN(MAX(1.0f, gains.blueGain), maxGain);
        [_device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:nil];
        [_device unlockForConfiguration];
        
        self.labelColorTemperature.text = [NSString stringWithFormat:@"Color Temp: %d", colorTemperature];
    }
    
    [self save];
}

- (IBAction)didChangeSlider3:(UISlider *)sender {
    AVCaptureDeviceFormat *activeFormat = _device.activeFormat;
    CMTime minDuration = activeFormat.minExposureDuration;
    CMTime maxDuration = activeFormat.maxExposureDuration;
    CMTimeRange range = CMTimeRangeMake(minDuration, maxDuration);
    
#define S(s) [NSValue valueWithCMTime:CMTimeMake(1, s)]
    NSArray<NSValue *> *basicDurations = @[
                                           S(2),
                                           S(3),
                                           S(4),
                                           S(5),
                                           S(6),
                                           S(7),
                                           S(8),
                                           S(9),
                                           S(10),
                                           S(15),
                                           S(20),
                                           S(25),
                                           S(30),
                                           S(40),
                                           S(50),
                                           S(60),
                                           S(70),
                                           S(80),
                                           S(90),
                                           S(100),
                                           S(125),
                                           S(250),
                                           S(500),
                                           S(1000),
                                           ];
#undef S
    
    NSMutableArray<NSValue *> *availableDuration = [NSMutableArray<NSValue *> array];
    for(int i = 0 ; i < basicDurations.count ; ++i) {
        if(CMTimeRangeContainsTime(range, [basicDurations[i] CMTimeValue])) {
            [availableDuration addObject:basicDurations[i]];
        }
    }

    int N = (int)availableDuration.count;
    int n = MIN((int)(sender.value * N), N - 1);
    sender.value = (float)n / (float)(N - 1);

    _shutterSpeed = [availableDuration[n] CMTimeValue];
    self.labelShutterSpeed.text = [NSString stringWithFormat:@"%d/%d", (int)_shutterSpeed.value, (int)_shutterSpeed.timescale];
    
    NSError *error;
    if([_device lockForConfiguration:&error]) {
        [_device setExposureModeCustomWithDuration:_shutterSpeed ISO:_iso completionHandler:nil];
        [_device unlockForConfiguration];
    }
    [self save];
}

- (IBAction)didChangeSlider2:(UISlider *)sender {
    AVCaptureDeviceFormat *activeFormat = _device.activeFormat;
    float minISO  = activeFormat.minISO;
    float maxISO  = activeFormat.maxISO;
    
    _iso = minISO + (maxISO - minISO) * sender.value;
    self.labelISO.text = [NSString stringWithFormat:@"ISO: %.1f", _iso];
    
    NSError *error;
    if([_device lockForConfiguration:&error]) {
        [_device setExposureModeCustomWithDuration:_shutterSpeed ISO:_iso completionHandler:nil];
        [_device unlockForConfiguration];
    }
    
    [self save];
}
- (IBAction)didChangeSlider1:(UISlider *)sender {
    NSError *error;
    if([_device lockForConfiguration:&error]) {
        [_device setFocusModeLockedWithLensPosition:sender.value completionHandler:nil];
        [_device unlockForConfiguration];
    }
    [self save];
}

- (IBAction)shoot:(id)sender {
    AVCaptureConnection *connection = [_output connectionWithMediaType:AVMediaTypeVideo];
    NSDictionary<NSNumber *, NSNumber *> *orientationMap = @{@(UIImageOrientationUp):@(AVCaptureVideoOrientationPortrait),
                                                             @(UIImageOrientationRight):@(AVCaptureVideoOrientationLandscapeRight),
                                                             @(UIImageOrientationDown):@(AVCaptureVideoOrientationPortraitUpsideDown),
                                                             @(UIImageOrientationLeft):@(AVCaptureVideoOrientationLandscapeLeft) };
    connection.videoOrientation = (AVCaptureVideoOrientation)(orientationMap[@(_orientation)].intValue);
    
    AVCapturePhotoSettings *settings = [[AVCapturePhotoSettings alloc] init];
    settings.flashMode = AVCaptureFlashModeOff;
    if (@available(iOS 10.2, *)) {
        [settings setAutoDualCameraFusionEnabled:NO];
    }
    [settings setAutoStillImageStabilizationEnabled:NO];

    [_output capturePhotoWithSettings:settings delegate:self];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhotoSampleBuffer:(nullable CMSampleBufferRef)photoSampleBuffer previewPhotoSampleBuffer:(nullable CMSampleBufferRef)previewPhotoSampleBuffer resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings bracketSettings:(nullable AVCaptureBracketedStillImageSettings *)bracketSettings error:(nullable NSError *)error {
    NSData *data = [AVCapturePhotoOutput JPEGPhotoDataRepresentationForJPEGSampleBuffer:photoSampleBuffer previewPhotoSampleBuffer:previewPhotoSampleBuffer];
    // UIImage *image = [UIImage imageWithData:data];
    // NSLog(@"take: %@", NSStringFromCGSize(image.size));
    // UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    
    DataTask *task = [self.takeQueue firstObject];
    if(task) {
        [self.takeQueue removeObjectAtIndex:0];
        task.data = data;
        [task signal];
    }
}


- (IBAction)tapUp:(UITapGestureRecognizer *)sender {
    NSDictionary<NSNumber *, NSNumber *> *nextOrientation = @{@(UIImageOrientationUp):@(UIImageOrientationRight),
                                                              @(UIImageOrientationRight):@(UIImageOrientationDown),
                                                              @(UIImageOrientationDown):@(UIImageOrientationLeft),
                                                              @(UIImageOrientationLeft):@(UIImageOrientationUp) };
    _orientation = (UIImageOrientation)(nextOrientation[@(_orientation)].intValue);
    
    UIImage *image = [UIImage imageNamed:@"up"];
    self.upImageView.image = [UIImage imageWithCGImage:image.CGImage scale:1.0 orientation:_orientation];
    
    [self save];
}

- (void)save {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setFloat:self.slider1.value forKey:@"slider1"];
    [ud setFloat:self.slider2.value forKey:@"slider2"];
    [ud setFloat:self.slider3.value forKey:@"slider3"];
    [ud setFloat:self.slider4.value forKey:@"slider4"];
    [ud setInteger:_orientation forKey:@"orientation"];
    
    [ud synchronize];
}


@end
