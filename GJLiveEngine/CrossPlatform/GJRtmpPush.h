//
//  GJRtmpSender.h
//  GJCaptureTool
//
//  Created by mac on 17/2/24.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <stdlib.h>
#include "GJRetainBuffer.h"
#include "rtmp.h"
#include "GJBufferPool.h"
#include "GJQueue.h"
#import "GJLiveDefine.h"
#import "GJLiveDefine+internal.h"

typedef enum _GJRTMPPushMessageType{
    GJRTMPPushMessageType_connectSuccess,
    GJRTMPPushMessageType_closeComplete,

    
    GJRTMPPushMessageType_connectError,
    GJRTMPPushMessageType_urlPraseError,
    GJRTMPPushMessageType_sendPacketError,//网络错误，发送失败
}GJRTMPPushMessageType;



struct _GJRtmpPush;
typedef GVoid(*PushMessageCallback)(GHandle userData, GJRTMPPushMessageType messageType,GHandle messageParm);

#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPush{
    RTMP*                   rtmp;
    GJQueue*                sendBufferQueue;
    char                    pushUrl[MAX_URL_LENGTH];
    
    pthread_t                sendThread;
    pthread_mutex_t          mutex;

    PushMessageCallback      messageCallback;
    void*                   rtmpPushParm;
    int                     stopRequest;
    int                     releaseRequest;
    
    GJTrafficStatus         audioStatus;
    GJTrafficStatus         videoStatus;
}GJRtmpPush;

GBool GJRtmpPush_Create(GJRtmpPush** push,PushMessageCallback callback,void* rtmpPushParm);
GVoid GJRtmpPush_CloseAndDealloc(GJRtmpPush** push);

/**
 发送h264

 @param push push description
 @param data data description
 */
GBool GJRtmpPush_SendH264Data(GJRtmpPush* push,R_GJH264Packet* data);
GBool GJRtmpPush_SendAACData(GJRtmpPush* push,R_GJAACPacket* data);
GBool GJRtmpPush_StartConnect(GJRtmpPush* push,const char* sendUrl);
GFloat32 GJRtmpPush_GetBufferRate(GJRtmpPush* push);
GJTrafficStatus GJRtmpPush_GetVideoBufferCacheInfo(GJRtmpPush* push);
GJTrafficStatus GJRtmpPush_GetAudioBufferCacheInfo(GJRtmpPush* push);
