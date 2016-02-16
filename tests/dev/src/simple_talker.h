// Copyright (c) 2016, XMOS Ltd, All rights reserved

#ifndef __simple_talker_h__
#define __simple_talker_h__

#include "gptp.h"

typedef int simple_talker_config_t;

simple_talker_config_t simple_talker_init(unsigned char packet_buf[], int packet_buf_size,
  const unsigned char src_mac_addr[6], const unsigned char stream_id[8]);

int simple_talker_create_packet(simple_talker_config_t config,
  unsigned char packet_buf[], int packet_buf_size, ptp_time_info_mod64 time_info, int local_timestamp, int sample_value);

#endif
