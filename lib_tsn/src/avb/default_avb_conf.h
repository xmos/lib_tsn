// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef __default_avb_conf_h__
#define __default_avb_conf_h__

#ifdef __avb_conf_h_exists__
#include "avb_conf.h"
#endif

#ifndef AVB_NUM_SOURCES
#define AVB_NUM_SOURCES 1
#endif

#ifndef AVB_NUM_TALKER_UNITS
#define AVB_NUM_TALKER_UNITS 1
#endif

#ifndef AVB_NUM_MEDIA_INPUTS
#define AVB_NUM_MEDIA_INPUTS 8
#endif

#ifndef AVB_1722_1_TALKER_ENABLED
#define AVB_1722_1_TALKER_ENABLED 1
#endif

#ifndef AVB_NUM_SINKS
#define AVB_NUM_SINKS 1
#endif

#ifndef AVB_NUM_LISTENER_UNITS
#define AVB_NUM_LISTENER_UNITS 1
#endif

#ifndef AVB_NUM_MEDIA_OUTPUTS
#define AVB_NUM_MEDIA_OUTPUTS 8
#endif

#ifndef AVB_1722_1_LISTENER_ENABLED
#define AVB_1722_1_LISTENER_ENABLED 1
#endif

#ifndef AVB_MAX_CHANNELS_PER_TALKER_STREAM
#define AVB_MAX_CHANNELS_PER_TALKER_STREAM 8
#endif

#ifndef AVB_MAX_CHANNELS_PER_LISTENER_STREAM
#define AVB_MAX_CHANNELS_PER_LISTENER_STREAM 8
#endif

#ifndef AVB_1722_FORMAT_61883_6
#define AVB_1722_FORMAT_61883_6 1
#endif

#ifndef AVB_NUM_MEDIA_UNITS
#define AVB_NUM_MEDIA_UNITS 1
#endif

#ifndef AVB_NUM_MEDIA_CLOCKS
#define AVB_NUM_MEDIA_CLOCKS 1
#endif

#ifndef AVB_MAX_AUDIO_SAMPLE_RATE
#define AVB_MAX_AUDIO_SAMPLE_RATE 48000
#endif

#ifndef AVB_ENABLE_1722_1
#define AVB_ENABLE_1722_1 0
#endif

#ifndef AVB_ENABLE_1722_MAAP
#define AVB_ENABLE_1722_MAAP 0
#endif

#ifndef FLASH_MAX_UPGRADE_IMAGE_SIZE
#define FLASH_MAX_UPGRADE_IMAGE_SIZE (128 * 1024)
#endif

#ifndef FLASH_PAGE_SIZE
#define FLASH_PAGE_SIZE (256)
#endif

#endif // __default_avb_conf_h__