// Copyright (c) 2011-2017, XMOS Ltd, All rights reserved
#ifndef __media_clock_internal_h__
#define __media_clock_internal_h__
#include <xccompat.h>
#include "default_avb_conf.h"
#include "avb.h"

#ifndef AVB_NUM_MEDIA_CLOCKS
#define AVB_NUM_MEDIA_CLOCKS 1
#endif

#ifndef MAX_CLK_CTL_CLIENTS
#define MAX_CLK_CTL_CLIENTS 8
#endif

#ifndef PLL_TO_WORD_MULTIPLIER
#define PLL_TO_WORD_MULTIPLIER 100
#endif

/** A description of a media clock */
typedef struct media_clock_t {
  media_clock_info_t info;
  unsigned int wordLength;
  unsigned int baseLengthRemainder;
  unsigned int wordTime;
  unsigned int baseLength;
  unsigned int lowBits;
  int count;
  unsigned int next_event;
  unsigned int bit;
} media_clock_t;


#define WC_FRACTIONAL_BITS 16

// The number of ticks between period clock recovery checks
#define CLOCK_RECOVERY_PERIOD  (1<<21)

void init_media_clock_recovery(NULLABLE_RESOURCE(chanend,ptp_svr),
                                       int clock_info,
                                       unsigned int clk_time,
                                       unsigned int rate);

unsigned int update_media_clock(NULLABLE_RESOURCE(chanend,ptp_svr),
                                int clock_index,
                                REFERENCE_PARAM(const media_clock_t, mclock),
                                unsigned int t2,
                                int period);


void update_media_clock_stream_info(int clock_index,
                                    unsigned int local_ts,
                                    unsigned int outgoing_ptp_ts,
                                    unsigned int presentation_ts,
                                    int locked,
                                    int fill);

void inform_media_clock_of_lock(int clock_index);

#endif
