//
//  live_audio_encoder_adapter.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/19.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_audio_encoder_adapter.h"

LiveAudioEncoderAdapter::LiveAudioEncoderAdapter() {
    audioCodecName = NULL;
    audioEncoder = NULL;
    isEncoding = false;
}

LiveAudioEncoderAdapter::~LiveAudioEncoderAdapter() {
}

static int fill_pcm_frame_callback(uint8_t *samples, int frame_size, int nb_channels, double *presentationTimeMills, void *context) {
    LiveAudioEncoderAdapter *adapter = (LiveAudioEncoderAdapter *)context;
    return adapter->getAudioFrame(samples, frame_size, nb_channels, presentationTimeMills);
}

void LiveAudioEncoderAdapter::init(LivePacketPool *pcmPacketPool, int audioSampleRate, int audioChannels, int audioBitRate, const char *audio_codec_name) {
    this->channelRatio = 1.0f;
    this->packetBuffer = NULL;
    this->packetBufferSize = 0;
    this->packetBufferCursor = 0;
    this->pcmPacketPool = pcmPacketPool;
    this->audioSampleRate = audioSampleRate;
    this->audioChannels = audioChannels;
    this->audioBitRate = audioBitRate;
    int audioCodecNameLength = strlen(audio_codec_name);
    audioCodecName = new char[audioCodecNameLength + 1];
    memset(audioCodecName, 0, audioCodecNameLength + 1);
    memcpy(audioCodecName, audio_codec_name, audioCodecNameLength);
    this->isEncoding = true;
    this->aacPacketPool = LiveAudioPacketPool::GetInstance();
    pthread_create(&audioEncoderThread, NULL, startEncodeThread, this);
}

void* LiveAudioEncoderAdapter::startEncodeThread(void *ptr) {
    LiveAudioEncoderAdapter *adapter = (LiveAudioEncoderAdapter *)ptr;
    adapter->startEncode();
    pthread_exit(0);
    return 0;
}

void LiveAudioEncoderAdapter::startEncode() {
    audioEncoder = new LiveAudioEncoder();
    audioEncoder->init(audioBitRate, audioChannels, audioSampleRate, audioCodecName, fill_pcm_frame_callback, this);
    while (isEncoding) {
        LiveAudioPacket *audioPacket = NULL;
        int ret = audioEncoder->encode(&audioPacket);
        if (ret >= 0 && NULL != audioPacket) {
            aacPacketPool->pushAudioPacketToQueue(audioPacket);
        }
    }
}

void LiveAudioEncoderAdapter::destroy() {
    isEncoding = false;
    pcmPacketPool->abortAudioPacketQueue();
    pthread_join(audioEncoderThread, 0);
    pcmPacketPool->destroyAudioPacketQueue();
    if (NULL != audioEncoder) {
        audioEncoder->destroy();
        delete audioEncoder;
        audioEncoder = NULL;
    }
    if (NULL != audioCodecName) {
        delete[] audioCodecName;
        audioCodecName = NULL;
    }
    if (NULL != packetBuffer) {
        delete packetBuffer;
        packetBuffer = NULL;
    }
}

int LiveAudioEncoderAdapter::getAudioFrame(uint8_t *samples, int frame_size, int nb_channels, double *presentationTimeMills) {
    int byteSize = frame_size;
    int samplesInShortCursor = 0;
    while (true) {
        if (packetBufferSize == 0) {
            int ret = this->getAudioPacket();
            if (ret < 0) {
                return ret;
            }
        }
        int copyToSamplesInShortSize = (byteSize - samplesInShortCursor * 2) / 2;
        if (packetBufferCursor + copyToSamplesInShortSize <= packetBufferSize) {
            this->cpyToSamples(samples, samplesInShortCursor, copyToSamplesInShortSize, presentationTimeMills);
            packetBufferCursor += copyToSamplesInShortSize;
            samplesInShortCursor = 0;
            break;
        } else {
            int subPacketBufferSize = packetBufferSize - packetBufferCursor;
            this->cpyToSamples(samples, samplesInShortCursor, subPacketBufferSize, presentationTimeMills);
            samplesInShortCursor += subPacketBufferSize;
            packetBufferSize = 0;
            continue;
        }
    }
    return frame_size * nb_channels;
}

int LiveAudioEncoderAdapter::cpyToSamples(uint8_t *samples, int samplesInShortCursor, int cpyPacketBufferSize, double *presentationTimeMills) {
    if (0 == samplesInShortCursor) {
        double packetBufferCursorDuration = (double)packetBufferCursor * 1000.0f / (double)(audioSampleRate * channelRatio);
        (*presentationTimeMills) = packetBufferPresentationTimeMills + packetBufferCursorDuration;
    }
    memcpy(samples + samplesInShortCursor, packetBuffer + packetBufferCursor, cpyPacketBufferSize * sizeof(short));
    return 1;
}

void LiveAudioEncoderAdapter::discardAudioPacket() {
    while (pcmPacketPool->detectDiscardAudioPacket()) {
        if (!pcmPacketPool->discardAudioPacket()) {
            break;
        }
    }
}

int LiveAudioEncoderAdapter::getAudioPacket() {
    this->discardAudioPacket();
    LiveAudioPacket *audioPacket = NULL;
    if (pcmPacketPool->getAudioPacket(&audioPacket, true) < 0) {
        return -1;
    }
    packetBufferCursor = 0;
    packetBufferPresentationTimeMills = audioPacket->position;
    packetBufferSize = audioPacket->size * channelRatio;
    if (NULL == packetBuffer) {
        packetBuffer = new short[packetBufferSize];
    }
    memcpy(packetBuffer, audioPacket->buffer, audioPacket->size * sizeof(short));
    int actualSize = this->processAudio();
    if (actualSize > 0 && actualSize < packetBufferSize) {
        packetBufferCursor = packetBufferSize - actualSize;
        memmove(packetBuffer + packetBufferCursor, packetBuffer, actualSize * sizeof(short));
    }
    if (NULL != audioPacket) {
        delete audioPacket;
        audioPacket = NULL;
    }
    return actualSize > 0 ? 1 : -1;
}
