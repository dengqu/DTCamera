//
//  live_thread.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#include "live_thread.h"

LiveThread::LiveThread() {
    pthread_mutex_init(&mLock, NULL);
    pthread_cond_init(&mCondition, NULL);
}

LiveThread::~LiveThread() {
}

void LiveThread::start() {
    handleRun(NULL);
}

void LiveThread::startAsync() {
    pthread_create(&mThread, NULL, startThread, this);
}

int LiveThread::wait() {
    if (!mRunning) {
        printf("mRunning is false so return 0\n");
        return 0;
    }
    void *status;
    int ret = pthread_join(mThread, &status);
    printf("pthread_join thread return result is %d\n", ret);
    return ret;
}

void LiveThread::stop() {
}

void* LiveThread::startThread(void *ptr) {
    printf("starting thread\n");
    LiveThread *thread = (LiveThread *)ptr;
    thread->mRunning = true;
    thread->handleRun(ptr);
    thread->mRunning = false;
    return NULL;
}

void LiveThread::waitOnNotify() {
    pthread_mutex_lock(&mLock);
    pthread_cond_wait(&mCondition, &mLock);
    pthread_mutex_unlock(&mLock);
}

void LiveThread::notify() {
    pthread_mutex_lock(&mLock);
    pthread_cond_signal(&mCondition);
    pthread_mutex_unlock(&mLock);
}

void LiveThread::handleRun(void *ptr) {
}
