//
//  LivePublisher.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/13.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LivePublisherDelegate <NSObject>

@required
- (void)onConnectSuccess;
- (void)onConnectFailed;
- (void)publishTimeOut;
- (void)pushRecordingVideoPacketToQueue;

@end

@interface LivePublisher : NSObject

@property (nonatomic, weak) id<LivePublisherDelegate> delegate;
@property (nonatomic, assign) double startConnectTimeMills;

- (instancetype)initWithRTMPURL:(NSString *)rtmpURL h264URL:(NSURL *)h264URL
     videoWidth:(NSInteger)videoWidth videoHeight:(NSInteger)videoHeight videoFrameRate:(NSInteger)videoFrameRate videoBitRate:(NSInteger)videoBitRate
                audioSampleRate:(NSInteger)audioSampleRate audioChannels:(NSInteger)audioChannels audioBitRate:(NSInteger)audioBitRate audioCodecName:(NSString *)audioCodecName;
- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps timestramp:(Float64)miliseconds;
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame timestramp:(Float64)miliseconds;
- (void)receiveAudioBuffer:(AudioBuffer)buffer sampleRate:(int)sampleRate startRecordTimeMills:(Float64)startRecordTimeMills;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
