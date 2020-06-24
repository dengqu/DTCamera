//
//  AACDecoder.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/11.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AACDecoder : NSObject

- (instancetype)initWithInputFilePath:(NSString *)inputFilePath outputFilePath:(NSString *)outputFilePath;
- (void)startDecode;

@end

NS_ASSUME_NONNULL_END
