// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef __avb_conf_h__
#define __avb_conf_h__

#include "app_config.h"

/* Some of the configuration depends on the app_config.h file included above */

/******** ETHERNET MAC CONFIGURATION PARAMETERS *************************************************/

#define NUM_ETHERNET_PORTS 1
#define NUM_ETHERNET_MASTER_PORTS 1

/******** ENDPOINT AUDIO AND CLOCKING PARAMETERS ************************************************/

/* Talker configuration */
#if AVB_DEMO_ENABLE_TALKER

/** The total number of AVB sources (streams that are to be transmitted). */
#define AVB_NUM_SOURCES 4
/** The total number or Talker components (typically the number of
  * tasks running the  :c:func:`avb_1722_talker` function). */
#define AVB_NUM_TALKER_UNITS 1
/** The total number of media inputs (typically number of I2S input channels). */
#define AVB_NUM_MEDIA_INPUTS 32
/** Enable the 1722.1 Talker functionality */
#define AVB_1722_1_TALKER_ENABLED 1

#else

#define AVB_NUM_SOURCES 0
#define AVB_NUM_TALKER_UNITS 0
#define AVB_NUM_MEDIA_INPUTS 0
#define AVB_1722_1_TALKER_ENABLED 0

#endif

/* Listener configuration */
#if AVB_DEMO_ENABLE_LISTENER

/** The total number of AVB sinks (incoming streams that can be listened to) */
#define AVB_NUM_SINKS 4
/** The total number or listener components
  * (typically the number of tasks running the  :c:func:`avb_1722_listener` function) */
#define AVB_NUM_LISTENER_UNITS 1
/** The total number of media outputs (typically the number of I2S output channels). */
#define AVB_NUM_MEDIA_OUTPUTS 32
/** Enable the 1722.1 Listener functionality */
#define AVB_1722_1_LISTENER_ENABLED 1

#else

#define AVB_NUM_SINKS 0
#define AVB_NUM_LISTENER_UNITS 0
#define AVB_NUM_MEDIA_OUTPUTS 0
#define AVB_1722_1_LISTENER_ENABLED 0

#endif

/** The maximum number of channels permitted per 1722 Talker stream */
#define AVB_MAX_CHANNELS_PER_TALKER_STREAM 8
/** The maximum number of channels permitted per 1722 Listener stream */
#define AVB_MAX_CHANNELS_PER_LISTENER_STREAM 8

/** Enable combination of the media clock server and PTP server in a single core */
#define COMBINE_MEDIA_CLOCK_AND_PTP 1

/** Use 61883-6 audio format for 1722 streams */
#define AVB_1722_FORMAT_61883_6 1

/** The number of components in the endpoint that will register and initialize media FIFOs
    (typically an audio interface component such as I2S). */
#define AVB_NUM_MEDIA_UNITS 1

/** The number of media clocks in the endpoint. Typically the number of clock domains, each with a
  * separate PLL and master clock. */
#define AVB_NUM_MEDIA_CLOCKS 1

/** The maximum sample rate in Hz of audio that is to be input or output */
#define AVB_MAX_AUDIO_SAMPLE_RATE 48000

// This is the number of master clocks in a word clock
#define MASTER_TO_WORDCLOCK_RATIO 512

/******** 1722.1 PARAMETERS *****************************************************************/

/** Enable 1722.1 AVDECC on the entity */
#define AVB_ENABLE_1722_1 1

#define AVB_1722_1_ADP_ENTITY_CAPABILITIES (AVB_1722_1_ADP_ENTITY_CAPABILITIES_AEM_SUPPORTED| \
                                            AVB_1722_1_ADP_ENTITY_CAPABILITIES_CLASS_A_SUPPORTED| \
                                            AVB_1722_1_ADP_ENTITY_CAPABILITIES_GPTP_SUPPORTED| \
                                            AVB_1722_1_ADP_ENTITY_CAPABILITIES_AEM_IDENTIFY_CONTROL_INDEX_VALID)

#define AVB_1722_1_ADP_MODEL_ID 0x1234

enum aem_control_indices {
    DESCRIPTOR_INDEX_CONTROL_IDENTIFY = 0,
};

#define AVB_1722_1_FIRMWARE_UPGRADE_ENABLED 0

#define AVB_1722_1_FAST_CONNECT_ENABLED 0

/** Enable 1722.1 Controller functionality on the entity. */
#define AVB_1722_1_CONTROLLER_ENABLED 0

#define FLASH_MAX_UPGRADE_IMAGE_SIZE (128 * 1024)
#define FLASH_PAGE_SIZE (256)

#endif
