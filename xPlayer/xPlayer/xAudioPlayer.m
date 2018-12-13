//
//  xAudioPlayer.m
//  xPlayerDemo
//
//  Created by JSK on 2018/3/18.
//  Copyright © 2018年 JSK. All rights reserved.
//

#import "xAudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/time.h>

#define AUDIO_BUFFER_SAMPLES        2048
#define AUDIO_MAX_FRAME_SIZE        192000 // 1 second of 48khz 32bit audio
#define AUDIO_OUT_TO_FILE           0
#define AUDIO_PACKET_QUEUE_WARNING_SIZE     2048

#pragma mark - Packet Queue

typedef struct PacketQueue {
    AVPacketList    *first_pkt, *last_pkt;
    int             nb_packets;
    int             size;
    int             shouldQuit;
    pthread_mutex_t mutex;
    pthread_cond_t  cond;
} PacketQueue;


void packet_queue_init(PacketQueue *q) {
    memset(q, 0, sizeof(PacketQueue));
    pthread_mutex_init(&q->mutex, NULL);
    pthread_cond_init(&q->cond, NULL);
}

void packet_queue_clear(PacketQueue *q){
    AVPacketList *pkt1;
    pthread_mutex_lock(&q->mutex);
    while(q->nb_packets > 0){
        pkt1 = q->first_pkt;
        q->first_pkt = pkt1->next;
        if (!q->first_pkt)
            q->last_pkt = NULL;
        q->nb_packets--;
        q->size -= pkt1->pkt.size;
        AVPacket pkt = pkt1->pkt;
        if(pkt.data){
            av_free_packet(&pkt);
        }
        av_free(pkt1);
    }
    pthread_mutex_unlock(&q->mutex);
}

void packet_queue_dispose(PacketQueue *q){
    AVPacketList *pkt1;
    pthread_mutex_lock(&q->mutex);
    q->shouldQuit = 1;
    while(q->nb_packets > 0){
        pkt1 = q->first_pkt;
        q->first_pkt = pkt1->next;
        if (!q->first_pkt)
            q->last_pkt = NULL;
        q->nb_packets--;
        q->size -= pkt1->pkt.size;
        AVPacket pkt = pkt1->pkt;
        if(pkt.data){
            av_free_packet(&pkt);
        }
        av_free(pkt1);
    }
    pthread_cond_broadcast(&q->cond);
    pthread_mutex_unlock(&q->mutex);
    
    pthread_cond_destroy(&q->cond);
    pthread_mutex_destroy(&q->mutex);
    free(q);
}

int packet_queue_put(PacketQueue *q, AVPacket *pkt) {
    AVPacketList *pkt1;
    if(av_dup_packet(pkt) < 0) {
        return -1;
    }
    pkt1 = av_malloc(sizeof(AVPacketList));
    if (!pkt1)
        return -1;
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    
    pthread_mutex_lock(&q->mutex);
    if(q->shouldQuit){
        pthread_mutex_unlock(&q->mutex);
        av_free(pkt1);
        return -1;
    }
    if (!q->last_pkt)
        q->first_pkt = pkt1;
    else
        q->last_pkt->next = pkt1;
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size;
    pthread_cond_signal(&q->cond);
    
    pthread_mutex_unlock(&q->mutex);
    return 0;
}

int packet_queue_get(PacketQueue *q, AVPacket *pkt, int block) {
    
    AVPacketList *pkt1;
    int ret;
    
    pthread_mutex_lock(&q->mutex);
    for(;;) {
        if(q->shouldQuit){
            ret = -1;
            break;
        }
        pkt1 = q->first_pkt;
        if (pkt1) {
            q->first_pkt = pkt1->next;
            if (!q->first_pkt)
                q->last_pkt = NULL;
            q->nb_packets--;
            q->size -= pkt1->pkt.size;
            *pkt = pkt1->pkt;
            av_free(pkt1);
            ret = 1;
            break;
        } else if (!block) {
            ret = 0;
            break;
        } else {
            pthread_cond_wait(&q->cond, &q->mutex);
        }
    }
    pthread_mutex_unlock(&q->mutex);
    return ret;
}

#pragma mark - Audio Queue Service Context

static const int kNumberBuffers = 3;
typedef struct AudioQueueContext {
    AudioStreamBasicDescription   dataFormat;
    enum AVSampleFormat           sampleFmt;
    AudioQueueRef                 queue;
    AudioQueueBufferRef           buffers[kNumberBuffers];
    UInt32                        bufferByteSize;
} AudioQueueContext;

int aq_check_error(OSStatus error, const char *operation)
{
    if (error == noErr) return 0;
    
    char str[20];
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    
    fprintf(stderr, "Error: %s (%s)\n", operation, str);
    return -1;
}

void aq_init(AudioQueueContext *pCtx){
    memset(pCtx, 0, sizeof(AudioQueueContext));
}

void aq_dispose(AudioQueueContext *pCtx){
    OSStatus status = AudioQueueStop(pCtx->queue, true);
    aq_check_error(status, "AudioQueueStop()");
    status = AudioQueueDispose(pCtx->queue, true);
    aq_check_error(status, "AudioQueueDispose()");
    free(pCtx);
}

#pragma mark - Task Killer

typedef struct xTaskKillerContext {
    int                 taskStaus; //0:notStart 1:executing 2:finished
    int                 waitSecs;
    void                *data;
    void                (*kill_func)(void*);
    pthread_t           thread;
    pthread_mutex_t     mutex;
    pthread_cond_t      cond;
} xTaskKillerContext;

void x_taskKiller_init(xTaskKillerContext *pTK, long int waitSecs, void(*kill_func)(void*), void *data){
    pthread_mutex_init(&pTK->mutex, NULL);
    pthread_cond_init(&pTK->cond, NULL);
    pTK->waitSecs = waitSecs;
    pTK->data = data;
    pTK->kill_func = kill_func;
}

void* _x_taskKiller_start(void *data){
    xTaskKillerContext *pTK = data;
    pthread_mutex_lock(&pTK->mutex);
    if(pTK->taskStaus == 2){
        // 任务已完成，不必kill了
        pthread_mutex_unlock(&pTK->mutex);
        pthread_mutex_destroy(&pTK->mutex);
        pthread_cond_destroy(&pTK->cond);
        free(pTK);
        return NULL;
    }
    
    struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + pTK->waitSecs;
    ts.tv_nsec = tv.tv_usec * 1000;
    if (ts.tv_nsec > 1000000000) {
        ts.tv_sec += 1;
        ts.tv_nsec -= 1000000000;
    }
    pthread_cond_timedwait(&pTK->cond, &pTK->mutex, &ts);
    if(pTK->taskStaus != 2){
        pTK->kill_func(pTK->data);
    }
    pthread_mutex_unlock(&pTK->mutex);
    pthread_mutex_destroy(&pTK->mutex);
    pthread_cond_destroy(&pTK->cond);
    free(pTK);
    return NULL;
}

void x_taskKiller_start(xTaskKillerContext *pTK){
    pthread_create(&pTK->thread, NULL, _x_taskKiller_start, pTK);
}

void x_taskKiller_cancel(xTaskKillerContext *pTK){
    pthread_mutex_lock(&pTK->mutex);
    pTK->taskStaus = 2;
    pthread_cond_signal(&pTK->cond);
    pthread_mutex_unlock(&pTK->mutex);
}

#pragma mark - Core Logic

typedef enum xAudioPlayerStatus {
    X_AUDIO_NONE = 0,
    X_AUDIO_INIT = 1,
    X_AUDIO_LOADING = 2,
    X_AUDIO_PLAYING = 3,
    X_AUDIO_STOP = 5,
    X_AUDIO_ERROR = 6
} xAudioPlayerStatus;

typedef struct xAudioReadContext xAudioReadContext;

typedef struct xAudioPlayerContext {
    char                url[1000];
    char                outFolderPath[950];
    AVFormatContext     *pFormatCtx;
    int                 audioStreamIndex;
    AVCodecContext      *pCodecCtx;
    xAudioReadContext   *pReadCtx;
    AudioQueueContext   *pAQCtx;            //ios Audio Queue Service Data
    xAudioPlayerStatus  status;
    char                errorMsg[1000];     //if status == X_AUDIO_ERROR, here is the error message
    int                 isTimeout;
    pthread_t           startThread;
    pthread_t           readThread;
    pthread_t           stopThread;
    pthread_t           disposeThread;
    pthread_mutex_t     mutex;
    pthread_mutex_t     statusMutex;
    pthread_cond_t      statusCond;
} xAudioPlayerContext;


struct xAudioReadContext{
    int                 shouldQuit;
    FILE                *pOutFile;         //audio pcm file for debug
    PacketQueue         *pPacketQueue;
    xAudioPlayerContext *pCtx;
};


int xa_init(xAudioPlayerContext *pCtx, char *url, char *outFileFolder){
    
    if(strlen(url) + 1 > sizeof(pCtx->url)){
        printf("input url too long\n");
        return -1;
    }
    if(strlen(outFileFolder) + 1 > sizeof(pCtx->outFolderPath)){
        printf("audio out folder path too long\n");
        return -1;
    }
    memset(pCtx, 0, sizeof(xAudioPlayerContext));
    
    strcpy(pCtx->url, url);
    if(outFileFolder != NULL){
        strcpy(pCtx->outFolderPath, outFileFolder);
    }
    
    pCtx->audioStreamIndex = -1;
    pCtx->status = X_AUDIO_INIT;
    pthread_mutex_init(&pCtx->mutex, NULL);
    pthread_mutex_init(&pCtx->statusMutex, NULL);
    pthread_cond_init(&pCtx->statusCond, NULL);
    return 0;
}

void* xa_dispose(void *data){
    
    xAudioPlayerContext *pCtx = data;
    //****************************************************
    pthread_mutex_lock(&pCtx->mutex);
    
    if(pCtx->pReadCtx != NULL){
        pCtx->pReadCtx->shouldQuit = 1;
        pCtx->pReadCtx = NULL;
    }
    
    if(pCtx->pAQCtx != NULL){
        aq_dispose(pCtx->pAQCtx);
        pCtx->pAQCtx = NULL;
    }
    
    if(pCtx->pCodecCtx != NULL){
        avcodec_close(pCtx->pCodecCtx);
        pCtx->pCodecCtx = NULL;
    }
    
    if(pCtx->pFormatCtx != NULL){
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
    }
    
    pCtx->status = X_AUDIO_NONE;
    pthread_cond_broadcast(&pCtx->statusCond);
    
    pthread_mutex_unlock(&pCtx->mutex);
    //****************************************************
    
    pthread_cond_broadcast(&pCtx->statusCond);
    
    pthread_cond_destroy(&pCtx->statusCond);
    pthread_mutex_destroy(&pCtx->statusMutex);
    pthread_mutex_destroy(&pCtx->mutex);
    free(pCtx);
    return NULL;
}

void* xa_stop(void *data){
    xAudioPlayerContext *pCtx = data;
    if(pCtx->status != X_AUDIO_PLAYING){
        return NULL;
    }
    //****************************************************
    pthread_mutex_lock(&pCtx->mutex);
    if(pCtx->status != X_AUDIO_PLAYING){
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    if(pCtx->pReadCtx != NULL){
        pCtx->pReadCtx->shouldQuit = 1;
        pCtx->pReadCtx = NULL;
    }
    
    if(pCtx->pAQCtx != NULL){
        aq_dispose(pCtx->pAQCtx);
        pCtx->pAQCtx = NULL;
    }
    
    if(pCtx->pCodecCtx != NULL){
        avcodec_close(pCtx->pCodecCtx);
        pCtx->pCodecCtx = NULL;
    }
    
    if(pCtx->pFormatCtx != NULL){
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
    }
    
    pCtx->status = X_AUDIO_STOP;
    pthread_cond_broadcast(&pCtx->statusCond);
    
    pthread_mutex_unlock(&pCtx->mutex);
    //****************************************************
    return NULL;
}

enum AVSampleFormat xa_get_support_sampleFmt(enum AVSampleFormat fmt){
    switch (fmt) {
        case AV_SAMPLE_FMT_U8:          ///< unsigned 8 bits
            return AV_SAMPLE_FMT_U8;
        case AV_SAMPLE_FMT_S16:         ///< signed 16 bits
            return AV_SAMPLE_FMT_S16;
        case AV_SAMPLE_FMT_S32:         ///< signed 32 bits
            return AV_SAMPLE_FMT_S32;
        case AV_SAMPLE_FMT_FLT:         ///< float
            return AV_SAMPLE_FMT_FLT;
        case AV_SAMPLE_FMT_DBL:         ///< double
            return AV_SAMPLE_FMT_FLT;
        case AV_SAMPLE_FMT_U8P:         ///< unsigned 8 bits, planar
            return AV_SAMPLE_FMT_U8;
        case AV_SAMPLE_FMT_S16P:        ///< signed 16 bits, planar
            return AV_SAMPLE_FMT_S16;
        case AV_SAMPLE_FMT_S32P:        ///< signed 32 bits, planar
            return AV_SAMPLE_FMT_S32;
        case AV_SAMPLE_FMT_FLTP:        ///< float, planar
            return AV_SAMPLE_FMT_FLT;
        case AV_SAMPLE_FMT_DBLP:        ///< double, planar
            return AV_SAMPLE_FMT_FLT;
        default:
            return AV_SAMPLE_FMT_S16;
    }
}

int xa_get_sampleFmt_byteSize (enum AVSampleFormat fmt){
    switch (fmt) {
        case AV_SAMPLE_FMT_U8:          ///< unsigned 8 bits
            return 1;
        case AV_SAMPLE_FMT_S16:         ///< signed 16 bits
            return 2;
        case AV_SAMPLE_FMT_S32:         ///< signed 32 bits
            return 4;
        case AV_SAMPLE_FMT_FLT:         ///< float
            return 4;
        case AV_SAMPLE_FMT_DBL:         ///< double
            return 8;
        case AV_SAMPLE_FMT_U8P:         ///< unsigned 8 bits, planar
            return 1;
        case AV_SAMPLE_FMT_S16P:        ///< signed 16 bits, planar
            return 2;
        case AV_SAMPLE_FMT_S32P:        ///< signed 32 bits, planar
            return 4;
        case AV_SAMPLE_FMT_FLTP:        ///< float, planar
            return 4;
        case AV_SAMPLE_FMT_DBLP:        ///< double, planar
            return 8;
        default:
            return 2;
    }
}

AudioFormatFlags xa_get_audioFmtFlags (enum AVSampleFormat fmt){
    AudioFormatFlags flags = kLinearPCMFormatFlagIsPacked;
    switch(fmt){
        case AV_SAMPLE_FMT_S16:
        case AV_SAMPLE_FMT_S32:
            flags |= kLinearPCMFormatFlagIsSignedInteger;
            break;
        case AV_SAMPLE_FMT_FLT:
            flags |= kAudioFormatFlagIsFloat;
            break;
        default:
            break;
    }
    return flags;
}

// 对av_read_frame不起作用，不知为何
int xa_interrupt_callback(void *data) {
    printf("xa_interrupt\n");
    xAudioPlayerContext *pCtx = data;
    if(pCtx->isTimeout == 1){
        return 1;
    }
    else{
        return 0;
    }
}

void xa_kill_read(void *data){
    // av_read_frame 长时间不反回的情况下触发，但找不到kill它的方法
    printf("xa_kill_read\n");
    xAudioPlayerContext *pCtx = data;
    pCtx->isTimeout = 1;
}

void* xa_read(void *data){
    
    xAudioReadContext *pReadCtx = (xAudioReadContext *)data;
    xAudioPlayerContext *pCtx = pReadCtx->pCtx;
    
    FILE *pOutFile = NULL;
    #if AUDIO_OUT_TO_FILE
    char fileName[50];
    sprintf(fileName, "/audio_out_%d.pcm", rand() % 100000);
    char* outFilePath = strcat(playerCtx->outFolderPath, fileName);
    pOutFile = fopen(outFilePath, "wb");
    if(pOutFile == NULL){
        printf("Couldn't open audio out file.\n");
    }
    #endif
    
    pReadCtx->pOutFile = pOutFile;
    
    AVPacket    packet;
    while(!pReadCtx->shouldQuit){
        //****************************************************
        pthread_mutex_lock(&pCtx->mutex);
        if(pReadCtx->shouldQuit){
            pthread_mutex_unlock(&pCtx->mutex);
            break;
        }
        // 引入Task Killer 来对付断网时 av_read_frame 长时间不反回的问题
        xTaskKillerContext *pTK = malloc(sizeof(xTaskKillerContext));
        x_taskKiller_init(pTK, 10, xa_kill_read, pCtx); //10秒后av_read_frame不反回，调用xa_kill_read
        x_taskKiller_start(pTK);
        //printf("av_read_frame\n");
        int ret = av_read_frame(pCtx->pFormatCtx, &packet);   //核心语句，读取packet
        x_taskKiller_cancel(pTK);
        pthread_mutex_unlock(&pCtx->mutex);
        //****************************************************
        if(ret < 0 || pReadCtx->shouldQuit){
            printf("av_read_frame return < 0, will stop.\n");
            break;
        }
        if(packet.stream_index == pCtx->audioStreamIndex) {
            packet_queue_put(pReadCtx->pPacketQueue, &packet);
            if(pReadCtx->pPacketQueue->nb_packets >= AUDIO_PACKET_QUEUE_WARNING_SIZE){
                usleep(50 * 1000); //wait 50 milliseconds
            }
            //printf("queue size:%d\n", pReadCtx->pPacketQueue->nb_packets);
        } else {
            av_free_packet(&packet);
        }
    }
    // 读取结束，stop
    if(pReadCtx->pCtx->status == X_AUDIO_PLAYING){
        xa_stop(pReadCtx->pCtx);
    }
    // 清理资源
    if(pReadCtx->pOutFile != NULL){
        fclose(pReadCtx->pOutFile);
        pReadCtx->pOutFile = NULL;
    }
    packet_queue_dispose(pReadCtx->pPacketQueue);
    pReadCtx->pPacketQueue = NULL;
    free(pReadCtx);
    
    return NULL;
}

//ret > 0: 正常
//ret < 0: should quit
int xa_decode_frame(xAudioReadContext *pReadCtx, uint8_t *audio_buf, int buf_size) {
    static AVPacket pkt;
    static uint8_t *audio_pkt_data = NULL;
    static int audio_pkt_size = 0;
    static AVFrame frame;
    
    xAudioPlayerContext *pCtx = pReadCtx->pCtx;
    int len1, data_size = 0;
    
    for(;;) {
        while(audio_pkt_size > 0) {
            int got_frame = 0;
            //****************************************************
            if(pReadCtx->shouldQuit){
                av_free_packet(&pkt);
                return -1;
            }
            len1 = avcodec_decode_audio4(pCtx->pCodecCtx, &frame, &got_frame, &pkt);
            //****************************************************
            if(len1 < 0) {
                /* if error, skip frame */
                audio_pkt_size = 0;
                break;
            }
            audio_pkt_data += len1;
            audio_pkt_size -= len1;
            data_size = 0;
            if(got_frame) {
                
                //****************************************************
                if(pReadCtx->shouldQuit){
                    av_free_packet(&pkt);
                    return -1;
                }
                //Out Audio Param
                int out_channels = (int)pCtx->pAQCtx->dataFormat.mChannelsPerFrame;
                uint64_t out_channel_layout = av_get_default_channel_layout(out_channels);
                enum AVSampleFormat out_sample_fmt = pCtx->pAQCtx->sampleFmt;
                int out_sample_rate = (int)pCtx->pAQCtx->dataFormat.mSampleRate;
                
                //Output audio data with out format to buffer
                struct SwrContext *au_convert_ctx = swr_alloc();
                au_convert_ctx = swr_alloc_set_opts(au_convert_ctx, out_channel_layout, out_sample_fmt, out_sample_rate,
                                                    pCtx->pCodecCtx->channel_layout, pCtx->pCodecCtx->sample_fmt , pCtx->pCodecCtx->sample_rate,0, NULL);
                //****************************************************
                swr_init(au_convert_ctx);
                int out_nb_samples = swr_convert(au_convert_ctx, &audio_buf, AUDIO_MAX_FRAME_SIZE, (const uint8_t **)frame.data, frame.nb_samples);
                swr_free(&au_convert_ctx);
                
                //Out Audio Size
                data_size = av_samples_get_buffer_size(NULL, out_channels, out_nb_samples, out_sample_fmt, 1);
                
            }
            if(data_size <= 0) {
                /* No data yet, get more frames */
                continue;
            }
            /* We have data, return it and come back for more later */
            return data_size;
        }
        if(pkt.data){
            av_free_packet(&pkt);
        }
        if(pReadCtx->shouldQuit){
            return -1;
        }
        if(packet_queue_get(pReadCtx->pPacketQueue, &pkt, 1) < 0) {
            return -1;
        }
        audio_pkt_data = pkt.data;
        audio_pkt_size = pkt.size;
    }
}

void xa_fill_buffer(void *data, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    
    //printf("xa_fill_buffer\n");
    xAudioReadContext *pReadCtx = (xAudioReadContext*)data;
    xAudioPlayerContext *pCtx = pReadCtx->pCtx;
    
    uint8_t *stream = inBuffer->mAudioData;
    //****************************************************
    if(pReadCtx->shouldQuit){
        return;
    }
    int len = pCtx->pAQCtx->bufferByteSize;
    //****************************************************
    int readLen = 0;
    int len1;
    int ret = 0;
    static uint8_t audio_buf[(AUDIO_MAX_FRAME_SIZE * 3) / 2];
    static unsigned int audio_buf_size = 0;
    static unsigned int audio_buf_index = 0;
    
    while(len > 0 && !pReadCtx->shouldQuit) {
        if(audio_buf_index >= audio_buf_size) {
            /* We have already sent all our data; get more */
            ret = xa_decode_frame(pReadCtx, audio_buf, sizeof(audio_buf));
            if(ret < 0){
                /* should quit */
                break;
            }
            audio_buf_size = ret;
            audio_buf_index = 0;
        }
        len1 = audio_buf_size - audio_buf_index;
        if(len1 > len)
            len1 = len;
        //****************************************************
        if(pReadCtx->shouldQuit){
            break;
        }
        memcpy(stream, (uint8_t *)audio_buf + audio_buf_index, len1);
        //****************************************************
        //Write PCM
        #if AUDIO_OUT_TO_FILE
        if(ctx->pOutFile != NULL){
            fwrite((uint8_t *)audio_buf + audio_buf_index, 1, len1, ctx->pOutFile);
        }
        #endif
        len -= len1;
        stream += len1;
        audio_buf_index += len1;
        readLen += len1;
    }
    //****************************************************
    if(!pReadCtx->shouldQuit){
        inBuffer->mAudioDataByteSize = readLen;
        AudioQueueEnqueueBuffer(pCtx->pAQCtx->queue, inBuffer, 0, NULL);
    }
    //****************************************************
}

void* xa_start(void *data){
    xAudioPlayerContext *pCtx = data;
    if(pCtx->status != X_AUDIO_INIT && pCtx->status != X_AUDIO_STOP && pCtx->status != X_AUDIO_ERROR){
        return NULL;
    }
    //****************************************************
    pthread_mutex_lock(&pCtx->mutex);  //后面所有分支return前都要调 pthread_mutex_unlock(&ctx->mutex);
    
    if(pCtx->status != X_AUDIO_INIT && pCtx->status != X_AUDIO_STOP && pCtx->status != X_AUDIO_ERROR){
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    pCtx->status = X_AUDIO_LOADING;
    pthread_cond_broadcast(&pCtx->statusCond);
    
    // Register all formats and codecs
    av_register_all();
    avformat_network_init();
    
//    AVDictionary *opts = 0;
//    av_dict_set(&opts, "timeout", "1000", 0); // in ms
    
    // Open Input
    if(avformat_open_input(&pCtx->pFormatCtx, pCtx->url, NULL, NULL) != 0){
        if(pCtx->pFormatCtx != NULL){
            avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        }
        strcpy(pCtx->errorMsg, "Couldn't open input stream.");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    // Interrupt callback
    AVIOInterruptCB icb = { xa_interrupt_callback, pCtx };
    pCtx->pFormatCtx->interrupt_callback = icb;
    
    // Retrieve stream information
    if(avformat_find_stream_info(pCtx->pFormatCtx, NULL) < 0){
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        strcpy(pCtx->errorMsg, "Couldn't find stream information.");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    // Dump information about file onto standard error
    av_dump_format(pCtx->pFormatCtx, 0, pCtx->url, 0);
    
    // Find the audio stream
    pCtx->audioStreamIndex = -1;
    for(int i = 0; i < pCtx->pFormatCtx->nb_streams; i++) {
        if(pCtx->pFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
            pCtx->audioStreamIndex = i;
        }
    }
    if(pCtx->audioStreamIndex == -1){
        printf("Couldn't find audio stream.\n");
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        strcpy(pCtx->errorMsg, "Couldn't find audio stream.");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    AVCodecContext *pCodecCtxOrig = pCtx->pFormatCtx->streams[pCtx->audioStreamIndex]->codec;
    AVCodec *pCodec = avcodec_find_decoder(pCodecCtxOrig->codec_id);
    if(!pCodec) {
        avcodec_close(pCodecCtxOrig);
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        strcpy(pCtx->errorMsg, "Unsupported codec!");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    // Copy context
    AVCodecContext *pCodecCtx = avcodec_alloc_context3(pCodec);
    if(avcodec_copy_context(pCodecCtx, pCodecCtxOrig) != 0) {
        free(pCodecCtx);
        avcodec_close(pCodecCtxOrig);
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        strcpy(pCtx->errorMsg, "Couldn't copy codec context");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    avcodec_close(pCodecCtxOrig);
    
    if(avcodec_open2(pCodecCtx, pCodec, NULL) != 0){
        avcodec_close(pCodecCtx);
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        strcpy(pCtx->errorMsg, "Couldn't open codec");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    pCtx->pCodecCtx = pCodecCtx;
    
    xAudioReadContext *pReadCtx = malloc(sizeof(xAudioReadContext));
    pReadCtx->pCtx = pCtx;
    PacketQueue *pPacketQueue = malloc(sizeof(PacketQueue));
    packet_queue_init(pPacketQueue);
    pReadCtx->pPacketQueue = pPacketQueue;
    pCtx->pReadCtx = pReadCtx;
    
    // 启动读线程
    pthread_create(&pCtx->readThread, NULL, xa_read, pReadCtx);
    
    // 启动播放组件
    AudioQueueContext *pAQCtx = malloc(sizeof(AudioQueueContext));
    pAQCtx->sampleFmt = xa_get_support_sampleFmt(pCodecCtx->sample_fmt);
    pAQCtx->dataFormat.mSampleRate = pCodecCtx->sample_rate;
    pAQCtx->dataFormat.mFormatID = kAudioFormatLinearPCM;
    pAQCtx->dataFormat.mFormatFlags = xa_get_audioFmtFlags(pAQCtx->sampleFmt);
    pAQCtx->dataFormat.mBitsPerChannel = 8 * xa_get_sampleFmt_byteSize(pAQCtx->sampleFmt);
    pAQCtx->dataFormat.mChannelsPerFrame = pCodecCtx->channels;
    pAQCtx->dataFormat.mBytesPerFrame = pCodecCtx->channels * xa_get_sampleFmt_byteSize(pAQCtx->sampleFmt);
    pAQCtx->dataFormat.mFramesPerPacket = 1;
    pAQCtx->dataFormat.mBytesPerPacket = pAQCtx->dataFormat.mFramesPerPacket * pAQCtx->dataFormat.mBytesPerFrame;
    pAQCtx->dataFormat.mReserved = 0;
    pAQCtx->bufferByteSize = AUDIO_BUFFER_SAMPLES * pAQCtx->dataFormat.mBytesPerFrame;
    pCtx->pAQCtx = pAQCtx;
    
    AudioQueueNewOutput(&pAQCtx->dataFormat,
                        xa_fill_buffer,
                        pReadCtx,   //fill 和 read 的参数一致
                        NULL,
                        NULL,
                        0,
                        &pAQCtx->queue);
    
    AudioQueueSetParameter(pAQCtx->queue, kAudioQueueParam_Volume, 1);
    
    for(int i = 0; i < kNumberBuffers; ++i) {
        AudioQueueAllocateBuffer(pAQCtx->queue, pAQCtx->bufferByteSize, &pAQCtx->buffers[i]);
    }
    
    OSStatus status = AudioQueueStart(pAQCtx->queue, NULL);
    if(aq_check_error(status, "AudioQueueStart()") != 0){
        
        aq_dispose(pCtx->pAQCtx);
        pCtx->pAQCtx = NULL;
        
        pCtx->pReadCtx->shouldQuit = 1;
        pCtx->pReadCtx = NULL;
        
        avcodec_close(pCtx->pCodecCtx);
        pCtx->pCodecCtx = NULL;
        
        avformat_close_input(&pCtx->pFormatCtx); //will set pFormatCtx to NULL
        
        strcpy(pCtx->errorMsg, "Couldn't start Audio Queue Service");
        pCtx->status = X_AUDIO_ERROR;
        pthread_cond_broadcast(&pCtx->statusCond);
        
        pthread_mutex_unlock(&pCtx->mutex);
        return NULL;
    }
    
    pCtx->status = X_AUDIO_PLAYING;
    pthread_cond_broadcast(&pCtx->statusCond);
    
    pthread_mutex_unlock(&pCtx->mutex);
    //****************************************************
    
    for(int i = 0; i < kNumberBuffers; ++i) {
        // 必须先fill一次，或者清零
        xa_fill_buffer(pReadCtx, pAQCtx->queue, pAQCtx->buffers[i]);
    }
    return NULL;
}

#pragma mark - Objc Demo

@interface xAudioPlayer(){
    xAudioPlayerContext     *pCtx;
}
@end

@implementation xAudioPlayer

-(instancetype)initWithUrl:(NSString*)url{
    self = [super init];
    if(!self)
        return nil;
    _url = url;
    NSString *docFolderPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    pCtx = malloc(sizeof(xAudioPlayerContext));
    xa_init(pCtx, (char*)[url UTF8String], (char *)[docFolderPath UTF8String]);
    _state = [self adaptState:pCtx->status];
    
    //start status monitor
    __weak typeof(self) weak = self;
    xAudioPlayerContext *_pCtx = pCtx;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        pthread_mutex_lock(&_pCtx->statusMutex);
        while(true){
            pthread_cond_wait(&_pCtx->statusCond, &_pCtx->statusMutex);
            xAudioPlayerStatus status = _pCtx->status;
            if(status == X_AUDIO_NONE){
                // has disposed
                break;
            }
            [weak handleStatuschange:status];
        }
        pthread_mutex_unlock(&_pCtx->statusMutex);
    });
    return self;
}

-(void)handleStatuschange:(xAudioPlayerStatus)status{
    xAudioState newState = [self adaptState:status];
    if(status == X_AUDIO_ERROR && strlen(pCtx->errorMsg) > 0){
        _errorMsg = [NSString stringWithUTF8String:pCtx->errorMsg];
    }
    else{
        _errorMsg = nil;
    }
    if(newState != self.state){
        _state = newState;
        if(self.delegate){
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate onStateChanged:newState];
            });
        }
    }
}

-(xAudioState)adaptState:(xAudioPlayerStatus)status{
    switch(status){
        case X_AUDIO_NONE:
        case X_AUDIO_INIT:
            return xAudioStateNone;
        case X_AUDIO_LOADING:
            return xAudioStateLoading;
        case X_AUDIO_PLAYING:
            return xAudioStatePlaying;
        case X_AUDIO_STOP:
            return xAudioStateStopped;
        case X_AUDIO_ERROR:
            return xAudioStateError;
    }
}

-(void)play{
    pthread_create(&pCtx->startThread, NULL, xa_start, pCtx);
}

-(void)stop{
    pthread_create(&pCtx->stopThread, NULL, xa_stop, pCtx);
}

-(void)dealloc{
    pthread_create(&pCtx->disposeThread, NULL, xa_dispose, pCtx);
    pCtx = NULL;
}

@end
