//
//  video_remuxer.h
//  DTCamera
//
//  Created by Dan Jiang on 2020/7/10.
//  Copyright © 2020 Dan Thought Studio. All rights reserved.
//

#ifndef video_remuxer_h
#define video_remuxer_h

#include <string>

extern "C" {
    #include "libavformat/avformat.h"
    #include "libavcodec/avcodec.h"
    #include "libswresample/swresample.h"
    #include "libavutil/avutil.h"
}

class VideoRemuxer {
public:
    VideoRemuxer();
    void Remuxing(const char *input_file, const char *output_file);
};

#endif /* video_remuxer_h */
