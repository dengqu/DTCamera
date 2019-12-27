//
//  live_audio_encoder.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/19.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_audio_encoder.h"

LiveAudioEncoder::LiveAudioEncoder() {
}

LiveAudioEncoder::~LiveAudioEncoder() {
}

int LiveAudioEncoder::init(int bitRate, int channels, int sampleRate, const char *codec_name, int (*fill_pcm_frame_callback)(uint8_t *, int, int, double *, void *), void *context) {
    avCodecContext = NULL;
    audio_next_pts = 0.0;
    input_frame = NULL;
    samples = NULL;
    samplesCursor = 0;
    swrContext = NULL;
    swrFrame = NULL;
    swrBuffer = NULL;
    convert_data = NULL;
    this->publishBitRate = bitRate;
    this->audioChannels = channels;
    this->audioSampleRate = sampleRate;
    this->fillPCMFrameCallback = fill_pcm_frame_callback;
    this->fillPCMFrameContext = context;
    av_register_all(); // 注册所有可用的 muxer, demuxer 和 protocol
    this->alloc_audio_stream(codec_name);
    this->alloc_avframe();
    return 1;
}

int LiveAudioEncoder::encode(LiveAudioPacket **audioPacket) {
    double presentationTimeMills = -1;
    fillPCMFrameCallback(samples, buffer_size, audioChannels, &presentationTimeMills, fillPCMFrameContext);
    AVRational time_base = {1, audioSampleRate};
    int ret, got_packet;
    AVPacket pkt;
    av_init_packet(&pkt);
    AVFrame* encode_frame;
    if (swrContext) {
        swr_convert(swrContext, convert_data, avCodecContext->frame_size, (const uint8_t**)input_frame->data, avCodecContext->frame_size);
        int length = avCodecContext->frame_size * av_get_bytes_per_sample(avCodecContext->sample_fmt);
        for (int k = 0; k < 2; ++k) {
            for (int j = 0; j < length; ++j) {
                swrFrame->data[k][j] = convert_data[k][j];
            }
        }
        encode_frame = swrFrame;
    } else {
        encode_frame = input_frame;
    }
    encode_frame->pts = audio_next_pts;
    audio_next_pts += encode_frame->nb_samples;
    pkt.duration = (int)AV_NOPTS_VALUE;
    pkt.pts = pkt.dts = 0;
    ret = avcodec_encode_audio2(avCodecContext, &pkt, encode_frame, &got_packet); // 编码音频
    if (ret < 0 || !got_packet) {
        printf("Error encoding audio frame: %s\n", av_err2str(ret));
        av_free_packet(&pkt);
        return ret;
    }
    if (got_packet) {
        pkt.pts = av_rescale_q(encode_frame->pts, avCodecContext->time_base, time_base);
        (*audioPacket) = new LiveAudioPacket();
        (*audioPacket)->data = new byte[pkt.size];
        memcpy((*audioPacket)->data, pkt.data, pkt.size);
        (*audioPacket)->size = pkt.size;
        (*audioPacket)->position = (float)(pkt.pts * av_q2d(time_base) * 1000.0f);
    }
    av_free_packet(&pkt);
    return ret;
}

void LiveAudioEncoder::destroy() {
    printf("start destroy!!!\n");
    if (NULL != swrBuffer) {
        free(swrBuffer);
        swrBuffer = NULL;
        swrBufferSize = 0;
    }
    if (NULL != swrContext) {
        swr_free(&swrContext);
        swrContext = NULL;
    }
    if (convert_data) {
        av_freep(&convert_data[0]);
        free(convert_data);
    }
    if (NULL != swrFrame) {
        av_frame_free(&swrFrame);
    }
    if (NULL != samples) {
        av_freep(&samples);
    }
    if (NULL != input_frame) {
        av_frame_free(&input_frame);
    }
    if (NULL != avCodecContext) {
        avcodec_close(avCodecContext);
        av_free(avCodecContext);
    }
    printf("end destroy!!!\n");
}

int LiveAudioEncoder::alloc_audio_stream(const char *codec_name) {
    AVCodec *codec = avcodec_find_encoder_by_name(codec_name); // 寻找 encoder
    if (!codec) {
        printf("Couldn't find a valid audio codec\n");
        return -1;
    }
    AVSampleFormat preferedSampleFMT = AV_SAMPLE_FMT_S16;
    int preferedChannels = audioChannels;
    int preferedSampleRate = audioSampleRate;
    /*
     * 会将音频流或者视频流的信息填充好，分配出 AVStream 结构体，
     * 在音频流中分配声道、采样率、表示格式、编码器等信息，
     * 在视频流中分配宽、高、帧率、表示格式、编码器等信息。
     */
    avCodecContext = avcodec_alloc_context3(codec);
    avCodecContext->codec_type = AVMEDIA_TYPE_AUDIO; // 基本属性 - 音频类型
    avCodecContext->sample_rate = audioSampleRate; // 基本属性 - 采样率
    if (publishBitRate > 0) { // 基本属性 - 码率
        avCodecContext->bit_rate = publishBitRate;
    } else {
        avCodecContext->bit_rate = PUBLISH_BITE_RATE;
    }
    avCodecContext->sample_fmt = preferedSampleFMT; // 基本属性 - 量化格式
    printf("audioChannels is %d\n", audioChannels);
    avCodecContext->channel_layout = preferedChannels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO; // 基本属性 - 声道
    avCodecContext->channels = av_get_channel_layout_nb_channels(avCodecContext->channel_layout); // 基本属性 - 声道
    avCodecContext->profile = FF_PROFILE_AAC_LOW;
    printf("avCodecContext->channels is %d\n", avCodecContext->channels);
    avCodecContext->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    avCodecContext->codec_id = codec->id;
    
    if (codec->sample_fmts) {
        /* check if the prefered sample format for this codec is supported.
         * this is because, depending on the version of libav, and with the whole ffmpeg/libav fork situation,
         * you have various implementations around. float samples in particular are not always supported.
         */
        const enum AVSampleFormat *p = codec->sample_fmts;
        for (; *p != -1; p++) {
            if (*p == avCodecContext->sample_fmt) {
                break;
            }
        }
        if (*p == -1) {
            printf("sample format incompatible with codec. Defaulting to a format known to work\n");
            avCodecContext->sample_fmt = codec->sample_fmts[0];
        }
    }
    
    if (codec->supported_samplerates) {
        const int *p = codec->supported_samplerates;
        int best = 0;
        int best_dist = INT_MAX;
        for (; *p; p++) {
            int dist = abs(avCodecContext->sample_rate - *p);
            if (dist < best_dist) {
                best_dist = dist;
                best = *p;
            }
        }
        /* best is the closest supported sample rate (same as selected if best_dist == 0) */
        avCodecContext->sample_rate = best;
    }
    
    // 有些编码器只允许特定格式的 PCM 作为输入源，所以有时需要构造一个重采样器来将 PCM 数据转换为可适配编码器输入的 PCM 数据
    if (preferedChannels != avCodecContext->channels
        || preferedSampleRate != avCodecContext->sample_rate
        || preferedSampleFMT != avCodecContext->sample_fmt) {
        printf("channels is {%d, %d}\n", preferedChannels, avCodecContext->channels);
        printf("sample_rate is {%d, %d}\n", preferedSampleRate, avCodecContext->sample_rate);
        printf("sample_fmt is {%d, %d}\n", preferedSampleFMT, avCodecContext->sample_fmt);
        printf("AV_SAMPLE_FMT_S16P is %d AV_SAMPLE_FMT_S16 is %d AV_SAMPLE_FMT_FLTP is %d\n",
               AV_SAMPLE_FMT_S16P, AV_SAMPLE_FMT_S16, AV_SAMPLE_FMT_FLTP);
        swrContext = swr_alloc_set_opts(NULL,
                                        av_get_default_channel_layout(avCodecContext->channels),
                                        avCodecContext->sample_fmt,
                                        avCodecContext->sample_rate,
                                        av_get_default_channel_layout(preferedChannels),
                                        preferedSampleFMT,
                                        preferedSampleRate,
                                        0,
                                        NULL);
        if (!swrContext || swr_init(swrContext)) {
            if (swrContext) {
                swr_free(&swrContext);
            }
            return -1;
        }
    }
    if (avcodec_open2(avCodecContext, codec, NULL) < 0) {
        printf("Couldn't open codec\n");
        return -2;
    }
    avCodecContext->time_base.num = 1;
    avCodecContext->time_base.den = avCodecContext->sample_rate;
    avCodecContext->frame_size = 1024;
    return 0;
}

int LiveAudioEncoder::alloc_avframe() {
    int ret = 0;
    AVSampleFormat preferedSampleFMT = AV_SAMPLE_FMT_S16;
    int preferedChannels = audioChannels;
    int preferedSampleRate = audioSampleRate;
    input_frame = av_frame_alloc();
    if (!input_frame) {
        printf("Could not allocate audio frame\n");
        return -1;
    }
    input_frame->nb_samples = avCodecContext->frame_size;
    input_frame->format = preferedSampleFMT;
    input_frame->channel_layout = preferedChannels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
    input_frame->sample_rate = preferedSampleRate;
    buffer_size = av_samples_get_buffer_size(NULL, av_get_channel_layout_nb_channels(input_frame->channel_layout), input_frame->nb_samples, preferedSampleFMT, 0); // 计算公式 frame_size * sizeof(SInt16) * channels
    samples = (uint8_t*)av_malloc(buffer_size);
    samplesCursor = 0;
    if (!samples) {
        printf("Could not allocate %d bytes for samples buffer\n", buffer_size);
        return -2;
    }
    printf("allocate %d bytes for samples buffer\n", buffer_size);
    ret = avcodec_fill_audio_frame(input_frame, av_get_channel_layout_nb_channels(input_frame->channel_layout), preferedSampleFMT, samples, buffer_size, 0);
    if (ret < 0) {
        printf("Could not setup audio frame\n");
    }
    if (swrContext) {
        if (av_sample_fmt_is_planar(avCodecContext->sample_fmt)) {
            printf("Codec Context SampleFormat is Planar...\n");
        }
        convert_data = (uint8_t**)calloc(avCodecContext->channels, sizeof(*convert_data));
        av_samples_alloc(convert_data, NULL, avCodecContext->channels, avCodecContext->frame_size, avCodecContext->sample_fmt, 0);
        swrBufferSize = av_samples_get_buffer_size(NULL, avCodecContext->channels, avCodecContext->frame_size, avCodecContext->sample_fmt, 0);
        swrBuffer = (uint8_t*)av_malloc(swrBufferSize);
        printf("After av_malloc swrBuffer\n");
        swrFrame = av_frame_alloc();
        if (!swrFrame) {
            printf("Could not allocate swrFrame frame\n");
            return -1;
        }
        swrFrame->nb_samples = avCodecContext->frame_size;
        swrFrame->format = avCodecContext->sample_fmt;
        swrFrame->channel_layout = avCodecContext->channels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
        swrFrame->sample_rate = avCodecContext->sample_rate;
        ret = avcodec_fill_audio_frame(swrFrame, avCodecContext->channels, avCodecContext->sample_fmt, (uint8_t*)swrBuffer, swrBufferSize, 0);
        printf("After avcodec_fill_audio_frame\n");
        if (ret < 0) {
            printf("avcodec_fill_audio_frame error\n");
            return -1;
        }
    }
    return ret;
}
