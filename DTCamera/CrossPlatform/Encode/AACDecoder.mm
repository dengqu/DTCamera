//
//  AACDecoder.mm
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/11.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import "AACDecoder.h"
#import "audio_decoder.h"

#define CHANNEL_PER_FRAME    2
#define BITS_PER_CHANNEL     16
#define BITS_PER_BYTE        8

@interface AACDecoder ()

@property (nonatomic, copy) NSString* inputFilePath;
@property (nonatomic, copy) NSString* outputFilePath;

@end

@implementation AACDecoder

- (instancetype)initWithInputFilePath:(NSString *)inputFilePath outputFilePath:(NSString *)outputFilePath {
    self = [super init];
    if (self) {
        self.inputFilePath = inputFilePath;
        self.outputFilePath = outputFilePath;
    }
    return self;
}

- (void)startDecode {
    AudioDecoder *tempDecoder = new AudioDecoder();
    int metaData[2];
    tempDecoder->getMusicMeta([self.inputFilePath cStringUsingEncoding:NSUTF8StringEncoding], metaData);
    delete tempDecoder;
    int sampleRate = metaData[0];
    int byteCountPerSec = sampleRate * CHANNEL_PER_FRAME * BITS_PER_CHANNEL / BITS_PER_BYTE;
    int packetBufferSize = (int)((byteCountPerSec / 2) * 0.2);
    AudioDecoder *decoder = new AudioDecoder();
    decoder->init([self.inputFilePath cStringUsingEncoding:NSUTF8StringEncoding], packetBufferSize);
    FILE* outputFile = fopen([self.outputFilePath cStringUsingEncoding:NSUTF8StringEncoding], "wb+");
    
    while (true) {
        AudioPacket *packet = decoder->decodePacket();
        if (packet->size == -1) {
            break;
        }
        fwrite(packet->buffer, sizeof(short), packet->size, outputFile);
    }
    
    if (NULL != decoder) {
        decoder->destroy();
        delete decoder;
        decoder = NULL;
    }
    if (NULL != outputFile) {
        fclose(outputFile);
        outputFile = NULL;
    }
}

@end
