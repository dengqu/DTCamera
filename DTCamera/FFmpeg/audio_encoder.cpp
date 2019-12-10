//
//  audio_encoder.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/5.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "audio_encoder.h"

AudioEncoder::AudioEncoder() {
}

AudioEncoder::~AudioEncoder() {
}

int AudioEncoder::alloc_audio_stream(const char *codec_name) {
    AVCodec *codec;
    AVSampleFormat preferedSampleFMT = AV_SAMPLE_FMT_S16;
    int preferedChannels = audioChannels;
    int preferedSampleRate = audioSampleRate;
    audioStream = avformat_new_stream(avFormatContext, NULL);
    audioStream->id = 1;
    avCodecContext = audioStream->codec;
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
    
    codec = avcodec_find_encoder_by_name(codec_name); // 寻找 encoder
    if (!codec) {
        printf("Couldn't find a valid audio codec\n");
        return -1;
    }
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

int AudioEncoder::alloc_avframe() {
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

int AudioEncoder::init(int bitRate, int channels, int sampleRate, int bitsPerSample, const char *aacFilePath, const char *codec_name) {
    avCodecContext = NULL;
    avFormatContext = NULL;
    input_frame = NULL;
    samples = NULL;
    samplesCursor = 0;
    swrContext = NULL;
    swrFrame = NULL;
    swrBuffer = NULL;
    convert_data = NULL;
    this->isWriteHeaderSuccess = false;
    
    totalEncodeTimeMills = 0;
    totalSWRTimeMills = 0;
    
    this->publishBitRate = bitRate;
    this->audioChannels = channels;
    this->audioSampleRate = sampleRate;
    int ret;
    avcodec_register_all(); // 注册所有可用的 encoder 和 decoder
    av_register_all(); // 注册所有可用的 muxer, demuxer 和 protocol
    
    avFormatContext = avformat_alloc_context();
    printf("aacFilePath is %s\n", aacFilePath);
    if ((ret = avformat_alloc_output_context2(&avFormatContext, NULL, NULL, aacFilePath)) != 0 ) { // 确认 muxer
        printf("avFormatContext   alloc   failed : %s\n", av_err2str(ret));
        return -1;
    }
    
    if (ret = avio_open2(&avFormatContext->pb, aacFilePath, AVIO_FLAG_WRITE, NULL, NULL)) { // 确认 protocol
        printf("Could not avio open fail %s\n", av_err2str(ret));
        return -1;
    }
    
    this->alloc_audio_stream(codec_name);
    av_dump_format(avFormatContext, 0, aacFilePath, 1);
    if (avformat_write_header(avFormatContext, NULL) != 0) {
        printf("Could not write header\n");
        return -1;
    }
    this->isWriteHeaderSuccess = true;
    this->alloc_avframe();
    
    return 1;
}

int AudioEncoder::init(int bitRate, int channels, int bitsPerSample, const char *aacFilePath, const char *codec_name) {
    return init(bitRate, channels, 44100, bitsPerSample, aacFilePath, codec_name);
}

void AudioEncoder::encode(uint8_t *buffer, int size) {
    int bufferCursor = 0;
    int bufferSize = size;
    while (bufferSize >= (buffer_size - samplesCursor)) {
        int cpySize = buffer_size - samplesCursor;
        memcpy(samples + samplesCursor, buffer + bufferCursor, cpySize);
        bufferCursor += cpySize;
        bufferSize -= cpySize;
        this->encodePacket();
        samplesCursor = 0;
    }
    if (bufferSize > 0) {
        memcpy(samples + samplesCursor, buffer + bufferCursor, bufferSize);
        samplesCursor += bufferSize;
    }
}

void AudioEncoder::encodePacket() {
    int ret, got_output;
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
    pkt.stream_index = 0;
    pkt.duration = (int)AV_NOPTS_VALUE;
    pkt.pts = pkt.dts = 0;
    pkt.data = samples;
    pkt.size = buffer_size;
    ret = avcodec_encode_audio2(avCodecContext, &pkt, encode_frame, &got_output);
    if (ret < 0) {
        printf("Error encoding audio frame\n");
        return;
    }
    if (got_output) {
        if (avCodecContext->coded_frame && avCodecContext->coded_frame->pts != AV_NOPTS_VALUE) {
            pkt.pts = av_rescale_q(avCodecContext->coded_frame->pts, avCodecContext->time_base, audioStream->time_base);
        }
        pkt.flags |= AV_PKT_FLAG_KEY;
        this->duration = pkt.pts * av_q2d(audioStream->time_base);
        int writeCode = av_interleaved_write_frame(avFormatContext, &pkt);
    }
    av_free_packet(&pkt);
}

void AudioEncoder::destroy() {
    printf("start destroy!!!");
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
    if (this->isWriteHeaderSuccess) {
        avFormatContext->duration = this->duration * AV_TIME_BASE;
        printf("duration is %.3f", this->duration);
        av_write_trailer(avFormatContext);
    }
    if (NULL != avCodecContext) {
        avcodec_close(avCodecContext);
        av_free(avCodecContext);
    }
    if (NULL != avCodecContext && NULL != avFormatContext->pb) {
        avio_close(avFormatContext->pb);
    }
    printf("end destroy!!! totalEncodeTimeMills is %d totalSWRTimeMills is %d", totalEncodeTimeMills, totalSWRTimeMills);
}
