//
//  LivePublisher.mm
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/13.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import "LivePublisher.h"
#import "live_packet_pool.h"
#import "live_video_packet_queue.h"
#import "video_consumer_thread.h"
#import "live_audio_encoder_adapter.h"

static int on_publish_timeout_callback(void *context) {
    NSLog(@"PublishTimeoutCallback...\n");
    LivePublisher *publisher = (__bridge LivePublisher*)context;
    [publisher.delegate publishTimeOut];
    return 1;
}

@interface LivePublisher ()

@property (nonatomic, copy) NSString *rtmpURL;
@property (nonatomic, assign) NSInteger videoWidth;
@property (nonatomic, assign) NSInteger videoHeight;
@property (nonatomic, assign) NSInteger videoFrameRate;
@property (nonatomic, assign) NSInteger videoBitRate;
@property (nonatomic, assign) NSInteger audioSampleRate;
@property (nonatomic, assign) NSInteger audioChannels;
@property (nonatomic, assign) NSInteger audioBitRate;
@property (nonatomic, copy) NSString *audioCodecName;

@property (nonatomic, assign) int totalSampleCount;

@end

@implementation LivePublisher
{
    VideoConsumerThread *_consumer;
    LiveAudioEncoderAdapter *_audioEncoder;
    dispatch_queue_t _consumerQueue;
}

- (instancetype)initWithRTMPURL:(NSString *)rtmpURL
                     videoWidth:(NSInteger)videoWidth videoHeight:(NSInteger)videoHeight videoFrameRate:(NSInteger)videoFrameRate videoBitRate:(NSInteger)videoBitRate
                audioSampleRate:(NSInteger)audioSampleRate audioChannels:(NSInteger)audioChannels audioBitRate:(NSInteger)audioBitRate audioCodecName:(NSString *)audioCodecName {
    self = [super init];
    if (self) {
        self.rtmpURL = rtmpURL;
        self.videoWidth = videoWidth;
        self.videoHeight = videoHeight;
        self.videoFrameRate = videoFrameRate;
        self.videoBitRate = videoBitRate;
        self.audioSampleRate = audioSampleRate;
        self.audioChannels = audioChannels;
        self.audioBitRate = audioBitRate;
        self.audioCodecName = audioCodecName;
        _consumerQueue = dispatch_queue_create("com.danthought.LivePublisher.consumerQueue", NULL);
    }
    return self;
}

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps timestramp:(Float64)miliseconds {
    const char bytesHeader[] = "\x00\x00\x00\x01";
    size_t headerLength = 4;
    
    LiveVideoPacket *videoPacket = new LiveVideoPacket();
    
    size_t length = 2 * headerLength + sps.length + pps.length;
    videoPacket->buffer = new unsigned char[length];
    videoPacket->size = int(length);
    memcpy(videoPacket->buffer, bytesHeader, headerLength);
    memcpy(videoPacket->buffer + headerLength, (unsigned char*)[sps bytes], sps.length);
    memcpy(videoPacket->buffer + headerLength + sps.length, bytesHeader, headerLength);
    memcpy(videoPacket->buffer + headerLength * 2 + sps.length, (unsigned char*)[pps bytes], pps.length);
    videoPacket->timeMills = 0;
    
    LivePacketPool::GetInstance()->pushRecordingVideoPacketToQueue(videoPacket);
}

- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame timestramp:(Float64)miliseconds {
    const char bytesHeader[] = "\x00\x00\x00\x01";
    size_t headerLength = 4;

    LiveVideoPacket *videoPacket = new LiveVideoPacket();
    
    videoPacket->buffer = new unsigned char[headerLength + data.length];
    videoPacket->size = int(headerLength + data.length);
    memcpy(videoPacket->buffer, bytesHeader, headerLength);
    memcpy(videoPacket->buffer + headerLength, (unsigned char*)[data bytes], data.length);
    videoPacket->timeMills = miliseconds;
    
    LivePacketPool::GetInstance()->pushRecordingVideoPacketToQueue(videoPacket);
}

- (void)receiveAudioBuffer:(AudioBuffer)buffer sampleRate:(int)sampleRate startRecordTimeMills:(Float64)startRecordTimeMills {
    double maxDiffTimeMills = 25;
    double minDiffTimeMills = 10;
    double audioSamplesTimeMills = CFAbsoluteTimeGetCurrent() * 1000 - startRecordTimeMills;
    int audioSampleRate = sampleRate;
    int audioChannels = 2;
    double dataAccumulateTimeMills = self.totalSampleCount * 1000 / audioSampleRate / audioChannels;
    if (dataAccumulateTimeMills <= audioSamplesTimeMills - maxDiffTimeMills) {
        double correctTimeMills = audioSamplesTimeMills - dataAccumulateTimeMills - minDiffTimeMills;
        int correctBufferSize = (int)(correctTimeMills / 1000.0 * audioSampleRate * audioChannels);
        LiveAudioPacket *audioPacket = new LiveAudioPacket();
        audioPacket->buffer = new short[correctBufferSize];
        memset(audioPacket->buffer, 0, correctBufferSize * sizeof(short));
        audioPacket->size = correctBufferSize;
        LivePacketPool::GetInstance()->pushAudioPacketToQueue(audioPacket);
        self.totalSampleCount += correctBufferSize;
        NSLog(@"Correct Time Mills is %lf\n", correctTimeMills);
        NSLog(@"audioSamplesTimeMills is %lf, dataAccumulateTimeMills is %lf\n", audioSamplesTimeMills, dataAccumulateTimeMills);
    }
    int sampleCount = buffer.mDataByteSize / 2;
    self.totalSampleCount += sampleCount;
    short *packetBuffer = new short[sampleCount];
    memcpy(packetBuffer, buffer.mData, buffer.mDataByteSize);
    LiveAudioPacket *audioPacket = new LiveAudioPacket();
    audioPacket->buffer = packetBuffer;
    audioPacket->size = sampleCount;
    LivePacketPool::GetInstance()->pushAudioPacketToQueue(audioPacket);
}

- (void)start {
    if (NULL == _consumer) {
        _consumer = new VideoConsumerThread();
    }
    __weak __typeof(self) weakSelf = self;
    dispatch_async(_consumerQueue, ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.startConnectTimeMills = [[NSDate date] timeIntervalSince1970] * 1000;
        LivePacketPool::GetInstance()->initRecordingVideoPacketQueue();
        LivePacketPool::GetInstance()->initAudioPacketQueue((int)strongSelf.audioSampleRate);
        LiveAudioPacketPool::GetInstance()->initAudioPacketQueue();
        int consumerInitCode = strongSelf->_consumer->init([strongSelf nsstring2char:strongSelf.rtmpURL],
                                                           (int)strongSelf.videoWidth,
                                                           (int)strongSelf.videoHeight,
                                                           (int)strongSelf.videoFrameRate,
                                                           (int)strongSelf.videoBitRate,
                                                           (int)strongSelf.audioSampleRate,
                                                           (int)strongSelf.audioChannels,
                                                           (int)strongSelf.audioBitRate,
                                                           [strongSelf nsstring2char:strongSelf.audioCodecName]);
        if (consumerInitCode >= 0) {
            strongSelf->_consumer->registerPublishTimeoutCallback(on_publish_timeout_callback, (__bridge void*)self);
            strongSelf->_consumer->startAsync();
            NSLog(@"cosumer open video output success...\n");
            [strongSelf startAudioEncoding];
            [strongSelf.delegate onConnectSuccess];
        } else {
            NSLog(@"cosumer open video output failed...\n");
            LivePacketPool::GetInstance()->destroyRecordingVideoPacketQueue();
            LivePacketPool::GetInstance()->destroyAudioPacketQueue();
            LiveAudioPacketPool::GetInstance()->destroyAudioPacketQueue();
            [strongSelf.delegate onConnectFailed];
        }
    });
}

- (void)stop {
    [self stopAudioEncoding];
    if (_consumer) {
        _consumer->stop();
        delete _consumer;
        _consumer = NULL;
    }
}

- (void)startAudioEncoding {
    _audioEncoder = new LiveAudioEncoderAdapter();
    _audioEncoder->init(LivePacketPool::GetInstance(),
                        (int)self.audioSampleRate,
                        (int)self.audioChannels,
                        (int)self.audioBitRate,
                        [self nsstring2char:self.audioCodecName]);
}

- (void)stopAudioEncoding {
    if (NULL != _audioEncoder) {
        _audioEncoder->destroy();
        delete _audioEncoder;
        _audioEncoder = NULL;
    }
}

- (char *)nsstring2char:(NSString *)path {
    NSUInteger len = [path length];
    char *filePath = (char *)malloc(sizeof(char) * (len + 1));
    [path getCString:filePath maxLength:len + 1 encoding:[NSString defaultCStringEncoding]];
    return filePath;
}

@end
