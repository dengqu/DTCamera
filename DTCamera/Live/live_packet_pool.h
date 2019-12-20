//
//  live_packet_pool.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_packet_pool_h
#define live_packet_pool_h

#include "live_common.h"
#include "live_audio_packet_queue.h"
#include "live_video_packet_queue.h"

#define VIDEO_PACKET_QUEUE_THRRESHOLD                                        60

#define AUDIO_PACKET_DURATION_IN_SECS                                        0.04f

class LivePacketPool {
protected:
    LivePacketPool();
    static LivePacketPool* instance;
    
    LiveAudioPacketQueue *audioPacketQueue;
    int audioSampleRate;
    int channels;
    
    LiveVideoPacketQueue *recordingVideoPacketQueue;
    
private:
    int totalDiscardVideoPacketDuration;
    pthread_rwlock_t mRwlock;
    
    int bufferSize;
    short *buffer;
    int bufferCursor;
    
    bool detectDiscardVideoPacket();
    
    LiveVideoPacket *tempVideoPacket;
    int tempVideoPacketRefCnt;
    
protected:
    virtual void recordDropVideoFrame(int discardVideoPacketSize);
public:
    static LivePacketPool* GetInstance();
    virtual ~LivePacketPool();
    
    virtual void initAudioPacketQueue(int audioSampleRate);
    virtual void abortAudioPacketQueue();
    virtual void destroyAudioPacketQueue();
    virtual int getAudioPacket(LiveAudioPacket **audioPacket, bool block);
    virtual void pushAudioPacketToQueue(LiveAudioPacket *audioPacket);
    virtual int getAudioPacketQueueSize();
    
    bool discardAudioPacket();
    bool detectDiscardAudioPacket();
    
    void initRecordingVideoPacketQueue();
    void abortRecordingVideoPacketQueue();
    void destroyRecordingVideoPacketQueue();
    int getRecordingVideoPacket(LiveVideoPacket **videoPacket, bool block);
    bool pushRecordingVideoPacketToQueue(LiveVideoPacket *videoPacket);
    int getRecordingVideoPacketQueueSize();
    void clearRecordingVideoPacketToQueue();
};

#endif /* live_packet_pool_h */
