//
//  live_audio_packet_queue.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/13.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_audio_packet_queue_h
#define live_audio_packet_queue_h

#include "live_common.h"
#include <pthread.h>

typedef struct LiveAudioPacket {
    short *buffer;
    byte *data;
    int size;
    float position;
    long frameNum;
    
    LiveAudioPacket() {
        buffer = NULL;
        data = NULL;
        size = 0;
        position = -1;
    }
    
    ~LiveAudioPacket() {
        if (NULL != buffer) {
            delete[] buffer;
            buffer = NULL;
        }
        if (NULL != data) {
            delete[] data;
            data = NULL;
        }
    }
} LiveAudioPacket;

typedef struct LiveAudioPacketList {
    LiveAudioPacket *pkt;
    struct LiveAudioPacketList *next;
    LiveAudioPacketList() {
        pkt = NULL;
        next = NULL;
    }
} LiveAudioPacketList;

inline void buildPacketFromBuffer(LiveAudioPacket *audioPacket, short *samples, int sampleSize) {
    short *packetBuffer = new short[sampleSize];
    if (NULL != packetBuffer) {
        memcpy(packetBuffer, samples, sampleSize * 2);
        audioPacket->buffer = packetBuffer;
        audioPacket->size = sampleSize;
    } else {
        audioPacket->size = -1;
    }
}

class LiveAudioPacketQueue {
public:
    LiveAudioPacketQueue();
    LiveAudioPacketQueue(const char *queueNameParam);
    ~LiveAudioPacketQueue();
    
    void init();
    void flush();
    int put(LiveAudioPacket *audioPacket);
    /* return < 0 if aborted, 0 if no packet and > 0 if packet. */
    int get(LiveAudioPacket **audioPacket, bool block);
    int size();
    void abort();
    
private:
    LiveAudioPacketList *mFrist;
    LiveAudioPacketList *mLast;
    int mNbPackets;
    bool mAbortRequest;
    pthread_mutex_t mLock;
    pthread_cond_t mCondition;
    const char *queueName;
};

#endif /* live_audio_packet_queue_h */
