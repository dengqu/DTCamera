//
//  live_audio_encoder.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/19.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_audio_encoder_h
#define live_audio_encoder_h
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "live_audio_packet_queue.h"

#ifndef UINT64_C
#define UINT64_C(value)__CONCAT(value,ULL)
#endif

extern "C" {
    #include "libavcodec/avcodec.h"
    #include "libavformat/avformat.h"
    #include "libavutil/avutil.h"
    #include "libavutil/samplefmt.h"
    #include "libavutil/common.h"
    #include "libavutil/channel_layout.h"
    #include "libavutil/opt.h"
    #include "libavutil/imgutils.h"
    #include "libavutil/mathematics.h"
};

#ifndef PUBLISH_BITE_RATE
#define PUBLISH_BITE_RATE 64000
#endif

class LiveAudioEncoder {
private:
    /** 音频流数据输出 **/
    AVCodecContext *                            avCodecContext;
    AVFrame *                                encode_frame;
    int64_t                                     audio_next_pts;

    uint8_t **                                audio_samples_data;
    int                                       audio_nb_samples;
    int                                         audio_samples_size;

    int                                         publishBitRate;
    int                                        audioChannels;
    int                                         audioSampleRate;

    //初始化的时候，要进行的工作
    int alloc_avframe();
    int alloc_audio_stream(const char * codec_name);

    /** 声明填充一帧PCM音频的方法 **/
    typedef int (*fill_pcm_frame_callback)(int16_t *, int, int, double*, void *context);

    /** 注册回调函数 **/
    fill_pcm_frame_callback                     fillPCMFrameCallback;
    void*                                     fillPCMFrameContext;
public:
    LiveAudioEncoder();
    virtual ~LiveAudioEncoder();

    int init(int bitRate, int channels, int sampleRate, const char * codec_name,
            int (*fill_pcm_frame_callback)(int16_t *, int, int, double*, void *context), void* context);
    int encode(LiveAudioPacket** audioPacket);
    void destroy();
};
#endif //AUDIO_ENCODER_H
