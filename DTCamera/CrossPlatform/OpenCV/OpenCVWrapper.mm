//
//  OpenCVWrapper.m
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/21.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#import <opencv2/opencv.hpp> // import opencv should go first
#import "OpenCVWrapper.h"

@implementation OpenCVWrapper

- (void)filterImage:(unsigned char *)image width:(int)width height:(int)height {
    cv::Mat bgraImage = cv::Mat(height, width, CV_8UC4, image);
    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            bgraImage.at<cv::Vec<uint8_t, 4>>(y, x)[0] = 0; // De-blue
        }
    }
}

@end
