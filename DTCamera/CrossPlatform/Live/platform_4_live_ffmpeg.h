#ifndef PLATFORM_4_LIVE_FFMPEG
#define PLATFORM_4_LIVE_FFMPEG

#ifdef __ANDROID__

extern "C" {
#include "./../ThirdParty/FFmpeg/include/libavutil/opt.h"
#include "./../ThirdParty/FFmpeg/include/libavutil/mathematics.h"
#include "./../ThirdParty/FFmpeg/include/libavformat/avformat.h"
#include "./../ThirdParty/FFmpeg/include/libswscale/swscale.h"
#include "./../ThirdParty/FFmpeg/include/libswresample/swresample.h"
#include "./../ThirdParty/FFmpeg/include/libavutil/imgutils.h"
#include "./../ThirdParty/FFmpeg/include/libavutil/samplefmt.h"
#include "./../ThirdParty/FFmpeg/include/libavutil/timestamp.h"
#include "./../ThirdParty/FFmpeg/include/libavcodec/avcodec.h"
#include "./../ThirdParty/FFmpeg/include/libavfilter/avfiltergraph.h"
#include "./../ThirdParty/FFmpeg/include/libavfilter/avcodec.h"
#include "./../ThirdParty/FFmpeg/include/libavfilter/buffersink.h"
#include "./../ThirdParty/FFmpeg/include/libavfilter/buffersrc.h"
#include "./../ThirdParty/FFmpeg/include/libavutil/avutil.h"
#include "./../ThirdParty/FFmpeg/include/libswscale/swscale.h"
}

#elif defined(__APPLE__)	// IOS or OSX
extern "C" {
#include "libavutil/opt.h"
#include "libavutil/mathematics.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/imgutils.h"
#include "libavutil/samplefmt.h"
//#include "libavutil/timestamp.h"
#include "libavcodec/avcodec.h"
#include "libavfilter/avfiltergraph.h"
#include "libavfilter/avcodec.h"
#include "libavfilter/buffersink.h"
#include "libavfilter/buffersrc.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
}
#endif

#endif	// PLATFORM_4_LIVE_FFMPEG
