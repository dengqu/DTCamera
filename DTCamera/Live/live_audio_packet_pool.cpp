//
//  live_audio_packet_pool.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_audio_packet_pool.h"

LiveAudioPacketPool::LiveAudioPacketPool() {
    audioPacketQueue = NULL;
}

LiveAudioPacketPool::~LiveAudioPacketPool() {
}

LiveAudioPacketPool* LiveAudioPacketPool::instance = new LiveAudioPacketPool();
LiveAudioPacketPool* LiveAudioPacketPool::GetInstance() {
    return instance;
}

void LiveAudioPacketPool::initAudioPacketQueue() {
    const char *name = "audioPacket aac data queue";
    audioPacketQueue = new LiveAudioPacketQueue(name);
}

void LiveAudioPacketPool::abortAudioPacketQueue() {
    if (NULL != audioPacketQueue) {
        audioPacketQueue->abort();
    }
}

void LiveAudioPacketPool::destroyAudioPacketQueue() {
    if (NULL != audioPacketQueue) {
        delete audioPacketQueue;
        audioPacketQueue = NULL;
    }
}

int LiveAudioPacketPool::getAudioPacket(LiveAudioPacket **audioPacket, bool block) {
    int result = -1;
    if (NULL != audioPacketQueue) {
        result = audioPacketQueue->get(audioPacket, block);
    }
    return result;
}

int LiveAudioPacketPool::getAudioPacketQueueSize() {
    return audioPacketQueue->size();
}

void LiveAudioPacketPool::pushAudioPacketToQueue(LiveAudioPacket *audioPacket) {
    if (NULL != audioPacketQueue) {
        audioPacketQueue->put(audioPacket);
    }
}
