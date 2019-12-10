//
//  AACEncoder.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/10.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AACEncoder : NSObject

- (instancetype)initWithInputFilePath:(NSString *)inputFilePath outputFilePath:(NSString *)outputFilePath;
- (void)startEncode;

@end

NS_ASSUME_NONNULL_END
