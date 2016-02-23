// Copyright (c) 2016, XMOS Ltd, All rights reserved

#ifndef __test_h__
#define __test_h__

#include "ethernet.h"

struct test_conf
{
  int disable_talker;
  int ptp_change_interval_min_sec; /* must not overlap with talker timestamp delay */
  int ptp_change_interval_max_sec;
  int ptp_master_rate;
  int talker_timestamp_delay_max_sec;
};

void test_app(client ethernet_cfg_if i_cfg, chanend c_ptp, streaming chanend c_tx_hp,
  client ethernet_rx_if i_rx, client ethernet_tx_if i_tx, struct test_conf &test_conf);

#endif
