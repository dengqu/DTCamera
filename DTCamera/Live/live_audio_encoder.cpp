//
//  live_audio_encoder.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/19.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_audio_encoder.h"

LiveAudioEncoder::LiveAudioEncoder() {
    encode_frame = NULL;
    avCodecContext = NULL;
    audio_next_pts = 0.0;
}

LiveAudioEncoder::~LiveAudioEncoder() {
}

int LiveAudioEncoder::init(int bitRate, int channels, int sampleRate, const char *codec_name, int (*fill_pcm_frame_callback)(int16_t *, int, int, double *, void *), void *context) {
    this->publishBitRate = bitRate;
    this->audioChannels = channels;
    this->audioSampleRate = sampleRate;
    this->fillPCMFrameCallback = fill_pcm_frame_callback;
    this->fillPCMFrameContext = context;
    av_register_all();
    this->alloc_audio_stream(codec_name);
    this->alloc_avframe();
    return 1;
}

int LiveAudioEncoder::encode(LiveAudioPacket **audioPacket) {
    double presentationTimeMills = -1;
    int actualFillSampleSize = fillPCMFrameCallback((int16_t *)audio_samples_data[0], audio_nb_samples, audioChannels, &presentationTimeMills, fillPCMFrameContext);
    printf("fillPCMFrameCallback: %d\n", sizeof(audio_samples_data[0]));
    if (actualFillSampleSize == -1) {
        printf("fillPCMFrameCallback failed return actualFillSampleSize is %d \n", actualFillSampleSize);
        return -1;
    }
    if (actualFillSampleSize == 0) {
        return -1;
    }
    int actualFillFrameNum = actualFillSampleSize / audioChannels;
    int audioSamplesSize = actualFillFrameNum * audioChannels * sizeof(short);
    AVRational time_base = {1, audioSampleRate};
    int ret;
    AVPacket pkt = {0};
    int got_packet;
    av_init_packet(&pkt);
    pkt.duration = (int)AV_NOPTS_VALUE;
    pkt.pts = pkt.dts = 0;
    encode_frame->nb_samples = actualFillFrameNum;
    avcodec_fill_audio_frame(encode_frame, avCodecContext->channels, avCodecContext->sample_fmt, audio_samples_data[0], audioSamplesSize, 0);
    encode_frame->pts = audio_next_pts;
    audio_next_pts += encode_frame->nb_samples;
    ret = avcodec_encode_audio2(avCodecContext, &pkt, encode_frame, &got_packet);
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
    if (NULL != audio_samples_data[0]) {
        av_free(audio_samples_data[0]);
    }
    if (NULL != encode_frame) {
        av_free(encode_frame);
    }
    if (NULL != avCodecContext) {
        avcodec_close(avCodecContext);
        av_free(avCodecContext);
    }
    printf("end destroy!!!\n");
}

int LiveAudioEncoder::alloc_audio_stream(const char *codec_name) {
    AVCodec *codec = avcodec_find_encoder_by_name(codec_name);
    if (!codec) {
        printf("Couldn't find a valid audio codec By Codec Name %s\n", codec_name);
        return -1;
    }
    avCodecContext = avcodec_alloc_context3(codec);
    avCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
    avCodecContext->sample_rate = audioSampleRate;
    if (publishBitRate > 0) {
        avCodecContext->bit_rate = publishBitRate;
    } else {
        avCodecContext->bit_rate = PUBLISH_BITE_RATE;
    }
    avCodecContext->sample_fmt = AV_SAMPLE_FMT_S16;
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
    printf("audioChannels is %d\n", audioChannels);
    printf("AV_SAMPLE_FMT_S16 is %d\n", AV_SAMPLE_FMT_S16);
    avCodecContext->channel_layout = audioChannels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
    avCodecContext->channels = av_get_channel_layout_nb_channels(avCodecContext->channel_layout);
    avCodecContext->profile = FF_PROFILE_AAC_LOW;
    printf("avCodecContext->channels is %d\n", avCodecContext->channels);
    avCodecContext->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    avCodecContext->codec_id = codec->id;
    if (avcodec_open2(avCodecContext, codec, NULL) < 0) {
        printf("Couldn't open codec\n");
        return -2;
    }
    return 0;
}

int LiveAudioEncoder::alloc_avframe() {
    int ret = 0;
    encode_frame = av_frame_alloc();
    if (!encode_frame) {
        printf("Could not allocate audio frame\n");
        return -1;
    }
    encode_frame->nb_samples = avCodecContext->frame_size;
    encode_frame->format = avCodecContext->sample_fmt;
    encode_frame->channel_layout = avCodecContext->channel_layout;
    encode_frame->sample_rate = avCodecContext->sample_rate;
    
    audio_nb_samples = avCodecContext->codec->capabilities & AV_CODEC_CAP_VARIABLE_FRAME_SIZE ? 10240 : avCodecContext->frame_size;
    int src_samples_linesize;
    ret = av_samples_alloc_array_and_samples(&audio_samples_data, &src_samples_linesize, avCodecContext->channels, audio_nb_samples, avCodecContext->sample_fmt, 0);
    if (ret < 0) {
        printf("Could not allocate source samples\n");
        return -1;
    }
    audio_samples_size = av_samples_get_buffer_size(NULL, avCodecContext->channels, audio_nb_samples, avCodecContext->sample_fmt, 0);
    return ret;
}
