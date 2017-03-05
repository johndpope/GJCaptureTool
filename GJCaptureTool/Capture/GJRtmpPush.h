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
#import <Foundation/Foundation.h>

typedef enum _GJRTMPPushMessageType{
    GJRTMPPushMessageType_connectSuccess,
    GJRTMPPushMessageType_closeComplete,

    
    GJRTMPPushMessageType_connectError,
    GJRTMPPushMessageType_urlPraseError,
    GJRTMPPushMessageType_sendPacketError,
}GJRTMPPushMessageType;

typedef void(*PullMessageCallback)(GJRTMPPushMessageType messageType,void* rtmpPullParm,void* messageParm);

#define MAX_URL_LENGTH 100
typedef struct _GJRtmpPush{
    RTMP*               rtmp;
    GJQueue*            sendBufferQueue;
    char                pushUrl[MAX_URL_LENGTH];
    
    GJBufferPool*       memoryCachePool;
    pthread_t           sendThread;
    int                 sendPacketCount;
    int                 dropPacketCount;
    int                 sendByte;
    PullMessageCallback messageCallback;
    void*               rtmpPushParm;
    int                 stopRequest;
}GJRtmpPush;

void GJRtmpPush_Create(GJRtmpPush** push,PullMessageCallback callback,void* rtmpPushParm);
void GJRtmpPush_SendH264Data(GJRtmpPush* push,GJRetainBuffer* data,uint32_t dts);
void GJRtmpPush_SendAACData(GJRtmpPush* push,GJRetainBuffer* data,uint32_t dts);
void GJRtmpPush_CloseAndRelease(GJRtmpPush* push);
void GJRtmpPush_StartConnect(GJRtmpPush* push,const char* sendUrl);
float GJRtmpPush_GetBufferRate(GJRtmpPush* push);
