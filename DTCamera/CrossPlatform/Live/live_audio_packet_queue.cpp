//
//  live_audio_packet_queue.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/13.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_audio_packet_queue.h"

LiveAudioPacketQueue::LiveAudioPacketQueue() {
    init();
}

LiveAudioPacketQueue::LiveAudioPacketQueue(const char *queueNameParam) {
    init();
    queueName = queueNameParam;
}

void LiveAudioPacketQueue::init() {
    pthread_mutex_init(&mLock, NULL);
    pthread_cond_init(&mCondition, NULL);
    mNbPackets = 0;
    mFrist = NULL;
    mLast = NULL;
    mAbortRequest = false;
}

LiveAudioPacketQueue::~LiveAudioPacketQueue() {
    printf("%s ~LiveAudioPacketQueue ....\n", queueName);
    flush();
    pthread_mutex_destroy(&mLock);
    pthread_cond_destroy(&mCondition);
}

int LiveAudioPacketQueue::size() {
    pthread_mutex_lock(&mLock);
    int size = mNbPackets;
    pthread_mutex_unlock(&mLock);
    return size;
}

void LiveAudioPacketQueue::flush() {
    printf("\n %s flush .... and this time the queue size is %d \n", queueName, size());
    LiveAudioPacketList *pkt, *pkt1;
    LiveAudioPacket *audioPacket;
    pthread_mutex_lock(&mLock);
    for (pkt = mFrist; pkt != NULL; pkt = pkt1) {
        pkt1 = pkt->next;
        audioPacket = pkt->pkt;
        if (NULL != audioPacket) {
            delete audioPacket;
        }
        delete pkt;
        pkt = NULL;
    }
    mLast = NULL;
    mFrist = NULL;
    mNbPackets = 0;
    pthread_mutex_unlock(&mLock);
}

int LiveAudioPacketQueue::put(LiveAudioPacket *pkt) {
    if (mAbortRequest) {
        delete pkt;
        return -1;
    }
    LiveAudioPacketList *pkt1 = new LiveAudioPacketList();
    if (!pkt1) {
        return -1;
    }
    pkt1->pkt = pkt;
    pkt1->next = NULL;
    pthread_mutex_lock(&mLock);
    if (mLast == NULL) {
        mFrist = pkt1;
    } else {
        mLast->next = pkt1;
    }
    mLast = pkt1;
    mNbPackets++;
    pthread_cond_signal(&mCondition);
    pthread_mutex_unlock(&mLock);
    return 0;
}

int LiveAudioPacketQueue::get(LiveAudioPacket **pkt, bool block) {
    LiveAudioPacketList *pkt1;
    int ret;
    pthread_mutex_lock(&mLock);
    for (;;) {
        if (mAbortRequest) {
            ret = -1;
            break;
        }
        pkt1 = mFrist;
        if (pkt1) {
            mFrist = pkt1->next;
            if (!mFrist) {
                mLast = NULL;
            }
            mNbPackets--;
            *pkt = pkt1->pkt;
            delete pkt1;
            pkt1 = NULL;
            ret = 1;
            break;
        } else if (!block) {
            ret = 0;
            break;
        } else {
            pthread_cond_wait(&mCondition, &mLock);
        }
    }
    pthread_mutex_unlock(&mLock);
    return ret;
}

void LiveAudioPacketQueue::abort() {
    pthread_mutex_lock(&mLock);
    mAbortRequest = true;
    pthread_cond_signal(&mCondition);
    pthread_mutex_unlock(&mLock);
}
