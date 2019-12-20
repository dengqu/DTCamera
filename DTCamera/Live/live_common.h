//
//  live_common.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_common_h
#define live_common_h

#include <stdio.h>
#include <string>
#include <sys/time.h>

typedef unsigned char byte;

#ifndef MIN
#define MIN(a, b)  (((a) < (b)) ? (a) : (b))
#endif

namespace platform_4_live {

static inline long getCurrentTimeMills() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

static inline long getCurrentTimeSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec;
}

}

#endif /* live_common_h */
