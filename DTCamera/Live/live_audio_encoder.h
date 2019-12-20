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
}

#ifndef PUBLISH_BITE_RATE
#define PUBLISH_BITE_RATE 64000
#endif

class LiveAudioEncoder {
private:
    AVCodecContext *avCodecContext;
    AVFrame *encode_frame;
    int64_t audio_next_pts;
    
    uint8_t **audio_samples_data;
    int audio_nb_samples;
    int audio_samples_size;
    int publishBitRate;
    int audioChannels;
    int audioSampleRate;
    
    int alloc_avframe();
    int alloc_audio_stream(const char *codec_name);
    
    typedef int (*fill_pcm_frame_callback)(int16_t *, int, int, double*, void *context);
    
    fill_pcm_frame_callback fillPCMFrameCallback;
    void *fillPCMFrameContext;
public:
    LiveAudioEncoder();
    virtual ~LiveAudioEncoder();
    
    int init(int bitRate, int channels, int sampleRate, const char *codec_name, int (*fill_pcm_frame_callback)(int16_t *, int, int, double*, void *context), void *context);
    int encode(LiveAudioPacket **audioPacket);
    void destroy();
};

#endif /* live_audio_encoder_h */
