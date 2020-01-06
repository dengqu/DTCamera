//
//  live_audio_packet_pool.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_audio_packet_pool_h
#define live_audio_packet_pool_h

#include "live_audio_packet_queue.h"

class LiveAudioPacketPool {
protected:
    LiveAudioPacketPool();
    static LiveAudioPacketPool *instance;
    LiveAudioPacketQueue *audioPacketQueue;
    
public:
    static LiveAudioPacketPool* GetInstance();
    virtual ~LiveAudioPacketPool();
    
    virtual void initAudioPacketQueue();
    virtual void abortAudioPacketQueue();
    virtual void destroyAudioPacketQueue();
    virtual int getAudioPacket(LiveAudioPacket **audioPacket, bool block);
    virtual void pushAudioPacketToQueue(LiveAudioPacket *audioPacket);
    virtual int getAudioPacketQueueSize();
};

#endif /* live_audio_packet_pool_h */
