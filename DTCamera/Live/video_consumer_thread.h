//
//  video_consumer_thread.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef video_consumer_thread_h
#define video_consumer_thread_h

#include "live_common.h"
#include "live_thread.h"
#include "live_packet_pool.h"
#include "live_audio_packet_pool.h"
#include "recording_h264_publisher.h"

#define CLIENT_CANCEL_CONNECT_ERR_CODE               -100199

class VideoConsumerThread: public LiveThread {
public:
    VideoConsumerThread();
    virtual ~VideoConsumerThread();
    int init(char *videoOutputURI,
             int videoWidth, int videoHeight, int videoFrameRate, int videoBitRate,
             int audioSampleRate, int audioChannels, int audioBitRate, char *audioCodecName);
    virtual void stop();
    
    void registerPublishTimeoutCallback(int (*on_publish_timeout_callback)(void *context), void *context);
    
    int getH264Packet(LiveVideoPacket **packet);
    int getAudioPacket(LiveAudioPacket **audioPacket);
    
protected:
    LivePacketPool *packetPool;
    LiveAudioPacketPool *aacPacketPool;
    RecordingPublisher *videoPublisher;
    bool isStopping;
    bool isConnecting;
    pthread_mutex_t connectingLock;
    pthread_mutex_t interruptLock;
    pthread_cond_t interruptCondition;

    virtual void init();
    virtual void buildPublisherInstance();
    void releasePublisher();
    void handleRun(void *ptr);
};

#endif /* video_consumer_thread_h */
