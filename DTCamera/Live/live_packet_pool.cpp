//
//  live_packet_pool.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_packet_pool.h"

LivePacketPool::LivePacketPool() {
    audioPacketQueue = NULL;
    recordingVideoPacketQueue = NULL;
    buffer = NULL;
    pthread_rwlock_init(&mRwlock, NULL);
}

LivePacketPool::~LivePacketPool() {
    pthread_rwlock_destroy(&mRwlock);
}

LivePacketPool* LivePacketPool::instance = new LivePacketPool();
LivePacketPool* LivePacketPool::GetInstance() {
    return instance;
}

void LivePacketPool::initAudioPacketQueue(int audioSampleRate) {
    const char *name = "audioPacket pcm data queue";
    audioPacketQueue = new LiveAudioPacketQueue(name);
    this->audioSampleRate = audioSampleRate;
    this->channels = 2;
    bufferSize = audioSampleRate * channels * AUDIO_PACKET_DURATION_IN_SECS;
    buffer = new short[bufferSize];
    bufferCursor = 0;
}

void LivePacketPool::abortAudioPacketQueue() {
    if (NULL != audioPacketQueue) {
        audioPacketQueue->abort();
    }
}

void LivePacketPool::destroyAudioPacketQueue() {
    if (NULL != audioPacketQueue) {
        delete audioPacketQueue;
        audioPacketQueue = NULL;
    }
    if (buffer) {
        delete[] buffer;
        buffer = NULL;
    }
}

int LivePacketPool::getAudioPacket(LiveAudioPacket **audioPacket, bool block) {
    int result = -1;
    if (NULL != audioPacketQueue) {
        result = audioPacketQueue->get(audioPacket, block);
    }
    return result;
}

int LivePacketPool::getAudioPacketQueueSize() {
    return audioPacketQueue->size();
}

bool LivePacketPool::discardAudioPacket() {
    bool ret = false;
    LiveAudioPacket *tempAudioPacket = NULL;
    int resultCode = audioPacketQueue->get(&tempAudioPacket, true);
    if (resultCode > 0) {
        delete tempAudioPacket;
        tempAudioPacket = NULL;
        pthread_rwlock_wrlock(&mRwlock);
        totalDiscardVideoPacketDuration -= (AUDIO_PACKET_DURATION_IN_SECS * 1000.0f);
        pthread_rwlock_unlock(&mRwlock);
        ret = true;
    }
    return ret;
}

bool LivePacketPool::detectDiscardAudioPacket() {
    bool ret = false;
    pthread_rwlock_wrlock(&mRwlock);
    ret = totalDiscardVideoPacketDuration >= (AUDIO_PACKET_DURATION_IN_SECS * 1000.0f);
    pthread_rwlock_unlock(&mRwlock);
    return ret;
}

void LivePacketPool::pushAudioPacketToQueue(LiveAudioPacket *audioPacket) {
    if (NULL != audioPacketQueue) {
        int audioPacketBufferCursor = 0;
        while (audioPacket->size > 0) {
            int audioBufferLength = bufferSize - bufferCursor;
            int length = MIN(audioBufferLength, audioPacket->size);
            memcpy(buffer + bufferCursor, audioPacket->buffer + audioPacketBufferCursor, length * sizeof(short));
            audioPacket->size -= length;
            bufferCursor += length;
            audioPacketBufferCursor += length;
            if (bufferCursor == bufferSize) {
                LiveAudioPacket *targetAudioPacket = new LiveAudioPacket();
                targetAudioPacket->size = bufferSize;
                short *audioBuffer = new short[bufferSize];
                memcpy(audioBuffer, buffer, bufferSize * sizeof(short));
                targetAudioPacket->buffer = audioBuffer;
                audioPacketQueue->put(targetAudioPacket);
                bufferCursor = 0;
            }
        }
    }
    delete audioPacket;
}

void LivePacketPool::initRecordingVideoPacketQueue() {
    if (NULL == recordingVideoPacketQueue) {
        const char *name = "recording video yuv frame packet queue";
        recordingVideoPacketQueue = new LiveVideoPacketQueue(name);
        totalDiscardVideoPacketDuration = 0;
        tempVideoPacket = NULL;
        tempVideoPacketRefCnt = 0;
    }
}

void LivePacketPool::abortRecordingVideoPacketQueue() {
    if (NULL != recordingVideoPacketQueue) {
        recordingVideoPacketQueue->abort();
    }
}

void LivePacketPool::destroyRecordingVideoPacketQueue() {
    if (NULL != recordingVideoPacketQueue) {
        delete recordingVideoPacketQueue;
        recordingVideoPacketQueue = NULL;
        if (tempVideoPacketRefCnt > 0) {
            delete tempVideoPacket;
            tempVideoPacket = NULL;
        }
    }
}

int LivePacketPool::getRecordingVideoPacket(LiveVideoPacket **videoPacket, bool block) {
    int result = -1;
    if (NULL != recordingVideoPacketQueue) {
        result = recordingVideoPacketQueue->get(videoPacket, block);
    }
    return result;
}

bool LivePacketPool::detectDiscardVideoPacket() {
    return recordingVideoPacketQueue->size() > VIDEO_PACKET_QUEUE_THRRESHOLD;
}

bool LivePacketPool::pushRecordingVideoPacketToQueue(LiveVideoPacket *videoPacket) {
    bool dropFrame = false;
    if (NULL != recordingVideoPacketQueue) {
        while (detectDiscardVideoPacket()) {
            dropFrame = true;
            int discardVideoFrameCnt = 0;
            int discardVideoFrameDuration = recordingVideoPacketQueue->discardGOP(&discardVideoFrameCnt);
            if (discardVideoFrameDuration < 0) {
                break;
            }
            this->recordDropVideoFrame(discardVideoFrameDuration);
        }
        if (NULL != tempVideoPacket) {
            int packetDuration = videoPacket->timeMills - tempVideoPacket->timeMills;
            tempVideoPacket->duration = packetDuration;
            recordingVideoPacketQueue->put(tempVideoPacket);
            tempVideoPacketRefCnt = 0;
        }
        tempVideoPacket = videoPacket;
        tempVideoPacketRefCnt = 1;
    }
    return dropFrame;
}

void LivePacketPool::recordDropVideoFrame(int discardVideoFrameDuration) {
    pthread_rwlock_wrlock(&mRwlock);
    totalDiscardVideoPacketDuration += discardVideoFrameDuration;
    pthread_rwlock_unlock(&mRwlock);
}

int LivePacketPool::getRecordingVideoPacketQueueSize() {
    if (NULL != recordingVideoPacketQueue) {
        return recordingVideoPacketQueue->size();
    }
    return 0;
}

void LivePacketPool::clearRecordingVideoPacketToQueue() {
    if (NULL != recordingVideoPacketQueue) {
        return recordingVideoPacketQueue->flush();
    }
}
