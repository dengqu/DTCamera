//
//  live_audio_encoder_adapter.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/19.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_audio_encoder_adapter_h
#define live_audio_encoder_adapter_h

#include "live_audio_encoder.h"
#include <pthread.h>
#include "live_packet_pool.h"
#include "live_audio_packet_pool.h"

class LiveAudioEncoderAdapter {
public:
    LiveAudioEncoderAdapter();
    virtual ~LiveAudioEncoderAdapter();
    
    void init(LivePacketPool *pcmPacketPool, int audioSampleRate, int audioChannels, int audioBitRate, const char *audio_codec_name);
    virtual void destroy();
    
protected:
    bool isEncoding;
    LiveAudioEncoder *audioEncoder;
    pthread_t audioEncoderThread;
    static void* startEncodeThread(void *ptr);
    void startEncode();
    LivePacketPool *pcmPacketPool;
    LiveAudioPacketPool *aacPacketPool;
    
    int packetBufferSize;
    short *packetBuffer;
    int packetBufferCursor;
    int audioSampleRate;
    int audioChannels;
    int audioBitRate;
    char *audioCodecName;
    double packetBufferPresentationTimeMills;
    
    float channelRatio;
    
    int cpyToSamples(uint8_t *samples, int samplesInShortCursor, int cpyPacketBufferSize, double *presentationTimeMills);
    
    int getAudioPacket();
    
    virtual int processAudio() {
        return packetBufferSize;
    }
    
    virtual void discardAudioPacket();

public:
    int getAudioFrame(uint8_t *samples, int frame_size, int nb_channels, double *presentationTimeMills);
};

#endif /* live_audio_encoder_adapter_h */
