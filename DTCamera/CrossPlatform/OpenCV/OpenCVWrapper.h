//
//  OpenCVWrapper.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/21.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

- (void)filterImage:(unsigned char *)image width:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
