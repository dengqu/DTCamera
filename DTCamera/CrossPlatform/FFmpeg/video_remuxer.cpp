//
//  video_remuxer.cpp
//  DTCamera
//
//  Created by Dan Jiang on 2020/7/10.
//  Copyright © 2020 Dan Thought Studio. All rights reserved.
//

#include "video_remuxer.h"

#include <iostream>

VideoRemuxer::VideoRemuxer() {
    
}

void VideoRemuxer::Remuxing(const char *input_file, const char *output_file) {
    std::string in_file = std::string(input_file);
    std::string out_file = std::string(output_file);
    
    int ret = 0;
    
    av_register_all();
    
    AVFormatContext *ifmt_ctx = NULL;
    if ((ret = avformat_open_input(&ifmt_ctx, in_file.c_str(), 0, 0)) < 0) {
        std::cerr << "Could not open input file " << in_file.c_str() << std::endl;
        exit(1);
    }
    
    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        std::cerr << "Failed to retrieve input stream information" << std::endl;
        exit(1);
    }
    
    av_dump_format(ifmt_ctx, 0, in_file.c_str(), 0);
    
    AVFormatContext *ofmt_ctx = NULL;
    avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, out_file.c_str());
    if (!ofmt_ctx) {
        std::cerr << "Could not create output context " << out_file.c_str() << std::endl;
        exit(1);
    }

    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVStream *out_stream = avformat_new_stream(ofmt_ctx, in_stream->codec->codec);
        if (!out_stream) {
            std::cerr << "Failed allocating output stream" << std::endl;
            exit(1);
        }
        
        ret = avcodec_copy_context(out_stream->codec, in_stream->codec);
        if (ret < 0) {
            std::cerr << "Failed to copy context from input to output stream codec context" << std::endl;
            exit(1);
        }
        
        out_stream->codec->codec_tag = 0;
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
            out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
        
        out_stream->time_base = out_stream->codec->time_base;
    }

    av_dump_format(ofmt_ctx, 0, out_file.c_str(), 1);
    
    if (!(ofmt_ctx->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, out_file.c_str(), AVIO_FLAG_WRITE);
        if (ret < 0) {
            std::cerr << "Could not open output file " << out_file.c_str() << std::endl;
            exit(1);
        }
    }
    
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        std::cerr << "Error occurred when opening output file" << std::endl;
        exit(1);
    }
    
    AVPacket pkt;
    while (1) {
        AVStream *in_stream, *out_stream;
        
        ret = av_read_frame(ifmt_ctx, &pkt);
        if (ret < 0) {
            break;
        }
        
        in_stream = ifmt_ctx->streams[pkt.stream_index];
        out_stream = ofmt_ctx->streams[pkt.stream_index];
        
        pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF);
        pkt.dts = av_rescale_q_rnd(pkt.dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF);
        pkt.duration = av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
        pkt.pos = -1;
        
        ret = av_interleaved_write_frame(ofmt_ctx, &pkt);
        if (ret < 0) {
            std::cerr << "Error muxing packet" << std::endl;
            exit(1);
        }
        av_free_packet(&pkt);
    }
    
    av_write_trailer(ofmt_ctx);
    
    avformat_close_input(&ifmt_ctx);
    avformat_free_context(ofmt_ctx);
    
    std::cout << "finish remuxing " << in_file.c_str() << " to " << out_file.c_str() << std::endl;
}
