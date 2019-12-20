//
//  live_thread.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef live_thread_h
#define live_thread_h

#include "live_common.h"
#include <pthread.h>

class LiveThread {
public:
    LiveThread();
    ~LiveThread();
    
    void start();
    void startAsync();
    int wait();
    
    void waitOnNotify();
    void notify();
    virtual void stop();
    
protected:
    bool mRunning;
    virtual void handleRun(void *ptr);

protected:
    pthread_t mThread;
    pthread_mutex_t mLock;
    pthread_cond_t mCondition;
    
    static void* startThread(void *ptr);
};

#endif /* live_thread_h */
