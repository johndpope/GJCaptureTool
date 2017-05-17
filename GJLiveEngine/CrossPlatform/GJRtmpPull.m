//
//  GJRtmpPull.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPull.h"
#include "GJLog.h"
#include "sps_decode.h"
#import "GJLiveDefine+internal.h"
#include <string.h>
#import <Foundation/Foundation.h>
#import "GJBufferPool.h"
#define BUFFER_CACHE_SIZE 40
#define RTMP_RECEIVE_TIMEOUT    10




GVoid GJRtmpPull_Delloc(GJRtmpPull* pull);

GBool packetBufferRelease(GJRetainBuffer* buffer){
    if (buffer->data) {
        free(buffer->data);
    }
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)buffer);
    return GTrue;
}

static GHandle pullRunloop(GHandle parm){
    pthread_setname_np("rtmpPullLoop");
    GJRtmpPull* pull = (GJRtmpPull*)parm;
    GJRTMPPullMessageType errType = GJRTMPPullMessageType_connectError;
    GHandle errParm = NULL;
    GInt32 ret = RTMP_SetupURL(pull->rtmp, pull->pullUrl);
    if (!ret) {
        errType = GJRTMPPullMessageType_urlPraseError;
        GJLOG(GJ_LOGERROR, "RTMP_SetupURL error");
        goto ERROR;
    }
    pull->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    ret = RTMP_Connect(pull->rtmp, NULL);
    if (!ret) {
        errType = GJRTMPPullMessageType_connectError;
        GJLOG(GJ_LOGERROR, "RTMP_Connect error");
        goto ERROR;
    }
    ret = RTMP_ConnectStream(pull->rtmp, 0);
    if (!ret) {
        errType = GJRTMPPullMessageType_connectError;
        GJLOG(GJ_LOGERROR, "RTMP_ConnectStream error");
        goto ERROR;
    }else{
        GJLOG(GJ_LOGDEBUG, "RTMP_Connect success");
        if(pull->messageCallback){
            pull->messageCallback(pull, GJRTMPPullMessageType_connectSuccess,pull->messageCallbackParm,NULL);
        }
    }

    
    while(!pull->stopRequest){
        RTMPPacket packet = {0};
        GBool rResult = GFalse;
        while ((rResult = RTMP_ReadPacket(pull->rtmp, &packet))) {
            GUInt8 *sps = NULL,*pps = NULL,*pp = NULL,*sei = NULL;
            GInt32 spsSize = 0,ppsSize = 0,ppSize = 0,seiSize=0;
            GJStreamPacket streamPacket;
            if (!RTMPPacket_IsReady(&packet) || !packet.m_nBodySize)
            {
                continue;
            }
            
            RTMP_ClientPacket(pull->rtmp, &packet);
            
            if (packet.m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                GJLOGFREQ("receive audio pts:%d",packet.m_nTimeStamp);
                streamPacket.type = GJMediaType_Audio;
                pull->audioPullInfo.pts = packet.m_nTimeStamp;
                pull->audioPullInfo.count++;
                pull->audioPullInfo.byte += packet.m_nBodySize;
                GUInt8* body = (GUInt8*)packet.m_body;
                
                R_GJAACPacket* aacPacket = (R_GJAACPacket*)                GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJAACPacket));
                memset(aacPacket, 0, sizeof(R_GJAACPacket));

                GJRetainBuffer* retainBuffer = &aacPacket->retain;
                retainBufferPack(&retainBuffer, body - RTMP_MAX_HEADER_SIZE, RTMP_MAX_HEADER_SIZE+packet.m_nBodySize, packetBufferRelease, NULL);
//                retainBufferMoveDataToPoint(retainBuffer, RTMP_MAX_HEADER_SIZE, GFalse);
                aacPacket->pts = packet.m_nTimeStamp;
                aacPacket->adtsOffset = body+2-aacPacket->retain.data;
                aacPacket->adtsSize = 7;
                aacPacket->aacOffset = aacPacket->adtsOffset+7;
                aacPacket->aacSize = (GInt32)(packet.m_nBodySize -aacPacket->adtsSize - 2);
                streamPacket.packet.aacPacket = aacPacket;
                packet.m_body=NULL;
                pull->dataCallback(pull,streamPacket,pull->dataCallbackParm);
                retainBufferUnRetain(retainBuffer);
                
            }else if (packet.m_packetType == RTMP_PACKET_TYPE_VIDEO){
                GJLOGFREQ("receive audio pts:%d",packet.m_nTimeStamp);
                streamPacket.type = GJMediaType_Video;
                GUInt8 *body = (GUInt8*)packet.m_body;
                GUInt8 *pbody = body;
                GInt32 isKey = 0;
                if ((pbody[0] & 0x0F) == 7) {
                    if (pbody[1] == 0) {//sps pps
                        spsSize += pbody[11]<<8;
                        spsSize += pbody[12];
                        sps = pbody+13;
                        
                        pbody = sps+spsSize;
                        ppsSize += pbody[1]<<8;
                        ppsSize += pbody[2];
                        pps = pbody+3;
                        pbody = pps+ppsSize;
                        if (pbody+4>body+packet.m_nBodySize) {
                            GJLOG(GJ_LOGINFO,"only spspps\n");
                        }
                    }
                    if (pbody[1] == 1) {//naul
                        find_pp_sps_pps(&isKey, pbody+8,(GInt32)(body+packet.m_nBodySize- pbody-8), &pp, NULL, NULL, NULL, NULL, &sei, &seiSize);
                        ppSize = (GInt32)(body+packet.m_nBodySize-pp);
                    }else{
                        GJAssert(0,"h264 stream no naul\n");
                    }
                    
                }else{
                    GJAssert(0,"not h264 stream,type:%d\n",body[0] & 0x0F);
                }
                
                R_GJH264Packet* h264Packet = (R_GJH264Packet*)                GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJH264Packet));
                memset(h264Packet, 0, sizeof(R_GJH264Packet));
                GJRetainBuffer* retainBuffer = &h264Packet->retain;
                retainBufferPack(&retainBuffer, packet.m_body-RTMP_MAX_HEADER_SIZE,RTMP_MAX_HEADER_SIZE+packet.m_nBodySize,packetBufferRelease, NULL);
               
                
                h264Packet->spsOffset = sps - retainBuffer->data;
                h264Packet->spsSize = spsSize;
                h264Packet->ppsOffset = pps - retainBuffer->data;
                h264Packet->ppsSize = ppsSize;
                h264Packet->ppOffset = pp - retainBuffer->data;
                h264Packet->ppSize = ppSize;
                h264Packet->seiOffset = sei - retainBuffer->data;
                h264Packet->seiSize = seiSize;
                h264Packet->pts = packet.m_nTimeStamp;
                streamPacket.packet.h264Packet = h264Packet;
                
                
                pull->videoPullInfo.pts = packet.m_nTimeStamp;
                pull->videoPullInfo.count++;
                pull->videoPullInfo.byte += packet.m_nBodySize;
                
                pull->dataCallback(pull,streamPacket,pull->dataCallbackParm);
                retainBufferUnRetain(retainBuffer);
                packet.m_body=NULL;
            }else{
                GJLOG(GJ_LOGWARNING,"not media Packet:%p type:%d",packet,packet.m_packetType);
                RTMPPacket_Free(&packet);
                break;
            }
            break;
        }
//        if (packet.m_body) {
//            RTMPPacket_Free(&packet);
////            GJAssert(0, "读取数据错误\n");
//        }
        if (rResult == GFalse) {
            errType = GJRTMPPullMessageType_receivePacketError;
            GJLOG(GJ_LOGWARNING,"pull Read Packet Error");
            goto ERROR;
        }
    }
    errType = GJRTMPPullMessageType_closeComplete;
ERROR:
    RTMP_Close(pull->rtmp);
    if (pull->messageCallback) {
        pull->messageCallback(pull, errType,pull->messageCallbackParm,errParm);
    }
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->pullThread = NULL;
    if (pull->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJRtmpPull_Delloc(pull);
    }
    GJLOG(GJ_LOGDEBUG, "pullRunloop end");
    return NULL;
}
GVoid GJRtmpPull_Create(GJRtmpPull** pullP,PullMessageCallback callback,GHandle rtmpPullParm){
    GJRtmpPull* pull = NULL;
    if (*pullP == NULL) {
        pull = (GJRtmpPull*)malloc(sizeof(GJRtmpPull));
    }else{
        pull = *pullP;
    }
    memset(pull, 0, sizeof(GJRtmpPull));
    pull->rtmp = RTMP_Alloc();
    RTMP_Init(pull->rtmp);
    
    pull->messageCallback = callback;
    pull->messageCallbackParm = rtmpPullParm;
    pull->stopRequest = GFalse;
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
}

GVoid GJRtmpPull_Delloc(GJRtmpPull* pull){
    if (pull) {
        RTMP_Free(pull->rtmp);
        free(pull);
        GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Delloc:%p",pull);
    }else{
        GJLOG(GJ_LOGWARNING, "GJRtmpPull_Delloc NULL PULL");
    }
}
GVoid GJRtmpPull_Close(GJRtmpPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Close:%p",pull);
    pull->stopRequest = GTrue;

}
GVoid GJRtmpPull_Release(GJRtmpPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Release:%p",pull);
    pull->messageCallback = NULL;
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->releaseRequest = GTrue;
    if (pull->pullThread == NULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJRtmpPull_Delloc(pull);
    }
}
GVoid GJRtmpPull_CloseAndRelease(GJRtmpPull* pull){
    GJRtmpPull_Close(pull);
    GJRtmpPull_Release(pull);
}

GBool GJRtmpPull_StartConnect(GJRtmpPull* pull,PullDataCallback dataCallback,GHandle callbackParm,const GChar* pullUrl){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_StartConnect:%p",pull);

    if (pull->pullThread != NULL) {
        GJRtmpPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = GFalse;
    pull->dataCallback = dataCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);
    return GTrue;
}
GJTrafficUnit GJRtmpPull_GetVideoPullInfo(GJRtmpPull* pull){
    return pull->videoPullInfo;
}
GJTrafficUnit GJRtmpPull_GetAudioPullInfo(GJRtmpPull* pull){
    return pull->audioPullInfo;
}
