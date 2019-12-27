//
//  recording_publisher.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "recording_publisher.h"

RecordingPublisher::RecordingPublisher() {
    isConnected = false;
    isWriteHeaderSuccess = false;
    video_st = NULL;
    audio_st = NULL;
    bsfc = NULL;
    oc = NULL;
    publishTimeout = 0;
    lastAudioPacketPresentationTimeMills = 0;
}

RecordingPublisher::~RecordingPublisher() {
    publishTimeout = 0;
}

void RecordingPublisher::registerPublishTimeoutCallback(int (*on_publish_timeout_callback)(void *), void *context) {
    this->onPublishTimeoutCallback = on_publish_timeout_callback;
    this->timeoutContext = context;
}

void RecordingPublisher::registerFillAACPacketCallback(int (*fill_aac_packet_callback)(LiveAudioPacket **, void *), void *context) {
    this->fillAACPacketCallback = fill_aac_packet_callback;
    this->fillAACPacketContext = context;
}

void RecordingPublisher::registerFillVideoPacketCallback(int (*fill_packet_frame)(LiveVideoPacket **, void *), void *context) {
    this->fillH264PacketCallback = fill_packet_frame;
    this->fillH264PacketContext = context;
}

int RecordingPublisher::detectTimeout() {
    if (platform_4_live::getCurrentTimeMills() - sendLatestFrameTimemills > publishTimeout) {
        int queueSize = LivePacketPool::GetInstance()->getRecordingVideoPacketQueueSize();
        printf("RecordingPublisher::interrupt_cb callback time out ... queue size:%d\n", queueSize);
        return 1; // 返回 1 则代表结束 I/O 操作
    }
    return 0; // 返回 0 则代表继续 I/O 操作
}

int RecordingPublisher::interrupt_cb(void *ctx) { // 超时回调函数
    RecordingPublisher *publisher = (RecordingPublisher *)ctx;
    return publisher->detectTimeout();
}

int RecordingPublisher::init(char *videoOutputURI, int videoWidth, int videoHeight, int videoFrameRate, int videoBitRate, int audioSampleRate, int audioChannels, int audioBitRate, char *audioCodecName) {
    int ret = 0;
    this->publishTimeout = PUBLISH_DATA_TIME_OUT;
    this->sendLatestFrameTimemills = platform_4_live::getCurrentTimeMills();
    this->duration = 0.0;
    this->isConnected = false;
    this->onPublishTimeoutCallback = NULL;
    this->video_st = NULL;
    this->audio_st = NULL;
    this->videoWidth = videoWidth;
    this->videoHeight = videoHeight;
    this->videoFrameRate = videoFrameRate;
    this->videoBitRate = videoBitRate;
    this->audioSampleRate = audioSampleRate;
    this->audioChannels = audioChannels;
    this->audioBitRate = audioBitRate;
    
    avcodec_register_all();
    av_register_all();
    avformat_network_init();
    
    printf("Publish URL %s\n", videoOutputURI);

    avformat_alloc_output_context2(&oc, NULL, "flv", videoOutputURI);
    if (!oc) {
        return -1;
    }
    fmt = oc->oformat;
    
    if ((ret = buildVideoStream()) < 0) {
        printf("buildVideoStream failed....\n");
        return -1;
    }
    
    if ((ret = buildAudioStream(audioCodecName)) < 0) {
        printf("buildAudioStream failed....\n");
        return -1;
    }
    
    if (!(fmt->flags & AVFMT_NOFILE)) {
        if (PUBLISH_INVALID_FLAG != this->publishTimeout) {
            AVIOInterruptCB int_cb = {interrupt_cb, this};
            oc->interrupt_callback = int_cb;
            ret = avio_open2(&oc->pb, videoOutputURI, AVIO_FLAG_WRITE, &oc->interrupt_callback, NULL);
            if (ret < 0) {
                printf("Could not open '%s': %s\n", videoOutputURI, av_err2str(ret));
                return -1;
            }
            this->isConnected = true;
        } else {
            return -1;
        }
    } else {
        return -1;
    }
    
    return 1;
}

int RecordingPublisher::encode() {
    int ret = 0;
    double video_time = getVideoStreamTimeInSecs();
    double audio_time = getAudioStreamTimeInSecs();
//    printf("video_time is %lf, audio_time is %f\n", video_time, audio_time);
    if (!video_st || (video_st && audio_st && audio_time < video_time)) { // 通过比较两路流上当前的时间戳信息，将时间戳比较小的那一路流进行封装和输出，音视频是交错存储的，即存储完一帧视频帧之后，再存储一段时间的音频，不一定是一帧音频，要看视频的 FPS 是多少
        ret = write_audio_frame(oc, audio_st);
    } else if (video_st) {
        ret = write_video_frame(oc, video_st);
    }
    sendLatestFrameTimemills = platform_4_live::getCurrentTimeMills();
    duration = MIN(audio_time, video_time);
    if (ret < 0 && VIDEO_QUEUE_ABORT_ERR_CODE != ret && AUDIO_QUEUE_ABORT_ERR_CODE != ret && !isInterrupted()) {
        if (NULL != onPublishTimeoutCallback) {
            onPublishTimeoutCallback(timeoutContext);
        }
        this->isConnected = false;
    }
    return ret;
}

int RecordingPublisher::stop() {
    printf("enter RecordingPublisher::stop...\n");
    int ret = 0;
    if (isConnected && isWriteHeaderSuccess) {
        printf("leave RecordingPublisher::stop() if (isConnected && isWriteHeaderSuccess)\n");
        av_write_trailer(oc);
        oc->duration = duration * AV_TIME_BASE; // 设置视频长度
    }
    if (video_st) {
        close_video(oc, video_st);
        video_st = NULL;
    }
    if (audio_st) {
        close_audio(oc, audio_st);
        audio_st = NULL;
    }
    if (isConnected) {
        if (!(fmt->flags & AVFMT_NOFILE)) {
            avio_close(oc->pb);
        }
        isConnected = false;
    }
    if (oc) {
        avformat_free_context(oc);
        oc = NULL;
    }
    printf("leave RecordingPublisher::stop...\n");
    return ret;
}

int RecordingPublisher::buildAudioStream(char *audioCodecName) {
    int ret = 1;
    AVCodec *audioCodec = NULL;
    audio_st = add_stream(oc, &audioCodec, AV_CODEC_ID_NONE, audioCodecName);
    if (audio_st && audioCodec) {
        if ((ret = open_audio(oc, audioCodec, audio_st)) < 0) {
            printf("open_audio failed....\n");
            return ret;
        }
    }
    return ret;
}

int RecordingPublisher::buildVideoStream() {
    int ret = 1;
    AVCodec *video_codec = NULL;
    fmt->video_codec = AV_CODEC_ID_H264;
    if (fmt->video_codec != AV_CODEC_ID_NONE) {
        video_st = add_stream(oc, &video_codec, fmt->video_codec, NULL);
    }
    if (video_st && video_codec) {
        if ((ret = open_video(oc, video_codec, video_st)) < 0) {
            printf("open_video failed....\n");
            return ret;
        }
    }
    return ret;
}

AVStream* RecordingPublisher::add_stream(AVFormatContext *oc, AVCodec **codec, enum AVCodecID codecId, char *codecName) {
    AVCodecContext *c;
    AVStream *st;
    if (AV_CODEC_ID_NONE == codecId) {
        *codec = avcodec_find_encoder_by_name(codecName);
    } else {
        *codec = avcodec_find_encoder(codecId);
    }
    if (!(*codec)) {
        printf("Could not find encoder for '%s'\n", avcodec_get_name(codecId));
        return NULL;
    }
    printf("\n find encoder name is '%s'\n", (*codec)->name);
    
    st = avformat_new_stream(oc, *codec);
    if (!st) {
        printf("Could not allocate stream\n");
        return NULL;
    }
    st->id = oc->nb_streams - 1;
    c = st->codec;
    
    switch ((*codec)->type) {
        case AVMEDIA_TYPE_AUDIO:
            printf("audioBitRate is %d audioChannels is %d audioSampleRate is %d\n", audioBitRate,
                 audioChannels, audioSampleRate);
            c->sample_fmt = AV_SAMPLE_FMT_FLTP;
            c->bit_rate = audioBitRate;
            c->codec_type = AVMEDIA_TYPE_AUDIO;
            c->sample_rate = audioSampleRate;
            c->channel_layout = audioChannels == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
            c->channels = av_get_channel_layout_nb_channels(c->channel_layout);
            c->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
            break;
        case AVMEDIA_TYPE_VIDEO:
            c->codec_id = AV_CODEC_ID_H264;
            c->bit_rate = videoBitRate;
            c->width = videoWidth;
            c->height = videoHeight;
            
            st->avg_frame_rate.num = 30000;
            st->avg_frame_rate.den = (int)(30000 / videoFrameRate);
            
            c->time_base.den = 30000;
            c->time_base.num = (int)(30000 / videoFrameRate);
            
            c->gop_size = videoFrameRate; // 表示两个 I 帧之间的间隔
            
            /**  -qscale q  使用固定的视频量化标度(VBR)  以<q>质量为基础的VBR，取值0.01-255，约小质量越好，即qscale 4和-qscale 6，4的质量比6高 。
             *                     此参数使用次数较多，实际使用时发现，qscale是种固定量化因子，设置qscale之后，前面设置的-b好像就无效了，而是自动调整了比特率。
             *     -qmin q 最小视频量化标度(VBR) 设定最小质量，与-qmax（设定最大质量）共用
             *     -qmax q 最大视频量化标度(VBR) 使用了该参数，就可以不使用qscale参数  **/
            c->qmin = 10;
            c->qmax = 30;
            c->pix_fmt = COLOR_FORMAT;
            // 新增语句，设置为编码延迟
            av_opt_set(c->priv_data, "preset", "ultrafast", 0);
            // 实时编码关键看这句，上面那条无所谓
            av_opt_set(c->priv_data, "tune", "zerolatency", 0);
            
            printf("sample_aspect_ratio = %d   %d", c->sample_aspect_ratio.den, c->sample_aspect_ratio.num);
            
            break;
        default:
            break;
    }
    /* Some formats want stream headers to be separate. */
    if (oc->oformat->flags & AVFMT_GLOBALHEADER) {
        c->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }
    return st;
}

int RecordingPublisher::open_video(AVFormatContext *oc, AVCodec *codec, AVStream *st) {
    return 1;
}

int get_sr_index(unsigned int sampling_frequency) {
    switch (sampling_frequency) {
        case 96000:
            return 0;
        case 88200:
            return 1;
        case 64000:
            return 2;
        case 48000:
            return 3;
        case 44100:
            return 4;
        case 32000:
            return 5;
        case 24000:
            return 6;
        case 22050:
            return 7;
        case 16000:
            return 8;
        case 12000:
            return 9;
        case 11025:
            return 10;
        case 8000:
            return 11;
        case 7350:
            return 12;
        default:
            return 0;
    }
}

int RecordingPublisher::open_audio(AVFormatContext *oc, AVCodec *codec, AVStream *st) {
    AVCodecContext *c = st->codec;
    c->extradata = (uint8_t *)av_malloc(2);
    c->extradata_size = 2;
    unsigned int object_type = 2; // AAC LC by default
    char dsi[2];
    dsi[0] = (object_type << 3) | (get_sr_index(c->sample_rate) >> 1);
    dsi[1] = ((get_sr_index(c->sample_rate) & 1) << 7) | (c->channels << 3);
    memcpy(c->extradata, dsi, 2); // FFmpeg 设置 extradata 的目的是为解码器提供原始数据，从而初始化解码器，类似于编码 AAC 前面加上 ADTS 的头，ADTS 头部信息可以提取编码器的 Profile、采样率以及声道数的信息
    bsfc = av_bitstream_filter_init("aac_adtstoasc"); // This filter creates an MPEG-4 AudioSpecificConfig from an MPEG-2/4 ADTS header and removes the ADTS header.
    return 1;
}

double RecordingPublisher::getAudioStreamTimeInSecs() {
    return lastAudioPacketPresentationTimeMills / 1000.0f;
}

int RecordingPublisher::write_audio_frame(AVFormatContext *oc, AVStream *st) {
    int ret = AUDIO_QUEUE_ABORT_ERR_CODE;
    LiveAudioPacket *audioPacket = NULL;
    if ((ret = fillAACPacketCallback(&audioPacket, fillAACPacketContext)) > 0) {
        AVPacket pkt = {0};
        av_init_packet(&pkt);
        lastAudioPacketPresentationTimeMills = audioPacket->position;
        pkt.data = audioPacket->data;
        pkt.size = audioPacket->size;
        pkt.dts = pkt.pts = lastAudioPacketPresentationTimeMills / 1000.0f / av_q2d(st->time_base);
        pkt.duration = 1024;
        pkt.stream_index = st->index;
        AVPacket newPacket;
        av_init_packet(&newPacket);
        ret = av_bitstream_filter_filter(bsfc, st->codec, NULL, &newPacket.data, &newPacket.size, pkt.data, pkt.size, pkt.flags & AV_PKT_FLAG_KEY);
        if (ret > 0) {
            newPacket.pts = pkt.pts;
            newPacket.dts = pkt.dts;
            newPacket.duration = pkt.duration;
            newPacket.stream_index = pkt.stream_index;
//            printf("write_audio_frame %d\n", newPacket.size);
            ret = this->interleavedWriteFrame(oc, &newPacket);
            if (ret != 0) {
                printf("Error while writing audio frame: %s\n", av_err2str(ret));
            }
        } else {
            printf("Error av_bitstream_filter_filter: %s\n", av_err2str(ret));
        }
        av_free_packet(&newPacket);
        av_free_packet(&pkt);
        delete audioPacket;
    } else {
        ret = AUDIO_QUEUE_ABORT_ERR_CODE;
    }
    return ret;
}

int RecordingPublisher::interleavedWriteFrame(AVFormatContext *s, AVPacket *pkt) {
    if (startSendTime == 0) {
        startSendTime = platform_4_live::getCurrentTimeMills();
    }
    int ret = av_interleaved_write_frame(s, pkt);
    return ret;
}

void RecordingPublisher::close_video(AVFormatContext *oc, AVStream *st) {
    if (NULL != st->codec) {
        avcodec_close(st->codec);
    }
}

void RecordingPublisher::close_audio(AVFormatContext *oc, AVStream *st) {
    if (NULL != st->codec) {
        avcodec_close(st->codec);
    }
    if (NULL != bsfc) {
        av_bitstream_filter_close(bsfc);
    }
}
