//
//  GJLivePull.m
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePull.h"
#import "GJH264Decoder.h"
#import "GJLivePlayer.h"
#import "GJLog.h"
#import "GJPCMDecodeFromAAC.h"
#import <CoreImage/CoreImage.h>
#import "GJLivePullContext.h"


@interface GJLivePull()
{
    NSThread*  _playThread;
    GJPullSessionStatus _pullSessionStatus;
    GJLivePullContext* _pullContext;
    
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPCMDecodeFromAAC* audioDecoder;
@property(strong,nonatomic) NSRecursiveLock* lock;

@property(assign,nonatomic)GJLivePlayer* player;
@property(assign,nonatomic)float gaterFrequency;
@property(strong,nonatomic)NSTimer * timer;

@property(assign,nonatomic)GJTrafficStatus videoTraffic;
@property(assign,nonatomic)GJTrafficStatus audioTraffic;



@end
@implementation GJLivePull

static GVoid livePullCallback(GHandle userDate,GJLivePullMessageType message,GHandle param);

- (instancetype)init
{
    self = [super init];
    if (self) {
        GJLivePull_Create(&(_pullContext), livePullCallback, (__bridge GHandle)(self));
        _enablePreview = YES;
        _gaterFrequency = 2.0;
        _lock = [[NSRecursiveLock alloc]init];
    }
    return self;
}

static void livePullCallback(GHandle pull, GJLivePullMessageType messageType,GHandle parm){
    GJLivePull* livePull = (__bridge GJLivePull *)(pull);
    
        switch (messageType) {
            case GJLivePull_connectError:
            case GJLivePull_urlPraseError:
                GJLOG(GJ_LOGERROR, "pull connect error:%d",messageType);
                [livePull.delegate livePull:livePull errorType:kLivePullConnectError infoDesc:@"连接错误"];
                [livePull stopStreamPull];
                break;
            case GJLivePull_receivePacketError:
                GJLOG(GJ_LOGERROR, "pull sendPacket error:%d",messageType);
                [livePull.delegate livePull:livePull errorType:kLivePullReadPacketError infoDesc:@"读取失败"];
                [livePull stopStreamPull];
                break;
            case GJLivePull_connectSuccess:
            {
                GJLOG(GJ_LOGINFO, "pull connectSuccess");
                [livePull.delegate livePull:livePull connentSuccessWithElapsed:*(GInt32*)parm];
                dispatch_async(dispatch_get_main_queue(), ^{
                    livePull.timer = [NSTimer scheduledTimerWithTimeInterval:livePull.gaterFrequency target:livePull selector:@selector(updateStatusCallback) userInfo:nil repeats:YES];
                    GJLOG(GJ_LOGINFO, "NSTimer START:%s",[NSString stringWithFormat:@"%@",livePull.timer].UTF8String);
                });
                

            }
                break;
            case GJLivePull_closeComplete:{
                GJLOG(GJ_LOGINFO, "pull closeComplete");
                [livePull.delegate livePull:livePull closeConnent:parm resion:kConnentCloce_Active];
            }
                break;
            case GJLivePull_bufferUpdate:{
                UnitBufferInfo* info = parm;
                [livePull.delegate livePull:livePull bufferUpdatePercent:info->percent duration:info->bufferDur];
            }
                break;
            case GJLivePull_decodeFristVideoFrame:{
//                GJPullFristFrameInfo info = {0};
//                info.size = *(GSize*)parm;
                [livePull.delegate livePull:livePull fristFrameDecode:parm];
            }
                break;
            default:
                GJLOG(GJ_LOGERROR,"not catch info：%d",messageType);
                break;
        }
}

-(void)updateStatusCallback{
    GJTrafficStatus vCache = GJLivePull_GetVideoTrafficStatus(_pullContext);
    GJTrafficStatus aCache = GJLivePull_GetAudioTrafficStatus(_pullContext);
    _pullSessionStatus.videoStatus.cacheCount = vCache.enter.count - vCache.leave.count;
    _pullSessionStatus.videoStatus.cacheTime = vCache.enter.ts - vCache.leave.ts;
    _pullSessionStatus.videoStatus.bitrate = (vCache.enter.byte - _videoTraffic.enter.byte)*1.0 / _gaterFrequency;
    _pullSessionStatus.videoStatus.frameRate = (vCache.leave.count - _videoTraffic.leave.count)*1.0  / _gaterFrequency;
    _pullSessionStatus.audioStatus.cacheCount = aCache.enter.count - aCache.leave.count;
    _pullSessionStatus.audioStatus.cacheTime = aCache.enter.ts - aCache.leave.ts;
    _pullSessionStatus.audioStatus.bitrate =  (aCache.enter.byte - _audioTraffic.enter.byte)*1.0 / _gaterFrequency;
    _pullSessionStatus.audioStatus.frameRate = (aCache.leave.count - _audioTraffic.leave.count)*1.0  / _gaterFrequency;
    _videoTraffic = vCache;
    _audioTraffic = aCache;
    [self.delegate livePull:self updatePullStatus:&_pullSessionStatus];
#ifdef NETWORK_DELAY
     
    if ([self.delegate respondsToSelector:@selector(livePull:networkDelay:)]) {
        [self.delegate livePull:self networkDelay:[_player getNetWorkDelay]];
    }
#endif
}

- (bool)startStreamPullWithUrl:(char*)url{
    [_timer invalidate];
    return GJLivePull_StartPull(_pullContext, url);
}

- (void)stopStreamPull{
    return GJLivePull_StopPull(_pullContext);
}

-(UIView *)getPreviewView{
    return (__bridge UIView *)(GJLivePull_GetDisplayView(_pullContext));
}

-(void)setEnablePreview:(BOOL)enablePreview{
    _enablePreview = enablePreview;
}

-(void)dealloc{
    if (_pullContext) {
        GJLivePull_Dealloc(&(_pullContext));
    }
}
@end
