//
//  VideoRemuxerObject.m
//  DTCamera
//
//  Created by Dan Jiang on 2020/7/12.
//  Copyright © 2020 Dan Thought Studio. All rights reserved.
//

#import "VideoRemuxerObject.h"

#include "video_remuxer.h"

@interface VideoRemuxerObject ()

@property (nonatomic, assign) std::shared_ptr<VideoRemuxer> remuxer;

@end

@implementation VideoRemuxerObject

- (instancetype)init {
    self = [super init];
    if (self) {
        self.remuxer = std::make_shared<VideoRemuxer>();
    }
    return self;
}

- (void)remuxing:(NSString *)inputFilePath outputFilePath:(NSString *)outputFilePath {
    self.remuxer->Remuxing([inputFilePath UTF8String], [outputFilePath UTF8String]);
}

@end
