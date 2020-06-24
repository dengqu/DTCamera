//
//  audio_decoder.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/11.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef audio_decoder_h
#define audio_decoder_h

#include <stdio.h>

extern "C" {
    #include "libavformat/avformat.h"
    #include "libavcodec/avcodec.h"
    #include "libswresample/swresample.h"
    #include "libavutil/avutil.h"
}

typedef struct AudioPacket {
    static const int AUDIO_PACKET_ACTION_PLAY = 0;
    static const int AUDIO_PACKET_ACTION_PAUSE = 100;
    static const int AUDIO_PACKET_ACTION_SEEK = 101;

    short *buffer;
    int size;
    float position;
    int action;
    
    float extra_param1;
    float extra_param2;
    
    AudioPacket() {
        buffer = NULL;
        size = 0;
        position = -1;
        action = 0;
        extra_param1 = 0;
        extra_param2 = 0;
    }
    ~AudioPacket() {
        if (NULL != buffer) {
            delete[] buffer;
            buffer = NULL;
        }
    }
} AudioPacket;

#define OUT_PUT_CHANNELS 2
#define MIN(a, b)  (((a) < (b)) ? (a) : (b))

class AudioDecoder {
private:
    AVFormatContext *avFormatContext;
    AVCodecContext *avCodecContext;
    int stream_index;
    float timeBase;
    AVFrame *pAudioFrame;
    AVPacket packet;
    
    char* inputFilePath;
    
    int packetBufferSize;
    
    short *audioBuffer;
    float position;
    int audioBufferCursor;
    int audioBufferSize;
    float duration;
    bool isNeedFirstFrameCorrectFlag;
    float firstFrameCorrectionInSecs;
    
    SwrContext *swrContext;
    void *swrBuffer;
    int swrBufferSize;
    
    int init(const char* fileString);
    int readSamples(short* samples, int size);
    int readFrame();
    bool audioCodecIsSupported();
    
public:
    AudioDecoder();
    virtual ~AudioDecoder();
    
    virtual int getMusicMeta(const char* fileString, int *metaData);
    virtual void init(const char* fileString, int packetBufferSizeParam);
    virtual AudioPacket* decodePacket();
    virtual void destroy();
};

#endif /* audio_decoder_h */
