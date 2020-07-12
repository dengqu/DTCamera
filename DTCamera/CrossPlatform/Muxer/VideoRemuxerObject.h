//
//  VideoRemuxerObject.h
//  DTCamera
//
//  Created by Dan Jiang on 2020/7/12.
//  Copyright © 2020 Dan Thought Studio. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoRemuxerObject : NSObject

- (instancetype)init;
- (void)remuxing:(NSString *)inputFilePath outputFilePath:(NSString *)outputFilePath;

@end

NS_ASSUME_NONNULL_END
