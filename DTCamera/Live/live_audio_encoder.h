//
//  live_audio_encoder.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/19.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_audio_encoder_h
#define live_audio_encoder_h

#include "live_common.h"
#include "live_audio_packet_queue.h"

extern "C" {
    #include "libavformat/avformat.h"
    #include "libavcodec/avcodec.h"
    #include "libswresample/swresample.h"
}

#ifndef PUBLISH_BITE_RATE
#define PUBLISH_BITE_RATE 64000
#endif

class LiveAudioEncoder {
private:
    AVCodecContext *avCodecContext;
        
    int64_t audio_next_pts;
    
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
    
    int alloc_avframe();
    int alloc_audio_stream(const char *codec_name);
    
    typedef int (*fill_pcm_frame_callback)(uint8_t *, int, int, double*, void *context);
    
    fill_pcm_frame_callback fillPCMFrameCallback;
    void *fillPCMFrameContext;
public:
    LiveAudioEncoder();
    virtual ~LiveAudioEncoder();
    
    int init(int bitRate, int channels, int sampleRate, const char *codec_name, int (*fill_pcm_frame_callback)(uint8_t *, int, int, double*, void *context), void *context);
    int encode(LiveAudioPacket **audioPacket);
    void destroy();
};

#endif /* live_audio_encoder_h */
