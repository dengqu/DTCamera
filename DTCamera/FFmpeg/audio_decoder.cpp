//
//  audio_decoder.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/11.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "audio_decoder.h"

AudioDecoder::AudioDecoder() {
    inputFilePath = NULL;
}

AudioDecoder::~AudioDecoder() {
    if (NULL != inputFilePath) {
        delete[] inputFilePath;
        inputFilePath = NULL;
    }
}

int AudioDecoder::getMusicMeta(const char *fileString, int *metaData) {
    init(fileString);
    int sampleRate = avCodecContext->sample_rate;
    printf("sampleRate is %d\n", sampleRate);
    int bitRate = avCodecContext->bit_rate;
    printf("bitRate is %d\n", bitRate);
    destroy();
    metaData[0] = sampleRate;
    metaData[1] = bitRate;
    return 0;
}

void AudioDecoder::init(const char *fileString, int packetBufferSizeParam) {
    init(fileString);
    packetBufferSize = packetBufferSizeParam;
}

int AudioDecoder::init(const char *audioFile) {
    printf("enter AudioDecoder::init\n");
    audioBuffer = NULL;
    position = -1.0f;
    audioBufferCursor = 0;
    audioBufferSize = 0;
    swrContext = NULL;
    swrBuffer = NULL;
    swrBufferSize = 0;
    isNeedFirstFrameCorrectFlag = true;
    firstFrameCorrectionInSecs = 0.0f;
    
    avcodec_register_all();
    av_register_all();
    avFormatContext = avformat_alloc_context();
    printf("open accompany file %s....\n", audioFile);

    if (NULL == inputFilePath) {
        int length = strlen(audioFile);
        inputFilePath = new char[length + 1];
        memset(inputFilePath, 0, length + 1);
        memcpy(inputFilePath, audioFile, length + 1);
    }
    
    /*
     * 根据所提供的文件路径判断文件的格式，决定使用哪一个 Demuxer，
     * 举例来说，如果是 flv，那么 Demuxer 就会使用对应的 ff_flv_demuxer，
     * 所以对应的关键生命周期的方法 read_packet、read_seek、read_close 都会使用该 flv 的 Demuxer 中函数指针指定的函数，
     * read_header 函数会将 AVStream 结构体构造好，以便后续的步骤继续使用 AVStream 作为输入参数。
     */
    int result = avformat_open_input(&avFormatContext, audioFile, NULL, NULL);
    if (result != 0) {
        printf("can't open file %s result is %d\n", audioFile, result);
        return -1;
    } else {
        printf("open file %s success and result is %d\n", audioFile, result);
    }
    
    /*
     * 方法的作用就是把所有 Stream 的 MetaData 信息填充好，
     * 方法内部会先查找对应的解码器，然后打开对应的解码器，紧接着会利用 Demuxer 中的 read_packet 函数读取一段数据进行解码，当然解码的数据越多，分析出的流信息就会越准确，
     * probe size、max_analyze_duration 和 fps_probe_size 这三个参数共同控制解码数据的长度，
     * 当然，如果配置这几个参数的值越小，那么这个函数执行的时间就会越快，但是会导致 AVStream 结构体里面一些信息（视频的宽、高、fps、编码类型等）不准确。
     */
    avFormatContext->max_analyze_duration = 50000;
    result = avformat_find_stream_info(avFormatContext, NULL); // 检查在文件中的流的信息
    if (result < 0) {
        printf("fail avformat_find_stream_info result is %d\n", result);
        return -1;
    } else {
        printf("sucess avformat_find_stream_info result is %d\n", result);
    }
    stream_index = av_find_best_stream(avFormatContext, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0); // 寻找音频流下标
    printf("stream_index is %d\n", stream_index);

    if (stream_index == -1) {
        printf("no audio stream\n");
        return -1;
    }
    
    AVStream *audioStream = avFormatContext->streams[stream_index]; // 得到音频流
    if (audioStream->time_base.den && audioStream->time_base.num) {
        timeBase = av_q2d(audioStream->time_base);
    } else if (audioStream->codec->time_base.den && audioStream->codec->time_base.num) {
        timeBase = av_q2d(audioStream->codec->time_base);
    }
    avCodecContext = audioStream->codec; // 获得音频流的解码器上下文
    printf("avCodecContext->codec_id is %d AV_CODEC_ID_AAC is %d\n", avCodecContext->codec_id, AV_CODEC_ID_AAC);
    AVCodec *avCodec = avcodec_find_decoder(avCodecContext->codec_id); // 根据解码器上下文找到解码器
    if (avCodec == NULL) {
        printf("Unsupported codec\n");
        return -1;
    }
    
    /*
     * open 对应的就是 init 函数指针所指向的函数，该函数里面就会调用具体的编码库的 API，
     * 比如 libx264 这个 Codec 会调用 libx264 的编码库的 API，
     * 而 LAME 这个 Codec 会调用 LAME 的编码库的 API，
     * 并且会以对应的 AVCodecContext 中的 priv_data 来填充对应第三方库所需要的私有参数，
     * 如果开发者没有对属性 priv_data 填充值，那么就使用默认值。
     */
    result = avcodec_open2(avCodecContext, avCodec, NULL);
    if (result < 0) {
        printf("fail avcodec_open2 result is %d\n", result);
        return -1;
    } else {
        printf("sucess avcodec_open2 result is %d\n", result);
    }
    
    if (!audioCodecIsSupported()) {
        printf("because of audio Codec Is Not Supported so we will init swresampler...\n");
        swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(OUT_PUT_CHANNELS), AV_SAMPLE_FMT_S16, avCodecContext->sample_rate, av_get_default_channel_layout(avCodecContext->channels), avCodecContext->sample_fmt, avCodecContext->sample_rate, 0, NULL);
        if (!swrContext || swr_init(swrContext)) {
            if (swrContext) {
                swr_free(&swrContext);
            }
            avcodec_close(avCodecContext); // 调用对应第三方库的 API 来关闭掉对应的编码库
            printf("init resampler failed...\n");
            return -1;
        }
    }
    printf("channels is %d sampleRate is %d\n", avCodecContext->channels, avCodecContext->sample_rate);
    pAudioFrame = av_frame_alloc();
    return 1;
}

bool AudioDecoder::audioCodecIsSupported() {
    if (avCodecContext->sample_fmt == AV_SAMPLE_FMT_S16) {
        return true;
    }
    return false;
}

AudioPacket* AudioDecoder::decodePacket() {
    short *samples = new short[packetBufferSize];
    int stereoSampleSize = readSamples(samples, packetBufferSize);
    AudioPacket *samplePacket = new AudioPacket();
    if (stereoSampleSize > 0) {
        samplePacket->buffer = samples;
        samplePacket->size = stereoSampleSize;
        samplePacket->position = position;
    } else {
        samplePacket->size = -1;
    }
    return samplePacket;
}

int AudioDecoder::readSamples(short *samples, int size) {
    int sampleSize = size;
    while (size > 0) {
        if (audioBufferCursor < audioBufferSize) {
            int audioBufferDataSize = audioBufferSize - audioBufferCursor;
            int copySize = MIN(size, audioBufferDataSize);
            memcpy(samples + (sampleSize - size), audioBuffer + audioBufferCursor, copySize * 2); // the last param is number of bytes to copy
            size -= copySize;
            audioBufferCursor += copySize;
        } else {
            if (readFrame() < 0) {
                break;
            }
        }
    }
    int fillSize = sampleSize - size;
    if (fillSize == 0) {
        return -1;
    }
    return fillSize;
}

int AudioDecoder::readFrame() {
    int ret = 1;
    av_init_packet(&packet);
    int gotframe = 0;
    int readFrameCode = -1;
    while (true) {
        /*
         * 内部处理了数据不能被解码器完全处理完的情况，
         * 该函数的实现首先会委托到 Demuxer 的 read_packet 方法中去，
         * 对于音频流，一个 AVPacket 可能包含多个 AVFrame，
         * 但是对于视频流，一个 AVPacket 只包含一个 AVFrame，
         * 该函数最终只会返回一个 AVPacket 结构体。
         */
        readFrameCode = av_read_frame(avFormatContext, &packet);
        if (readFrameCode >= 0) {
            if (packet.stream_index == stream_index) {
                int len = avcodec_decode_audio4(avCodecContext, pAudioFrame, &gotframe, &packet); // 音频解码
                if (len < 0) {
                    printf("decode audio error, skip packet\n");
                }
                if (gotframe) {
                    int numChannels = OUT_PUT_CHANNELS;
                    int numFrames = 0;
                    void *audioData;
                    if (swrContext) {
                        const int bufSize = av_samples_get_buffer_size(NULL, numChannels, pAudioFrame->nb_samples, AV_SAMPLE_FMT_S16, 1);
                        if (!swrBuffer || swrBufferSize < bufSize) {
                            swrBufferSize = bufSize;
                            swrBuffer = realloc(swrBuffer, swrBufferSize);
                        }
                        uint8_t *outbuf[2] = { (uint8_t*)swrBuffer, NULL };
                        numFrames = swr_convert(swrContext, outbuf, pAudioFrame->nb_samples, (const uint8_t **)pAudioFrame->data, pAudioFrame->nb_samples);
                        if (numFrames < 0) {
                            printf("fail resample audio\n");
                            ret = -1;
                            break;
                        }
                        audioData = swrBuffer;
                    } else {
                        if (avCodecContext->sample_fmt != AV_SAMPLE_FMT_S16) {
                            printf("bucheck, audio format is invalid\n");
                            ret = -1;
                            break;
                        }
                        audioData = pAudioFrame->data[0];
                        numFrames = pAudioFrame->nb_samples;
                    }
                    if (isNeedFirstFrameCorrectFlag && position >= 0) {
                        float expectedPosition = position + duration;
                        float actualPosition = av_frame_get_best_effort_timestamp(pAudioFrame) * timeBase;
                        firstFrameCorrectionInSecs = actualPosition - expectedPosition;
                        isNeedFirstFrameCorrectFlag = false;
                    }
                    duration = av_frame_get_pkt_duration(pAudioFrame) * timeBase;
                    position = av_frame_get_best_effort_timestamp(pAudioFrame) * timeBase - firstFrameCorrectionInSecs;
                    audioBufferSize = numFrames * numChannels;
                    audioBuffer = (short *)audioData;
                    audioBufferCursor = 0;
                    break;
                }
            }
        } else {
            ret = -1;
            break;
        }
    }
    av_free_packet(&packet);
    return ret;
}

void AudioDecoder::destroy() {
    printf("AudioDecoder start destroy!!!\n");
    if (NULL != swrBuffer) {
        free(swrBuffer);
        swrBuffer = NULL;
        swrBufferSize = 0;
    }
    if (NULL != swrContext) {
        swr_free(&swrContext);
        swrContext = NULL;
    }
    if (NULL != pAudioFrame) {
        av_free(pAudioFrame);
        pAudioFrame = NULL;
    }
    if (NULL != avCodecContext) {
        avcodec_close(avCodecContext);
        avCodecContext = NULL;
    }
    if (NULL != avFormatContext) {
        /*
         * 该函数负责释放对应的资源，
         * 首先会调用对应的 Demuxer 中的生命周期 read_close 方法，
         * 然后释放掉 AVFormatContext，
         * 最后关闭文件或者远程网络连接。
         */
        avformat_close_input(&avFormatContext);
        avFormatContext = NULL;
    }
    printf("AudioDecoder end destroy!!!\n");
}
