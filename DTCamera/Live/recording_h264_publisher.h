//
//  recording_h264_publisher.h
//  DTCamera
//
//  Created by Dan Jiang on 2019/12/17.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

#ifndef recording_h264_publisher_h
#define recording_h264_publisher_h

#include "recording_publisher.h"

class RecordingH264Publisher: public RecordingPublisher {
public:
    RecordingH264Publisher();
    virtual ~RecordingH264Publisher();
    
public:
    virtual int stop();
    
protected:
    int lastPresentationTimeMs;
    
    virtual int write_video_frame(AVFormatContext *oc, AVStream *st);
    virtual double getVideoStreamTimeInSecs();
    
    uint32_t findStartCode(uint8_t *in_pBuffer, uint32_t in_ui32BufferSize,
                           uint32_t in_ui32Code, uint32_t& out_ui32ProcessedBytes);
    
    void parseH264SequenceHeader(uint8_t *in_pBuffer, uint32_t in_ui32Size,
                                 uint8_t **inout_pBufferSPS, int &inout_ui32sizeSPS,
                                 uint8_t **inout_pBufferPPS, int &inout_ui32sizePPS);
};

#endif /* recording_h264_publisher_h */
