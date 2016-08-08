// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
#include "ethernet_wrappers.h"

unsafe void eth_send_packet(client interface ethernet_tx_if i, char *unsafe packet, unsigned n,
                          unsigned dst_port) {
  i.send_packet((char *restrict)packet, n, dst_port);
}