//
//  AACEncoder.mm
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/10.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import "AACEncoder.h"
#import "audio_encoder.h"

@interface AACEncoder ()

@property (nonatomic, copy) NSString* inputFilePath;
@property (nonatomic, copy) NSString* outputFilePath;

@end

@implementation AACEncoder

- (instancetype)initWithInputFilePath:(NSString *)inputFilePath outputFilePath:(NSString *)outputFilePath {
    self = [super init];
    if (self) {
        self.inputFilePath = inputFilePath;
        self.outputFilePath = outputFilePath;
    }
    return self;
}

- (void)startEncode {
    AudioEncoder *encoder = new AudioEncoder();
    int bitsPerSample = 16;
    const char *codec_name = [@"libfdk_aac" cStringUsingEncoding:NSUTF8StringEncoding];
    int bitRate = 128 * 1024;
    int channels = 2;
    int sampleRate = 44100;
    encoder->init(bitRate, channels, sampleRate, bitsPerSample, [self.outputFilePath cStringUsingEncoding:NSUTF8StringEncoding], codec_name);
    int bufferSize = 1024 * 256;
    uint8_t* buffer = new uint8_t[bufferSize];
    FILE* inputFileHandle = fopen([self.inputFilePath cStringUsingEncoding:NSUTF8StringEncoding], "rb");
    size_t readBufferSize = 0;
    while ((readBufferSize = fread(buffer, 1, bufferSize, inputFileHandle)) > 0) {
        encoder->encode(buffer, (int)readBufferSize);
    }
    delete[] buffer;
    fclose(inputFileHandle);
    encoder->destroy();
    delete encoder;
}

@end
