//
//  audio_encoder.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/5.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef audio_encoder_h
#define audio_encoder_h

#include <stdio.h>

extern "C" {
    #include "libavformat/avformat.h"
    #include "libavcodec/avcodec.h"
    #include "libswresample/swresample.h"
    #include "libavutil/channel_layout.h"
    #include "libavutil/avutil.h"
}

#ifndef PUBLISH_BITE_RATE
#define PUBLISH_BITE_RATE 64000
#endif

class AudioEncoder {
private:
    AVFormatContext *avFormatContext;
    AVCodecContext *avCodecContext;
    AVStream *audioStream;
    
    bool isWriteHeaderSuccess;
    double duration;
    
    AVFrame *input_frame;
    int buffer_size;
    uint8_t *samples;
    int samplesCursor;
    SwrContext *swrContext;
    uint8_t **convert_data;
    AVFrame *swrFrame;
    uint8_t *swrBuffer;
    int swrBufferSize;
    
    int publishBitRate;
    int audioChannels;
    int audioSampleRate;
    
    int totalSWRTimeMills;
    int totalEncodeTimeMills;
    
    int alloc_avframe();
    int alloc_audio_stream(const char *codec_name);
    void encodePacket();
    
    
public:
    AudioEncoder();
    virtual ~AudioEncoder();

    int init(int bitRate, int channels, int sampleRate, int bitsPerSample, const char* aacFilePath, const char* codec_name);
    int init(int bitRate, int channels, int bitsPerSample, const char* aacFilePath, const char* codec_name);
    void encode(uint8_t *buffer, int size);
    void destroy();
};

#endif /* audio_encoder_h */
