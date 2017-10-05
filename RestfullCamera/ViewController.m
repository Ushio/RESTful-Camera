//
//  ViewController.m
//  RestfullCamera
//
//  Created by Ushio on 2017/10/04.
//  Copyright © 2017年 wow. All rights reserved.
//

#import "ViewController.h"

// TODO
/*
 画像の向き
 ホワイトバランス
 */
#include <ifaddrs.h>
#include <arpa/inet.h>

static NSString *selfIP() {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    
                }
                
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;
}

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

@property (weak, nonatomic) IBOutlet UISlider *slider3;
@property (weak, nonatomic) IBOutlet UISlider *slider2;
@property (weak, nonatomic) IBOutlet UISlider *slider1;

@property (nonatomic) NSMutableArray<DataTask *> *takeQueue;
@end

@implementation ViewController {
    AVCaptureSession *_session;
    AVCaptureDevice *_device;
    AVCapturePhotoOutput *_output;
    AVCaptureVideoPreviewLayer *_previewLayer;
    
    float _iso;
    CMTime _shutterSpeed;
    
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
        
        _device.activeFormat = largeFormat;
        NSLog(@"%@", largeFormat);
        
        [_device unlockForConfiguration];
    }
    
    //セッション開始
    [_session startRunning];
    
    _iso = 100.0f;
    _shutterSpeed = CMTimeMake(1, 30);
    
    [self didChangeSlider1:self.slider1];
    [self didChangeSlider2:self.slider2];
    [self didChangeSlider3:self.slider3];
    
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
}
- (IBAction)shoot:(id)sender {
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

- (IBAction)didChangeSlider1:(UISlider *)sender {
    NSError *error;
    if([_device lockForConfiguration:&error]) {
        [_device setFocusModeLockedWithLensPosition:sender.value completionHandler:nil];
        [_device unlockForConfiguration];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
