//
//  recording_publisher.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef recording_publisher_h
#define recording_publisher_h

#include "live_common.h"
#include "live_packet_pool.h"

extern "C" {
    #include "libavformat/avformat.h"
    #include "libavformat/avio.h"
    #include "libavcodec/avcodec.h"
    #include "libavutil/channel_layout.h"
    #include "libavutil/avutil.h"
    #include "libavutil/opt.h"
}

#define COLOR_FORMAT            AV_PIX_FMT_BGRA
#ifndef PUBLISH_DATA_TIME_OUT
#define PUBLISH_DATA_TIME_OUT 15 * 1000
#endif

#define AUDIO_QUEUE_ABORT_ERR_CODE               -100200
#define VIDEO_QUEUE_ABORT_ERR_CODE               -100201

#ifndef PUBLISH_INVALID_FLAG
#define PUBLISH_INVALID_FLAG -1
#endif

class RecordingPublisher {
public:
    RecordingPublisher();
    virtual ~RecordingPublisher();
    
    static int interrupt_cb(void *ctx);
    
    int detectTimeout();
    
    virtual int init(char *videoOutputURI,
                     int videoWidth, int videoHeight, int videoFrameRate, int videoBitRate,
                     int audioSampleRate, int audioChannels, int audioBitRate, char *audioCodecName);
    
    virtual void registerFillAACPacketCallback(int (*fill_aac_packet)(LiveAudioPacket **, void *context), void *context);
    virtual void registerFillVideoPacketCallback(int (*fill_packet_frame)(LiveVideoPacket **, void *context), void *context);
    virtual void registerPublishTimeoutCallback(int (*on_publish_timeout_callback)(void *context), void *context);
    
    int encode();
    
    virtual int stop();
    
    void interruptPublisherPipe() {
        this->publishTimeout = PUBLISH_INVALID_FLAG;
    }
    
    inline bool isInterrupted() {
        return this->publishTimeout == PUBLISH_INVALID_FLAG;
    }

    typedef int (*fill_aac_packet_callback)(LiveAudioPacket **, void *context);
    typedef int (*fill_h264_packet_callback)(LiveVideoPacket **, void *context);
    typedef int (*on_publish_timeout_callback)(void *context);
    
protected:
    virtual AVStream* add_stream(AVFormatContext *oc, AVCodec **codec, enum AVCodecID codecId, char *codecName);
    virtual int open_video(AVFormatContext *oc, AVCodec *codec, AVStream *st);
    int open_audio(AVFormatContext *oc, AVCodec *codec, AVStream *st);
    virtual int write_video_frame(AVFormatContext *oc, AVStream *st) = 0;
    virtual int write_audio_frame(AVFormatContext *oc, AVStream *st);
    virtual void close_video(AVFormatContext *oc, AVStream *st);
    void close_audio(AVFormatContext *oc, AVStream *st);
    virtual double getVideoStreamTimeInSecs() = 0;
    double getAudioStreamTimeInSecs();
    int buildVideoStream();
    int buildAudioStream(char *audioCodecName);
    
protected:
    // sps and pps data
    uint8_t *headerData;
    int headerSize;
    int publishTimeout;
    
    int startSendTime = 0;
    
    int interleavedWriteFrame(AVFormatContext *s, AVPacket *pkt);
    
    AVOutputFormat *fmt;
    AVFormatContext *oc;
    AVStream *video_st;
    AVStream *audio_st;
    AVBitStreamFilterContext *bsfc;
    double duration;
    
    double lastAudioPacketPresentationTimeMills;
    
    int videoWidth;
    int videoHeight;
    float videoFrameRate;
    int videoBitRate;
    int audioSampleRate;
    int audioChannels;
    int audioBitRate;
    
    fill_aac_packet_callback fillAACPacketCallback;
    void *fillAACPacketContext;
    fill_h264_packet_callback fillH264PacketCallback;
    void *fillH264PacketContext;
    on_publish_timeout_callback onPublishTimeoutCallback;
    void *timeoutContext;
    
    long sendLatestFrameTimemills; // 为了纪录发出的最后一帧的发送时间, 以便于判断超时
    bool isConnected;
    bool isWriteHeaderSuccess;
};

#endif /* recording_publisher_h */
