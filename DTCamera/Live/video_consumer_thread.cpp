//
//  video_consumer_thread.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "video_consumer_thread.h"

VideoConsumerThread::VideoConsumerThread() {
    isStopping = false;
    videoPublisher = NULL;
    isConnecting = false;
    
    pthread_mutex_init(&connectingLock, NULL);
    pthread_cond_init(&interruptCondition, NULL);
    pthread_mutex_init(&interruptLock, NULL);
}

VideoConsumerThread::~VideoConsumerThread() {
    pthread_mutex_destroy(&connectingLock);
    pthread_cond_destroy(&interruptCondition);
    pthread_mutex_destroy(&interruptLock);
}

void VideoConsumerThread::registerPublishTimeoutCallback(int (*on_publish_timeout_callback)(void *context), void *context) {
    if (NULL != videoPublisher) {
        videoPublisher->registerPublishTimeoutCallback(on_publish_timeout_callback, context);
    }
}

static int fill_aac_packet_callback(LiveAudioPacket **packet, void *context) {
    VideoConsumerThread *consumer = (VideoConsumerThread *)context;
    return consumer->getAudioPacket(packet);
}

int VideoConsumerThread::getAudioPacket(LiveAudioPacket **audioPacket) {
    if (aacPacketPool->getAudioPacket(audioPacket, true) < 0) {
        printf("aacPacketPool->getAudioPacket return negetive value...\n");
        return -1;
    }
    return 1;
}

static int fill_h264_packet_callback(LiveVideoPacket **packet, void *context) {
    VideoConsumerThread *consumer = (VideoConsumerThread *)context;
    return consumer->getH264Packet(packet);
}

int VideoConsumerThread::getH264Packet(LiveVideoPacket **packet) {
    if (packetPool->getRecordingVideoPacket(packet, true) < 0) {
        printf("packetPool->getRecordingVideoPacket return negetive value...\n");
        return -1;
    }
    return 1;
}

void VideoConsumerThread::init() {
    isStopping = false;
    packetPool = LivePacketPool::GetInstance();
    aacPacketPool = LiveAudioPacketPool::GetInstance();
    videoPublisher = NULL;
}

int VideoConsumerThread::init(char *videoOutputURI, int videoWidth, int videoHeight, int videoFrameRate, int videoBitRate, int audioSampleRate, int audioChannels, int audioBitRate, char *audioCodecName) {
    init();
    if (NULL == videoPublisher) {
        pthread_mutex_lock(&connectingLock);
        this->isConnecting = true;
        pthread_mutex_unlock(&connectingLock);
        buildPublisherInstance();
        int ret = videoPublisher->init(videoOutputURI, videoWidth, videoHeight, videoFrameRate, videoBitRate, audioSampleRate, audioChannels, audioBitRate, audioCodecName);
        pthread_mutex_lock(&connectingLock);
        this->isConnecting = false;
        pthread_mutex_unlock(&connectingLock);
        printf("videoPublisher->init return code %d...\n", ret);
        if (ret < 0 || videoPublisher->isInterrupted()) {
            printf("videoPublisher->init failed...\n");
            pthread_mutex_lock(&interruptLock);
            
            this->releasePublisher();
            
            pthread_cond_signal(&interruptCondition);
            pthread_mutex_unlock(&interruptLock);
        }
        if (!isStopping) {
            videoPublisher->registerFillAACPacketCallback(fill_aac_packet_callback, this);
            videoPublisher->registerFillVideoPacketCallback(fill_h264_packet_callback, this);
        } else {
            printf("Client Cancel ...\n");
            return CLIENT_CANCEL_CONNECT_ERR_CODE;
        }
    }
    return 0;
}

void VideoConsumerThread::releasePublisher() {
    if (NULL != videoPublisher) {
        videoPublisher->stop();
        delete videoPublisher;
        videoPublisher = NULL;
    }
}

void VideoConsumerThread::buildPublisherInstance() {
    videoPublisher = new RecordingH264Publisher();
}

void VideoConsumerThread::stop() {
    printf("enter VideoConsumerThread::stop...\n");
    pthread_mutex_lock(&connectingLock);
    if (isConnecting) {
        printf("before interruptPublisherPipe()\n");
        videoPublisher->interruptPublisherPipe();
        printf("after interruptPublisherPipe()\n");
        pthread_mutex_unlock(&connectingLock);
        
        pthread_mutex_lock(&interruptLock);
        pthread_cond_wait(&interruptCondition, &interruptLock);
        pthread_mutex_unlock(&interruptLock);
        
        printf("VideoConsumerThread::stop isConnecting return...\n");
        return;
    }
    pthread_mutex_unlock(&connectingLock);
    
    int ret = -1;
    
    isStopping = true;
    packetPool->abortRecordingVideoPacketQueue();
    aacPacketPool->abortAudioPacketQueue();
    long startEndingThreadTimeMills = platform_4_live::getCurrentTimeMills();
    printf("before wait publisher encoder ...\n");
    
    if (videoPublisher != NULL) {
        videoPublisher->interruptPublisherPipe();
    }
    if ((ret = wait()) != 0) {
        printf("Couldn't cancel VideoConsumerThread: %d\n", ret);
    }
    printf("after wait publisher encoder ... %d\n", (int)(platform_4_live::getCurrentTimeMills() - startEndingThreadTimeMills));

    this->releasePublisher();

    packetPool->destroyRecordingVideoPacketQueue();
    aacPacketPool->destroyAudioPacketQueue();
    printf("leave VideoConsumerThread::stop...\n");
}

void VideoConsumerThread::handleRun(void *ptr) {
    while (mRunning) {
        int ret = videoPublisher->encode();
        if (ret < 0) {
            printf("videoPublisher->encode result is invalid, so we will stop encode...\n");
            break;
        }
    }
}
