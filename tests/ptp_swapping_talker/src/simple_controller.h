// Copyright (c) 2016, XMOS Ltd, All rights reserved

#ifndef __simple_controller_h__
#define __simple_controller_h__

#include "ethernet.h"

void simple_controller_init(client ethernet_cfg_if i_cfg, client ethernet_rx_if i_rx, const unsigned char src_mac_addr[6],
  unsigned char stream_id[8]);

void simple_controller_periodic(client ethernet_tx_if i_tx);

void simple_controller_packet_received(const unsigned char packet_buf[], const ethernet_packet_info_t &packet_info);

#endif
